# frozen_string_literal: true

require_relative 'car_section'
require_relative 'cid'
require_relative 'errors'
require_relative 'extensions'

require 'base64'
require 'cbor'
require 'stringio'

# CAR v1: https://ipld.io/specs/transport/car/carv1/
# multicodec codes: https://github.com/multiformats/multicodec/blob/master/table.csv

module Oxygene
  class CARArchive
    using Oxygene::Extensions

    SECTION_PREFIX = "\x01\x71\x12\x20".b.freeze
    private_constant :SECTION_PREFIX

    attr_reader :roots

    def initialize(data)
      @sections = []
      @section_map = {}
      @buffer = StringIO.new(data)
      @map_needs_update = false

      read_header(@buffer)
    end

    def section_with_cid(cid, use_map: false, return_body: true)
      if found_section = find_parsed_section(cid, use_map)
        return (return_body ? found_section.json_body : found_section)
      end

      if found_section = parse_sections_until_match(cid, use_map)
        return (return_body ? found_section.json_body : found_section)
      end

      nil
    end

    def parsed_sections
      @sections.dup.freeze
    end

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

    def self.make_cid_link(cid)
      { '$link' => CID.from_cbor_tag(cid) }
    end

    def self.make_bytes(data)
      string = Base64.strict_encode64(data)
      string.chomp!('=') while string.getbyte(-1) == 61

      { '$bytes' => string }
    end

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

      section_data = buffer.read(len)
      raise DecodeError.new("Section too short: #{section_data}") unless section_data.length == len

      if section_data.start_with?(SECTION_PREFIX)
        cid_data = section_data.byteslice(0, 36)
        body_data = section_data.byteslice(36..)

        raise DecodeError.new("CID too short: #{cid_data}") unless cid_data.length == 36

        cid_data.prepend(CID::BINARY_PREFIX)
        cid = CID.new(cid_data, true, true)
      else
        sbuffer = StringIO.new(section_data)

        version = sbuffer.read_varint
        raise UnsupportedError.new("Unexpected CID version: #{version}") unless version == 1

        codec = sbuffer.read_varint
        raise UnsupportedError.new("Unexpected CID codec: #{codec}") unless codec == 0x71  # dag-cbor

        hash = sbuffer.read_varint
        raise UnsupportedError.new("Unexpected CID hash: #{hash}") unless hash == 0x12  # sha2-256

        clen = sbuffer.read_varint
        raise UnsupportedError.new("Unexpected CID length: #{clen}") unless clen == 32

        raise UnsupportedError.new("Non-canonical CID prefix")
      end

      new_section = CARSection.new(cid, body_data)

      @sections << new_section

      new_section
    end
  end
end
