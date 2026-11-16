# frozen_string_literal: true

require 'base64'

require_relative 'cid'
require_relative 'errors'

# tmp
module CBOR
  def self.decode_sequence(data)
    Oxygene::CBOR.decode_sequence(data)
  end
end

module Oxygene

  #
  # Decodes the DRISL subset of CBOR used in ATProto.
  #
  # Follows the constraints specified in:
  # - https://dasl.ing/drisl.html
  # - https://atproto.com/specs/data-model
  #

  module CBOR

    # Indicates if the adapter to the native C CBOR parser from the external `cbor` gem is loaded
    # (default: false, until `oxygene/cbor_native` is required explicitly).
    #
    def self.native_module?
      false
    end

    # Decodes the given CBOR string as a single item.
    # The data must not contain any extra bytes after the decoded item.
    #
    # @param data [String] CBOR-encoded bytes
    # @param json [Boolean] if true, wraps CID objects in `$link` and encodes byte strings as `$bytes` with Base64
    #
    # @return [Object] the decoded value
    # @raise [DecodeError] for malformed or non-canonical CBOR
    # @raise [UnsupportedError] for unsupported CID formats

    def self.decode(data, json: false)
      Decoder.new(data, json).decode_single_item
    end

    # Decodes the given CBOR string as a sequence of concatenated items, as used in ATProto firehose message frames.
    #
    # @param data [String] concatenated CBOR items
    # @param json [Boolean] if true, wraps CID objects in `$link` and encodes byte strings as `$bytes` with Base64
    #
    # @return [Array] decoded items in the order as encoded in the input
    # @raise [DecodeError] for malformed or non-canonical CBOR
    # @raise [UnsupportedError] for unsupported CID formats

    def self.decode_sequence(data, json: false)
      Decoder.new(data, json).decode_sequence
    end

    # @api private
    #
    # Converts a byte string into the ATProto JSON representation as a `$bytes` object.
    #
    # @param data [String] binary data
    # @return [Hash{String => String}] a `$bytes` object containing Base64-encoded data

    def self.make_bytes(data)
      string = Base64.strict_encode64(data)
      string.chomp!('=') while string.getbyte(-1) == 61

      { '$bytes' => string }
    end

    # String#unpack1(data, offset:) is available on Ruby 3.1+
    UNPACK_OFFSET = (Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1.0'))
    private_constant :UNPACK_OFFSET

    # @api private
    #
    # Holds the input buffer and handles decoding all data encoded into it.
    #
    # The decoder holds a byte cursor indicating current reading position in the @offset variable.
    # Reader methods `read_*` receive the starting byte offset in the `offset` parameter, and store
    # the final offset after they read their data back into `@offset`. The separation is meant as
    # an optimization to avoid some instance variable reads & writes on some paths.

    class Decoder
      # @return [Integer] Maximum level of nested array and map items.
      MAX_DEPTH = 128

      # Largest CBOR argument value for integers (of both signs).
      # ATProto data model defines integers as signed 64-bit numbers.
      # @return [Integer]
      MAX_INTEGER_ARGUMENT = (1 << 63) - 1

      # Quick lookup table for 1-byte UTF-8 map keys from the ASCII range.
      # @return [Array<String>]
      ASCII_KEYS = Array.new(128) { |byte| byte.chr(Encoding::UTF_8).freeze }.freeze


      def initialize(data, json_mode)
        # We keep two versions of the input string, one in UTF-8 and the other in binary,
        # which lets us then slice fragments from either of those depending on which one
        # we need without changing encoding for the copied fragments

        encoding = data.encoding
        @data = (encoding == Encoding::UTF_8) ? data : data.dup.force_encoding(Encoding::UTF_8)
        @binary = (encoding == Encoding::BINARY) ? data : data.b

        @size = data.bytesize
        @json_mode = json_mode
      end

      # Decodes the whole input buffer as exactly one item. If there are any remaining bytes
      # after the item is decoded, an error is raised.
      #
      # @return [Object] the decoded value
      # @raise [DecodeError] if the item is malformed or bytes remain after it
      # @raise [UnsupportedError] if the item contains an unsupported CID

      def decode_single_item
        result = read_item(0, 0)

        # after the item, offset should be at the end of the buffer
        if @offset != @size
          raise DecodeError, "Unexpected bytes after CBOR item"
        end

        result
      end

      # Decodes a sequence of independent consecutive items until the end of the input is reached.
      #
      # @return [Array<Object>] decoded items in the order as encoded in the input
      # @raise [DecodeError] if any item is malformed or incomplete
      # @raise [UnsupportedError] if an item contains an unsupported CID

      def decode_sequence
        if @size == 0
          return []
        end

        # special case for len = 1
        first_item = read_item(0, 0)
        return [first_item] if @offset == @size

        # special case for len = 2 (standard firehose commit frame)
        items = [first_item, read_item(@offset, 0)]

        # parse any remaining items
        items << read_item(@offset, 0) while @offset < @size
        items
      end


      private

      # Decodes a single item.
      #
      # The function reads the item's "major type" from its initial byte, and then each section
      # handles the decoding of a specific major type value.
      #
      # @param offset [Integer] byte offset of the initial byte
      # @param depth [Integer] number of enclosing (parent) arrays and maps this item is nested in
      #
      # @return [Object] the decoded value
      # @raise [DecodeError] if the item is malformed or outside the supported CBOR subset
      # @raise [UnsupportedError] if the item contains an unsupported CID

      def read_item(offset, depth)
        data = @data
        head = data.getbyte(offset)
        raise DecodeError, "Truncated CBOR item" unless head

        offset += 1

        # the highest three bits are the major type, the lower five bits are the argument
        argument = head & 31

        case head >> 5
        when 0, 1
          # 0 = unsigned (positive) integer
          # 1 = negative integer

          if argument < 24
            @offset = offset
          else
            eight_byte_value = (argument == 27)
            argument = read_argument(argument, offset)

            if eight_byte_value && argument > MAX_INTEGER_ARGUMENT
              raise DecodeError, "CBOR integer is outside the signed 64-bit range"
            end
          end

          # head < 32 means major == 0
          (head < 32) ? argument : (-1 - argument)

        when 2
          # 2 = byte (binary) string

          if argument >= 24
            argument = read_argument(argument, offset)
            offset = @offset
          end

          byte_string = read_byte_string(argument, offset)
          @json_mode ? Oxygene::CBOR.make_bytes(byte_string) : byte_string

        when 3
          # 3 = text (UTF-8) string

          if argument == 24
            # fast path for strings with 1-byte length (24..255)
            argument = data.getbyte(offset)
            raise DecodeError, "Truncated CBOR text string" if argument.nil?
            raise DecodeError, "Invalid single-byte CBOR text length (#{argument})" if argument < 24

            offset += 1
          elsif argument > 24
            argument = read_argument(argument, offset)
            offset = @offset
          end

          finish = offset + argument
          raise DecodeError, "Truncated CBOR text string" if finish > @size
          @offset = finish

          text = data.byteslice(offset, argument)
          raise DecodeError, "Invalid UTF-8 in CBOR text string" unless text.valid_encoding?

          text

        when 4
          # 4 = array

          if argument >= 24
            argument = read_argument(argument, offset)
            offset = @offset
          end

          read_array(argument, offset, depth)

        when 5
          # 5 = map

          if argument >= 24
            argument = read_argument(argument, offset)
            offset = @offset
          end

          read_map(argument, offset, depth)

        when 6
          # 6 = tag - we only support CID (42)

          # 0xd8 = (6 << 5) + 24, 24 = value in 1 following byte
          unless head == 0xd8 && data.getbyte(offset) == 42
            tag = (argument >= 24) ? read_argument(argument, offset) : argument
            raise UnsupportedError, "Only CBOR tag 42 (CID) is supported (got: #{tag})"
          end

          read_cid(offset)

        when 7
          # 7 = simple values and floats (we don't support floats at the moment)

          @offset = offset

          case argument
          when 20 then false
          when 21 then true
          when 22 then nil
          else raise DecodeError, "Unsupported CBOR simple value or float (#{argument})"
          end
        end
      end

      # Reads a multi-byte argument value from the input buffer.
      #
      # Additional information codes 24..27 define a 1-, 2-, 4-, or 8-byte big-endian
      # argument value. The value must be encoded in a shortest possible form, so it
      # must be higher than the maximum value that can be encoded in the previous width's range.
      #
      # @param argument [Integer] additional information from the initial byte, must be 24 or higher
      # @param offset [Integer] byte offset immediately after the initial byte
      # @return [Integer] the parsed argument value
      # @raise [DecodeError] if the argument is reserved, indefinite, truncated, or non-minimal

      def read_argument(argument, offset)
        case argument
        when 24
          # value is the next byte
          byte_width = 1
          minimum = 24
          value = @data.getbyte(offset)

        when 25
          # value is next 2 bytes
          byte_width = 2
          minimum = 1 << 8
          low = @data.getbyte(offset + 1)
          value = (@data.getbyte(offset) << 8) | low if low

        when 26
          # value is next 4 bytes
          byte_width = 4
          minimum = 1 << 16

          value = UNPACK_OFFSET ? @data.unpack1('N', offset: offset) : @data.byteslice(offset, byte_width).unpack1('N')

        when 27
          # value is next 8 bytes
          byte_width = 8
          minimum = 1 << 32

          value = UNPACK_OFFSET ? @data.unpack1('Q>', offset: offset) : @data.byteslice(offset, byte_width).unpack1('Q>')

        else
          raise DecodeError, "Reserved or indefinite-length CBOR argument (#{argument})"
        end

        raise DecodeError, "Truncated CBOR argument" unless value
        raise NonMinimalEncodingError, "Non-minimal CBOR argument encoding" if value < minimum

        @offset = offset + byte_width
        value
      end

      # Reads a byte string of a given length from the input buffer.
      #
      # @param length [Integer] payload length in bytes
      # @param offset [Integer] byte offset of the payload
      # @return [String] the payload with binary encoding
      # @raise [DecodeError] if the payload is truncated

      def read_byte_string(length, offset)
        finish = offset + length
        raise DecodeError, "Truncated CBOR string" if finish > @size

        @offset = finish
        @binary.byteslice(offset, length)
      end

      # Decodes the elements of an array with a given length from the input buffer.
      #
      # @param length [Integer] number of elements in the array
      # @param offset [Integer] byte offset immediately after the array header
      # @param depth [Integer] number of enclosing (parent) arrays and maps this item is nested in
      #
      # @return [Array<Object>] decoded items in the order as encoded in the input
      # @raise [DecodeError] if the nesting limit is exceeded or an element is malformed
      # @raise [UnsupportedError] if an element contains an unsupported CID

      def read_array(length, offset, depth)
        raise DecodeError, "CBOR nesting is too deep (#{depth})" if depth >= MAX_DEPTH

        # fast path for common empty and one-item arrays
        case length
        when 0
          @offset = offset
          return []
        when 1
          return [read_item(offset, depth + 1)]
        end

        child_depth = depth + 1
        items = []

        while length > 0
          items << read_item(offset, child_depth)
          offset = @offset
          length -= 1
        end

        items
      end

      # Decodes a map with a given number of pairs from the input buffer.
      #
      # The map is expected to have UTF-8 text keys that are in canonical order.
      #
      # @param length [Integer] number of key-value pairs in the map
      # @param offset [Integer] byte offset immediately after the map header
      # @param depth [Integer] number of enclosing (parent) arrays and maps this item is nested in
      #
      # @return [Hash{String => Object}] decoded map of keys and values
      # @raise [DecodeError] if a key or value is malformed or the nesting limit is exceeded
      # @raise [UnsupportedError] if a value contains an unsupported CID

      def read_map(length, offset, depth)
        raise DecodeError, "CBOR nesting is too deep (#{depth})" if depth >= MAX_DEPTH

        items = {}

        if length == 0
          @offset = offset
          return items
        end

        child_depth = depth + 1
        items_left = length
        previous_key = nil
        previous_length = -1
        data = @data

        while true
          # Decode the item key:

          head = data.getbyte(offset)
          raise DecodeError, "Truncated CBOR map key" unless head

          offset += 1
          key_length = head - 0x60   # 0x60 = 3 << 5 (string major type)

          if key_length >= 24
            # this would means the major type was higher than 3:
            raise DecodeError, "CBOR map key must be a text string (got major: #{head >> 5})" if key_length > 31

            key_length = read_argument(key_length, offset)
            offset = @offset
            finish = offset + key_length

            raise DecodeError, "Truncated CBOR map key" if finish > @size
          else
            finish = offset + key_length

            # We detect truncated keys through the `read_item` below trying to read the value.
            # If the key is truncated, then the value will be missing too.
            # The branch above checks it explicitly, because we don't want to pass a possibly
            # extremely large length to be read to #byteslice; here it's <= 23.

            # this would means the major type was lower than 3:
            raise DecodeError, "CBOR map key must be a text string (got major: #{head >> 5})" if key_length < 0
          end

          if key_length == 1
            # fast path for very commonly used 1-letter keys using a table lookup
            # single-byte keys of value 0-127 are ASCII and valid UTF-8; 128-255 are invalid as single bytes

            key = ASCII_KEYS[data.getbyte(offset) || 128]
            raise DecodeError, "Invalid UTF-8 in CBOR map key (#{data.getbyte(offset)})" unless key
          else
            key = data.byteslice(offset, key_length)
            raise DecodeError, "Invalid UTF-8 in CBOR map key" unless key.valid_encoding?

            # hash duplicates the keys of inserted elements unless they're frozen
            key.freeze
          end

          # Keys need to be sorted by length first (shortest first), and then lexicographically by bytes.
          # Duplicates are rejected here. Using <=> operator avoids one call to `Comparable#<=`.

          if key_length < previous_length || (key_length == previous_length && (key <=> previous_key) <= 0)
            raise DecodeError, (key == previous_key) ? "Duplicate CBOR map key" : "Out of order CBOR map key"
          end

          previous_key = key
          previous_length = key_length


          # Decode the item value:

          items[key] = read_item(finish, child_depth)
          items_left -= 1
          return items if items_left == 0

          offset = @offset
        end
      end

      # Decodes a tag 42 item (CID) from the input buffer.
      #
      # @param offset [Integer] byte offset immediately after the initial tag byte
      # @return [CID, Hash{String => CID}] the CID, wrapped in a `$link` object in JSON mode
      # @raise [DecodeError] if the tag or CID byte string is malformed
      # @raise [UnsupportedError] if the CID format is unsupported

      def read_cid(offset)
        data = @binary

        # The supported CID formats all have a 37-byte length when encoded in CBOR (see CID#validate_binary_form).
        # The header should be:
        #   2 (byte string major) << 5 + 24 (length in 1 next byte) = 0x58
        #   then the byte with bytestring length = 37

        unless data.getbyte(offset + 1) == 0x58 && data.getbyte(offset + 2) == 37
          raise DecodeError, "CBOR tag 42 must contain a 37-byte CID byte string"
        end

        finish = offset + 40
        raise DecodeError, "Truncated CBOR CID" if finish > @size
        @offset = finish

        bytes = data.byteslice(offset + 3, 37)
        cid = CID.from_cbor_bytes(bytes)

        @json_mode ? { '$link' => cid } : cid
      end
    end

    private_constant :Decoder
  end
end
