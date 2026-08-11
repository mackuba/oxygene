# frozen_string_literal: true

# Based on the code of the base32 gem by Samantha Tesla (https://github.com/stesla/base32, MIT).

module Oxygene
  module Base32
    BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567".freeze

    BASE32_ENCODE_TABLE = Array.new(1024) { |i|
      (BASE32_ALPHABET.getbyte(i >> 5).chr + BASE32_ALPHABET.getbyte(i & 31).chr).freeze
    }.freeze

    BASE32_DECODE_TABLE = begin
      table = Array.new(256, 255)

      BASE32_ALPHABET.each_byte.with_index do |byte, value|
        table[byte] = value
        table[byte - 32] = value if byte >= 97 && byte <= 122
      end

      table.freeze
    end

    private_constant :BASE32_ALPHABET, :BASE32_ENCODE_TABLE, :BASE32_DECODE_TABLE

    def self.encode(data, start_offset = 0, prefix = "")
      total_size = data.bytesize
      raise ArgumentError, "Start offset can't be negative" if start_offset < 0
      raise ArgumentError, "Start offset is larger than the length of data" if start_offset > total_size

      size = total_size - start_offset
      output = prefix.dup
      offset = start_offset
      full_block_end = total_size - (size % 5)

      # A single base32 character is one of the 32 values in the BASE32_ALPHABET string
      # above, i.e. 5 bits. The BASE32_ENCODE_TABLE array stores a (flattened) 32x32 table
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

        output << BASE32_ENCODE_TABLE[(value >> 30) & 1023]
        output << BASE32_ENCODE_TABLE[(value >> 20) & 1023]
        output << BASE32_ENCODE_TABLE[(value >> 10) & 1023]
        output << BASE32_ENCODE_TABLE[(value) & 1023]

        offset += 5
      end

      case total_size - offset
      when 1
        output << BASE32_ENCODE_TABLE[data.getbyte(offset) << 2]
      when 2
        value = (data.getbyte(offset) << 8) | data.getbyte(offset + 1)

        output << BASE32_ENCODE_TABLE[value >> 6]
        output << BASE32_ENCODE_TABLE[(value & 63) << 4]
      when 3
        value = (data.getbyte(offset) << 16) |
                (data.getbyte(offset + 1) << 8) |
                (data.getbyte(offset + 2))

        output << BASE32_ENCODE_TABLE[value >> 14]
        output << BASE32_ENCODE_TABLE[(value >> 4) & 1023]
        output << BASE32_ALPHABET.getbyte((value & 15) << 1)
      when 4
        value = (data.getbyte(offset) << 24) |
                (data.getbyte(offset + 1) << 16) |
                (data.getbyte(offset + 2) << 8) |
                (data.getbyte(offset + 3))

        output << BASE32_ENCODE_TABLE[value >> 22]
        output << BASE32_ENCODE_TABLE[(value >> 12) & 1023]
        output << BASE32_ENCODE_TABLE[(value >> 2) & 1023]
        output << BASE32_ALPHABET.getbyte((value & 3) << 3)
      end

      output
    end

    def self.decode(data, start_offset = 0, prefix = "")
      total_size = data.bytesize
      raise ArgumentError, "Start offset can't be negative" if start_offset < 0
      raise ArgumentError, "Start offset is larger than the length of data" if start_offset > total_size

      encoded_end = total_size

      if encoded_end > start_offset && data.getbyte(encoded_end - 1) == 61 # '='
        encoded_end -= 1 while encoded_end > start_offset && data.getbyte(encoded_end - 1) == 61

        padding_size = total_size - encoded_end
        unpadded_remainder = (encoded_end - start_offset) & 7
        expected_padding = (8 - unpadded_remainder) & 7

        if ((total_size - start_offset) & 7) != 0 || padding_size != expected_padding || padding_size > 6
          raise ArgumentError, "Invalid Base32 padding"
        end
      end

      size = encoded_end - start_offset
      remainder = size & 7

      unless remainder == 0 || remainder == 2 || remainder == 4 || remainder == 5 || remainder == 7
        raise ArgumentError, "Invalid Base32 length"
      end

      output = prefix.dup.force_encoding(Encoding::BINARY)
      offset = start_offset
      full_block_end = encoded_end - remainder
      table = BASE32_DECODE_TABLE

      # Eight Base32 characters contain 40 bits, which decode to five bytes. Looking
      # up and combining a complete block at once avoids the arrays, chunks, temporary
      # one-character strings and arbitrary-size accumulator used by the base32 gem.
      while offset < full_block_end
        v0 = table[data.getbyte(offset)]
        v1 = table[data.getbyte(offset + 1)]
        v2 = table[data.getbyte(offset + 2)]
        v3 = table[data.getbyte(offset + 3)]
        v4 = table[data.getbyte(offset + 4)]
        v5 = table[data.getbyte(offset + 5)]
        v6 = table[data.getbyte(offset + 6)]
        v7 = table[data.getbyte(offset + 7)]

        invalid_value = v0 | v1 | v2 | v3 | v4 | v5 | v6 | v7
        invalid_character!(data, offset, offset + 8, table) if invalid_value > 31

        value = (v0 << 35) | (v1 << 30) | (v2 << 25) | (v3 << 20) | (v4 << 15) | (v5 << 10) | (v6 << 5) | v7

        output << ((value >> 32) & 255)
        output << ((value >> 24) & 255)
        output << ((value >> 16) & 255)
        output << ((value >> 8) & 255)
        output << (value & 255)

        offset += 8
      end

      case remainder
      when 2
        v0 = table[data.getbyte(offset)]
        v1 = table[data.getbyte(offset + 1)]
        invalid_character!(data, offset, encoded_end, table) if (v0 | v1) > 31

        value = (v0 << 5) | v1
        raise ArgumentError, "Invalid Base32 trailing bits" unless (value & 3) == 0

        output << (value >> 2)

      when 4
        v0 = table[data.getbyte(offset)]
        v1 = table[data.getbyte(offset + 1)]
        v2 = table[data.getbyte(offset + 2)]
        v3 = table[data.getbyte(offset + 3)]
        invalid_character!(data, offset, encoded_end, table) if (v0 | v1 | v2 | v3) > 31

        value = (v0 << 15) | (v1 << 10) | (v2 << 5) | v3
        raise ArgumentError, "Invalid Base32 trailing bits" unless (value & 15) == 0

        output << ((value >> 12) & 255)
        output << ((value >> 4) & 255)

      when 5
        v0 = table[data.getbyte(offset)]
        v1 = table[data.getbyte(offset + 1)]
        v2 = table[data.getbyte(offset + 2)]
        v3 = table[data.getbyte(offset + 3)]
        v4 = table[data.getbyte(offset + 4)]
        invalid_character!(data, offset, encoded_end, table) if (v0 | v1 | v2 | v3 | v4) > 31

        value = (v0 << 20) | (v1 << 15) | (v2 << 10) | (v3 << 5) | v4
        raise ArgumentError, "Invalid Base32 trailing bits" unless (value & 1) == 0

        output << ((value >> 17) & 255)
        output << ((value >> 9) & 255)
        output << ((value >> 1) & 255)

      when 7
        v0 = table[data.getbyte(offset)]
        v1 = table[data.getbyte(offset + 1)]
        v2 = table[data.getbyte(offset + 2)]
        v3 = table[data.getbyte(offset + 3)]
        v4 = table[data.getbyte(offset + 4)]
        v5 = table[data.getbyte(offset + 5)]
        v6 = table[data.getbyte(offset + 6)]
        invalid_character!(data, offset, encoded_end, table) if (v0 | v1 | v2 | v3 | v4 | v5 | v6) > 31

        value = (v0 << 30) | (v1 << 25) | (v2 << 20) | (v3 << 15) |
                (v4 << 10) | (v5 << 5) | v6
        raise ArgumentError, "Invalid Base32 trailing bits" unless (value & 7) == 0

        output << ((value >> 27) & 255)
        output << ((value >> 19) & 255)
        output << ((value >> 11) & 255)
        output << ((value >> 3) & 255)
      end

      output
    end

    def self.invalid_character!(data, offset, end_offset, table)
      offset += 1 while offset < end_offset && table[data.getbyte(offset)] <= 31
      character = data.byteslice(offset, 1)
      raise ArgumentError, "Invalid Base32 character: #{character.inspect}"
    end

    private_class_method :invalid_character!
  end
end
