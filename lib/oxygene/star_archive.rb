# frozen_string_literal: true

require_relative 'cbor'
require_relative 'errors'
require_relative 'varint_reader'

module Oxygene

  #
  # Parser for STAR archives (experimental).
  #

  class STARArchive
    MAGIC_PREFIX = "\x2A\x6C\x01\x00"

    attr_reader :data_pairs, :data_map, :metadata

    def initialize(data)
      unless data.is_a?(String) && data.encoding == Encoding::BINARY
        raise ArgumentError, "data should be a binary string"
      end

      @buffer = data.freeze
      @size = data.bytesize
      @offset = 0
      @varint_reader = VarintReader.new(data)
      @data_pairs = []
      @data_map = {}

      read_header

      while true
        had_data = read_section
        break if !had_data
      end

      @buffer = nil
      @varint_reader = nil
    end

    def inspect
      vars = (instance_variables - [:@data_map, :@varint_reader]).map { |v|
        "#{v}=#{instance_variable_get(v).inspect}"
      }

      "#<#{self.class}:0x#{object_id} #{vars.join(", ")}>"
    end


    private

    def read_header
      magic_size = MAGIC_PREFIX.bytesize
      magic = @buffer.byteslice(0, magic_size)
      raise DecodeError.new("Missing initial magic bytes") unless magic == MAGIC_PREFIX

      header_len = @varint_reader.read(magic_size)
      raise DecodeError.new("Header length cannot be 0") if header_len == 0

      offset = @varint_reader.offset
      finish = offset + header_len

      if finish > @size
        raise DecodeError.new("Header too short: got #{@size - offset} bytes, expected #{header_len}")
      end

      header_data = @buffer.byteslice(offset, header_len)

      begin
        metadata = Oxygene::CBOR.decode(header_data)
      rescue DecodeError, UnsupportedError
        raise DecodeError.new("Malformed CBOR data")
      end

      raise DecodeError.new("Metadata object should be a hash") unless metadata.is_a?(Hash)

      type = metadata['$type']
      raise DecodeError.new("Missing '$type' field") if type.nil?
      raise DecodeError.new("Invalid '$type' field: #{type.inspect}") unless type.is_a?(String)

      @type = type
      @metadata = metadata
      @offset = finish
    end

    def read_section
      control_byte = @buffer.getbyte(@offset)
      offset = @offset + 1

      case control_byte
      when 0
        # end of file
        raise DecodeError, "Unexpected content after end of file marker" unless offset == @size

        @offset = offset
        return false
      when 1
        # continue with the next section
      when nil
        raise DecodeError, "Unexpected end of file"
      else
        raise DecodeError, "Unexpected control byte: #{control_byte}"
      end

      k_len = @varint_reader.read(offset)
      key_start = @varint_reader.offset
      key_end = key_start + k_len
      raise DecodeError, "Truncated key data" if key_end > @size

      v_len = @varint_reader.read(key_end)
      value_start = @varint_reader.offset
      value_end = value_start + v_len
      raise DecodeError, "Truncated value data" if value_end > @size

      key = @buffer.byteslice(key_start, k_len).freeze
      value = @buffer.byteslice(value_start, v_len).freeze

      @data_pairs << [key, value]
      @data_map[key] = value
      @offset = value_end

      true
    end
  end
end
