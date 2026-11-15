# frozen_string_literal: true

require_relative 'car_section'
require_relative 'cbor'
require_relative 'cid'
require_relative 'errors'
require_relative 'varint_reader'

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
    # @return [Array<CID>] array of root CIDs listed in the archive header
    attr_reader :roots


    # Creates a CAR archive reader from an in-memory CAR file.
    #
    # @param data [String] CAR archive file as a binary string
    # @raise [ArgumentError] if the data is not a binary string
    # @raise [DecodeError] if the archive header has missing or invalid fields
    # @raise [UnsupportedError] if the archive uses an unsupported CAR version
    #
    def initialize(data)
      unless data.is_a?(String) && data.encoding == Encoding::BINARY
        raise ArgumentError, "data should be a binary string"
      end

      @sections = []
      @section_map = {}
      @buffer = data.freeze
      @size = data.bytesize
      @offset = 0
      @varint_reader = VarintReader.new(data)
      @map_needs_update = false

      read_header
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
        if @offset != @size
          @map_needs_update = true
          read_section while @offset != @size
        end

        release_buffer
      end

      @sections
    end

    # Returns a string with a representation of the object for debugging purposes.
    # @return [String]

    def inspect
      vars = (instance_variables - [:@section_map, :@varint_reader]).map { |v|
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

      while @offset != @size
        section = read_section

        if use_map
          @section_map[section.cid.cbor_form] = section
        else
          @map_needs_update = true
        end

        match = is_cid ? section.cid == cid : section.cid.cbor_form == cid
        return section if match
      end

      release_buffer
    end

    def release_buffer
      @buffer = nil
      @varint_reader = nil
    end

    def read_header
      len = @varint_reader.read_next
      raise DecodeError.new("Header length cannot be 0") if len == 0

      offset = @varint_reader.offset
      finish = offset + len

      if finish > @size
        raise DecodeError, "Header too short: got #{@size - offset} bytes, expected #{len}"
      end

      header_data = @buffer.byteslice(offset, len)
      header = Oxygene::CBOR.decode(header_data)
      raise DecodeError.new("Metadata object should be a hash") unless header.is_a?(Hash)
      raise UnsupportedError.new("Unexpected CAR version: #{header['version']}") unless header['version'] == 1

      roots = header['roots']
      raise DecodeError.new("Missing 'roots' field") if roots.nil?
      raise DecodeError.new("Invalid 'roots' field: #{roots.inspect}") unless roots.is_a?(Array)

      roots.each do |root|
        raise DecodeError, "Unexpected value in the roots array: #{root.inspect}" unless root.is_a?(CID)
      end

      @roots = roots.freeze
      @offset = finish
    end

    def read_section
      len = @varint_reader.read(@offset)
      raise DecodeError, "Section length is too short: #{len}" if len < 36

      offset = @varint_reader.offset
      finish = offset + len
      raise DecodeError, "Section is truncated" if finish > @size

      # TODO: verify content CIDs
      cid_data = @buffer.byteslice(offset, 36)
      cid_data.prepend(CID::CBOR_TAG_PREFIX)
      cid = CID.new(cid_data, binary: true, cbor_prefix: true, codec: :drisl)

      body_data = @buffer.byteslice(offset + 36, len - 36)
      new_section = CARSection.new(cid, body_data)

      @sections << new_section
      @offset = finish

      new_section
    end
  end
end
