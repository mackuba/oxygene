# frozen_string_literal: true

require_relative 'errors'

module Oxygene

  #
  # Reads unsigned LEB128 integers (varints) from an in-memory string.
  #
  # The reader rejects varints that are not minimally encoded or that are longer than 9 bytes.
  #
  # Relevant specifications:
  # - https://en.wikipedia.org/wiki/LEB128
  # - https://github.com/multiformats/unsigned-varint
  #

  class VarintReader

    # @return [Integer] current byte offset after the last successful read, initially zero
    attr_reader :offset

    # Maximum number of allowed bytes in the varint.
    MAX_DIGITS = 9

    MAX_SHIFT = MAX_DIGITS * 7
    private_constant :MAX_SHIFT

    # Creates a varint reader reading from a given data string.
    #
    # @param buffer [String] the input string (the reader stores a reference to it locally)
    #
    def initialize(buffer)
      @buffer = buffer.freeze
      @offset = 0
    end

    # Reads one varint from the buffer at the current {#offset}.
    #
    # After a successful read, the {#offset} is updated to the position after the varint. On error, offset is unchanged.
    #
    # @return [Integer] decoded unsigned integer value
    # @raise [DecodeError] if the varint is truncated, non-minimal, or exceeds nine bytes
    #
    def read_next
      read(@offset)
    end

    # Reads one varint from the buffer starting at the given byte offset.
    #
    # After a successful read, the {#offset} is updated to the position after the varint. On error, offset is unchanged.
    #
    # @param offset [Integer] starting byte offset (non-negative integer)
    # @return [Integer] decoded unsigned integer value
    # @raise [ArgumentError] if the starting offset is negative
    # @raise [DecodeError] if the varint is truncated, non-minimal, or exceeds nine bytes
    #
    def read(offset)
      raise ArgumentError, "Negative varint offset" if offset < 0

      byte = @buffer.getbyte(offset)
      raise DecodeError, "Unexpected end of data while reading varint" unless byte

      if byte < 128
        @offset = offset + 1
        return byte
      end

      buffer = @buffer
      offset += 1

      value = byte & 127
      shift = 7

      while true
        byte = buffer.getbyte(offset)
        raise DecodeError, "Unexpected end of data while reading varint" unless byte

        offset += 1

        if byte < 128
          raise NonMinimalEncodingError, "Non-minimal varint encoding" if byte == 0

          @offset = offset
          return value | (byte << shift)
        end

        value |= (byte & 127) << shift
        shift += 7

        raise DecodeError, "Varint length exceeds limit" if shift == MAX_SHIFT
      end
    end
  end
end
