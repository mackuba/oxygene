# frozen_string_literal: true

# Based on the code of the base32 gem by Samantha Tesla (https://github.com/stesla/base32, MIT).

module Oxygene
  module Base32
    BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567".freeze

    BASE32_PAIRS = Array.new(1024) { |i|
      (BASE32_ALPHABET.getbyte(i >> 5).chr + BASE32_ALPHABET.getbyte(i & 31).chr).freeze
    }.freeze

    private_constant :BASE32_ALPHABET, :BASE32_PAIRS

    def self.encode(data, start_offset = 0, prefix = "")
      total_size = data.bytesize
      size = total_size - start_offset
      output = prefix.dup
      offset = start_offset
      full_block_end = total_size - (size % 5)

      # A single base32 character is one of the 32 values in the BASE32_ALPHABET string
      # above, i.e. 5 bits. The BASE32_PAIRS array stores a (flattened) 32x32 table
      # of all possible combinations of two-character pairs (10 bits).
      #
      # Instead of taking the 40 bits of a 5-byte slice of the original string, slicing
      # it into 8 5-bit pieces and looking up 8 separate base32 characters, we process
      # 10 bits at a time here, looking up 4 two-character pairs. This allows us to do
      # only half the amount of array lookups, shifts and bitwise ands.

      while offset < full_block_end
        value = (data.getbyte(offset) << 32) |
                (data.getbyte(offset + 1) << 24) |
                (data.getbyte(offset + 2) << 16) |
                (data.getbyte(offset + 3) << 8) |
                (data.getbyte(offset + 4))

        output << BASE32_PAIRS[(value >> 30) & 1023]
        output << BASE32_PAIRS[(value >> 20) & 1023]
        output << BASE32_PAIRS[(value >> 10) & 1023]
        output << BASE32_PAIRS[(value) & 1023]

        offset += 5
      end

      case total_size - offset
      when 1
        output << BASE32_PAIRS[data.getbyte(offset) << 2]
      when 2
        value = (data.getbyte(offset) << 8) | data.getbyte(offset + 1)

        output << BASE32_PAIRS[value >> 6]
        output << BASE32_PAIRS[(value & 63) << 4]
      when 3
        value = (data.getbyte(offset) << 16) |
                (data.getbyte(offset + 1) << 8) |
                (data.getbyte(offset + 2))

        output << BASE32_PAIRS[value >> 14]
        output << BASE32_PAIRS[(value >> 4) & 1023]
        output << BASE32_ALPHABET.getbyte((value & 15) << 1)
      when 4
        value = (data.getbyte(offset) << 24) |
                (data.getbyte(offset + 1) << 16) |
                (data.getbyte(offset + 2) << 8) |
                (data.getbyte(offset + 3))

        output << BASE32_PAIRS[value >> 22]
        output << BASE32_PAIRS[(value >> 12) & 1023]
        output << BASE32_PAIRS[(value >> 2) & 1023]
        output << BASE32_ALPHABET.getbyte((value & 3) << 3)
      end

      output
    end
  end
end
