# frozen_string_literal: true

require_relative 'car_section'
require_relative 'cid'
require_relative 'errors'
require_relative 'extensions'

require 'base64'
require 'cbor'
require 'stringio'

module Oxygene

  #
  # Parses a Content Addressable Archive (CAR) bundle loaded e.g. from an ATProto firehose
  # message or from a repo .car exported from a PDS. The header part is decoded immediately,
  # while the subsequent body/data sections are lazily decoded only as requested.
  #
  # Only CAR version v1 is supported, and only limited to the features or variants used in ATProto
  # (e.g. CIDs only in the v1 version as defined in [DASL](https://dasl.ing)).
  #
  # Related specifications:
  #
  # - [IPLD CAR v1 spec](https://ipld.io/specs/transport/car/carv1/)
  # - [DASL CAR](https://dasl.ing/car.html)
  # - [ATProto CAR file serialization](https://atproto.com/specs/repository#car-file-serialization)
  # - [ATProto data model](https://atproto.com/specs/data-model)
  # - [multicodec](https://github.com/multiformats/multicodec),
  #   [multihash](https://github.com/multiformats/multihash)
  #   and [multibase](https://github.com/multiformats/multibase)
  #

  class CARArchive
    using Oxygene::Extensions

    # @return [Array<CID>] array of root CIDs listed in the archive header
    attr_reader :roots


    # Creates a CAR archive reader from an in-memory CAR file.
    #
    # @param data [String] CAR archive file as a binary string
    # @raise [DecodeError] if the archive header has missing or invalid fields
    # @raise [UnsupportedError] if the archive uses an unsupported CAR version
    #
    def initialize(data)
      @sections = []
      @section_map = {}
      @buffer = StringIO.new(data)
      @map_needs_update = false

      read_header(@buffer)
    end

    # Looks up a section with a given CID in the archive, decoding sections as needed.
    #
    # Sections are parsed lazily – if the requested section has already been loaded,
    # it's returned without parsing any more parts of the archive, otherwise unread
    # sections are parsed only until a match is found.
    #
    # When making repeated lookups for sections in one archive, e.g. when walking
    # the MST tree of a CAR repo, pass the `use_map: true` option, which tells
    # `CARArchive` to build and use an index that maps CIDs to sections for quicker lookup
    # (otherwise, parsed sections are searched sequentially). For performance, this isn't
    # enabled by default, since the common case of processing firehose commit messages only
    # does a single lookup to find the record data.
    #
    # The CID may be passed as either an {Oxygene::CID} object, or its {CID#cbor_form} string.
    #
    # @param cid [CID, String] a CID object or its binary CBOR representation, including the leading null byte
    # @param use_map [Boolean] whether to use and update the lookup index that maps CIDs to sections
    # @param return_body [Boolean] whether to return the section's JSON body directly instead of an {Oxygene::CARSection} object
    #
    # @return [Hash, Array, CARSection, nil] the requested section or its decoded body converted to ATProto JSON, or nil if not found
    # @raise [DecodeError] if a section is truncated or malformed
    # @raise [UnsupportedError] if a section uses an unsupported CID encoding

    def section_with_cid(cid, use_map: false, return_body: true)
      if found_section = find_parsed_section(cid, use_map)
        return (return_body ? found_section.json_body : found_section)
      end

      if found_section = parse_sections_until_match(cid, use_map)
        return (return_body ? found_section.json_body : found_section)
      end

      nil
    end

    # Returns the list of archive sections that have been parsed so far,
    # without parsing any more sections.
    #
    # @return [Array<CARSection>] sections parsed so far, in archive order

    def parsed_sections
      @sections.dup.freeze
    end

    # Parses all sections in the archive if they haven't been loaded yet, and
    # returns the list of all sections in the order as listed in the archive.
    #
    # Once all sections have been read, the original archive data buffer is
    # released so it can be garbage-collected.
    #
    # @return [Array<CARSection>] all sections in the archive
    # @raise [DecodeError] if a section is truncated or malformed
    # @raise [UnsupportedError] if a section uses an unsupported CID encoding

    def sections
      if @buffer
        if !@buffer.eof?
          read_section(@buffer) while !@buffer.eof?
          @map_needs_update = true
        end

        @buffer = nil
      end

      @sections
    end

    # @api private
    #
    # Converts decoded CBOR values to their ATProto-specific JSON representation.
    #
    # The passed hash or array is converted recursively in place. The conversion involves:
    # - replacing binary strings with `$bytes` objects with Base64-encoded data
    # - converting CBOR CID tags to `$link` objects holding an {Oxygene::CID}
    #
    # @param object [Hash, Array] decoded CBOR object to convert
    # @return [Hash, Array] the same object, updated in place
    # @raise [DecodeError] if the top-level value is not a hash or array

    def self.convert_data(object)
      if object.is_a?(Hash)
        object.each do |k, v|
          if v.is_a?(Hash) || v.is_a?(Array)
            convert_data(v)
          elsif v.is_a?(CBOR::Tagged)
            object[k] = make_cid_link(v)
          elsif v.is_a?(String) && v.encoding == Encoding::ASCII_8BIT
            object[k] = make_bytes(v)
          end
        end
      elsif object.is_a?(Array)
        object.each_with_index do |v, i|
          if v.is_a?(Hash) || v.is_a?(Array)
            convert_data(v)
          elsif v.is_a?(CBOR::Tagged)
            object[i] = make_cid_link(v)
          elsif v.is_a?(String) && v.encoding == Encoding::ASCII_8BIT
            object[i] = make_bytes(v)
          end
        end
      else
        raise DecodeError, "Unexpected value type in record: #{object}"
      end
    end

    # @api private
    #
    # Converts a CBOR CID tag to an ATProto JSON
    # [$link object](https://atproto.com/specs/data-model#json-representation).
    #
    # @param cid [CBOR::Tagged] CBOR tag containing the CID binary data
    # @return [Hash{String => CID}] a `$link` JSON object
    # @raise [DecodeError] if the value is not a supported CID

    def self.make_cid_link(cid)
      { '$link' => CID.from_cbor_tag(cid) }
    end

    # @api private
    #
    # Converts a binary string to an ATProto JSON
    # [$bytes object](https://atproto.com/specs/data-model#json-representation).
    #
    # @param data [String] binary data to encode
    # @return [Hash{String => String}] a `$bytes` JSON object

    def self.make_bytes(data)
      string = Base64.strict_encode64(data)
      string.chomp!('=') while string.getbyte(-1) == 61

      { '$bytes' => string }
    end

    # Returns a string with a representation of the object for debugging purposes.
    # @return [String]

    def inspect
      vars = (instance_variables - [:@section_map]).map { |v|
        if v == :@sections && @buffer
          "#{v}=[...]"
        else
          "#{v}=#{instance_variable_get(v).inspect}"
        end
      }

      "#<#{self.class}:0x#{object_id} #{vars.join(", ")}>"
    end


    private

    def find_parsed_section(cid, use_map)
      if use_map
        if @map_needs_update
          @sections.each { |s| @section_map[s.cid.cbor_form] ||= s }
          @map_needs_update = false
        end

        key = cid.is_a?(CID) ? cid.cbor_form : cid
        @section_map[key]
      else
        if cid.is_a?(CID)
          @sections.detect { |s| s.cid == cid }
        else
          @sections.detect { |s| s.cid.cbor_form == cid }
        end
      end
    end

    def parse_sections_until_match(cid, use_map)
      return if @buffer.nil?

      is_cid = cid.is_a?(CID)

      while !@buffer.eof?
        section = read_section(@buffer)

        if use_map
          @section_map[section.cid.cbor_form] = section
        else
          @map_needs_update = true
        end

        match = is_cid ? section.cid == cid : section.cid.cbor_form == cid
        return section if match
      end

      @buffer = nil
    end

    def read_header(buffer)
      len = buffer.read_varint
      raise DecodeError.new("Header length cannot be 0") if len == 0

      header_data = buffer.read(len)
      raise DecodeError.new("Header too short: #{header_data}") unless header_data.length == len

      header = CBOR.decode(header_data)
      raise DecodeError.new("Metadata object should be a hash") unless header.is_a?(Hash)
      raise UnsupportedError.new("Unexpected CAR version: #{header['version']}") unless header['version'] == 1

      roots = header['roots']
      raise DecodeError.new("Missing 'roots' field") if roots.nil?
      raise DecodeError.new("Invalid 'roots' field: #{roots.inspect}") unless roots.is_a?(Array)

      @roots = header['roots'].map { |x|
        if x.is_a?(CBOR::Tagged) && x.tag == 42
          CID.from_cbor_tag(x)
        else
          raise DecodeError.new("Unexpected value in the roots array: #{x.inspect}")
        end
      }.freeze
    end

    def read_section(buffer)
      len = buffer.read_varint
      raise DecodeError, "Section length is too short: #{len}" if len < 36

      # TODO: verify content CIDs
      cid_data = buffer.read(36)
      body_data = buffer.read(len - 36)

      unless cid_data&.bytesize == 36 && body_data&.bytesize == len - 36
        raise DecodeError, "Section is truncated"
      end

      cid_data.prepend(CID::CBOR_TAG_PREFIX)
      cid = CID.new(cid_data, binary: true, cbor_prefix: true, codec: :drisl)

      new_section = CARSection.new(cid, body_data)

      @sections << new_section

      new_section
    end
  end
end
