# frozen_string_literal: true

require_relative 'errors'
require_relative 'extensions'

require 'cbor'
require 'stringio'

module Oxygene

  #
  # Parser for STAR archives (experimental).
  #

  class STARArchive
    using Oxygene::Extensions

    MAGIC_PREFIX = "\x2A\x6C\x01\x00"

    attr_reader :data_pairs, :data_map, :metadata

    def initialize(data)
      @buffer = StringIO.new(data)
      @data_pairs = []
      @data_map = {}

      read_header(@buffer)

      loop do
        had_data = read_section(@buffer)
        break if !had_data
      end

      @buffer = nil
    end

    def inspect
      vars = (instance_variables - [:@data_map]).map { |v|
        "#{v}=#{instance_variable_get(v).inspect}"
      }

      "#<#{self.class}:0x#{object_id} #{vars.join(", ")}>"
    end


    private

    def read_header(buffer)
      magic = buffer.read(MAGIC_PREFIX.length)
      raise DecodeError.new("Missing initial magic bytes") unless magic == MAGIC_PREFIX

      header_len = read_varint(buffer)
      raise DecodeError.new("Header length cannot be 0") if header_len == 0

      header_data = buffer.read(header_len)

      unless header_data.length == header_len
        raise DecodeError.new("Header too short: got #{header_data.length} bytes, expected #{header_len}")
      end

      begin
        metadata = CBOR.decode(header_data)
      rescue StandardError
        raise DecodeError.new("Malformed CBOR data")
      end

      raise DecodeError.new("Metadata object should be a hash") unless metadata.is_a?(Hash)

      type = metadata['$type']
      raise DecodeError.new("Missing '$type' field") if type.nil?
      raise DecodeError.new("Invalid '$type' field: #{type.inspect}") unless type.is_a?(String)

      @type = type
      @metadata = metadata
    end

    def read_section(buffer)
      control_byte = buffer.getbyte

      case control_byte
      when 0
        # end of file
        if @buffer.eof?
          return false
        else
          raise DecodeError, "Unexpected content after end of file marker"
        end
      when 1
        # continue with the next section
      when nil
        raise DecodeError, "Unexpected end of file"
      else
        raise DecodeError, "Unexpected control byte: #{control_byte}"
      end

      k_len = read_varint(buffer)
      raise DecodeError, "Unexpected end of file" if k_len.nil?

      key = buffer.read(k_len)
      raise DecodeError, "Truncated key data" if key.nil? || key.length != k_len

      v_len = read_varint(buffer)
      raise DecodeError, "Unexpected end of file" if v_len.nil?

      value = buffer.read(v_len)
      raise DecodeError, "Truncated value data" if value.nil? || value.length != v_len

      @data_pairs << [key, value]
      @data_map[key] = value

      true
    end

    def read_varint(buffer)
      pos_before = buffer.pos
      value = buffer.read_varint
      length = buffer.pos - pos_before

      raise DecodeError, "Varint length exceeds limit" if length > 9

      value
    end
  end
end
