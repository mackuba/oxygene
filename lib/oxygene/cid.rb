# frozen_string_literal: true

require_relative 'base32'
require_relative 'errors'
require_relative 'extensions'

# CIDs in DAG-CBOR: https://ipld.io/specs/codecs/dag-cbor/spec/
# CIDs in JSON: https://ipld.io/specs/codecs/dag-json/spec/
# multibase: https://github.com/multiformats/multibase

module Oxygene
  class CID
    using Oxygene::Extensions

    JSON_PREFIX = 'b'

    DRISL_JSON_PREFIX = "bafyrei"
    RAW_JSON_PREFIX   = "bafkrei"

    private_constant :DRISL_JSON_PREFIX, :RAW_JSON_PREFIX

    CBOR_TAG_PREFIX = "\x00".b.freeze

    DRISL_CODEC_ID = 0x71
    RAW_CODEC_ID   = 0x55

    DRISL_BINARY_PREFIX = "\x01\x71\x12\x20".b.freeze
    RAW_BINARY_PREFIX   = "\x01\x55\x12\x20".b.freeze

    TAG_DRISL_BINARY_PREFIX = (CBOR_TAG_PREFIX + DRISL_BINARY_PREFIX).freeze
    TAG_RAW_BINARY_PREFIX   = (CBOR_TAG_PREFIX + RAW_BINARY_PREFIX).freeze

    private_constant :DRISL_BINARY_PREFIX, :RAW_BINARY_PREFIX, :TAG_DRISL_BINARY_PREFIX, :TAG_RAW_BINARY_PREFIX

    def self.from_cbor_tag(tag)
      CID.new(tag.value, binary: true, cbor_prefix: true)
    end

    def self.from_json(string)
      CID.new(string, binary: false)
    end

    def initialize(data, binary: true, cbor_prefix: false, codec: nil)
      raise ArgumentError.new("Data cannot be nil") if data.nil?

      codec_id = case codec
        when nil then nil
        when :drisl then DRISL_CODEC_ID
        when :raw then RAW_CODEC_ID
        else raise ArgumentError.new("Unexpected CID codec: #{codec.inspect}")
      end

      if binary
        if cbor_prefix
          validate_binary_form(data, true, codec_id)
          @cbor_form = data.freeze
        else
          validate_binary_form(data, false, codec_id)
          @cbor_form = (CBOR_TAG_PREFIX + data).freeze
        end
      else
        raise ArgumentError.new("cbor_prefix cannot be used with JSON input") if cbor_prefix

        validate_json_form(data, codec_id)
        @json_form = data.freeze
      end
    end

    def cbor_form
      @cbor_form ||= Base32.decode(@json_form, 1, CBOR_TAG_PREFIX).freeze
    end

    def raw_data
      @raw_data ||= if @cbor_form
        @cbor_form.byteslice(1, @cbor_form.bytesize - 1).freeze
      else
        Base32.decode(@json_form, 1).freeze
      end
    end

    alias data raw_data

    def json_form
      @json_form ||= Base32.encode(@cbor_form, 1, JSON_PREFIX).freeze
    end

    def to_s
      json_form
    end

    def inspect
      "CID(\"#{json_form}\")"
    end

    def ==(other)
      return false unless other.is_a?(CID)

      if @cbor_form && (other_cbor = other.instance_variable_get('@cbor_form'))
        @cbor_form == other_cbor
      elsif @json_form && (other_json = other.instance_variable_get('@json_form'))
        @json_form == other_json
      else
        self.cbor_form == other.cbor_form
      end
    end

    alias eql? ==

    def hash
      cbor_form.hash
    end


    private

    def validate_json_form(data, expected_codec)
      raise DecodeError.new("Unexpected CID length") unless data.bytesize == 59
      raise DecodeError.new("Unexpected CID prefix") unless data.getbyte(0) == 98 # 'b'

      offset = 1

      while offset < 59
        byte = data.getbyte(offset)
        raise DecodeError.new("Unexpected characters in CID") unless (byte >= 97 && byte <= 122) || (byte >= 50 && byte <= 55)
        offset += 1
      end

      codec = if data.start_with?(DRISL_JSON_PREFIX)
        DRISL_CODEC_ID
      elsif data.start_with?(RAW_JSON_PREFIX)
        RAW_CODEC_ID
      else
        raise UnsupportedError.new("Unexpected CID prefix")
      end

      if expected_codec && codec != expected_codec
        raise UnsupportedError.new("Unexpected CID codec: #{codec}")
      end

      # We're checking for existence of DRISL_BINARY_PREFIX / RAW_BINARY_PREFIX at the beginning,
      # but we want to avoid encoding each JSON CID to binary immediately just to check that.
      # 
      # So instead we're looking for the equivalent in JSON encoding - 'bafyrei...' or 'bafkrei...'.
      # But the last bits of the 4th byte (24...32) are encoded into two bits of the 7th character
      # in the base32 version (after the 'b' prefix), so the one after 'i'. So here we check if the
      # 8th character of the string is in the expected range that has such two first bits.

      char8 = data.getbyte(7)
      raise UnsupportedError.new("Unexpected CID prefix") unless char8 >= 97 && char8 <= 104 # 'a'..'h'

      # And the final character needs to have last two bits set to 0:

      trailing_byte = data.getbyte(58)
      position = (trailing_byte >= 97 && trailing_byte <= 122) ? (trailing_byte - 97) : (trailing_byte - 50 + 26)
      canonical_trailing_bits = (position & 3) == 0

      raise DecodeError.new("Unexpected CID trailing bits") unless canonical_trailing_bits
    end

    def validate_binary_form(data, cbor_prefix, expected_codec)
      expected_length = cbor_prefix ? 37 : 36
      data_length = data.bytesize

      raise DecodeError.new("CID too short: #{data}") if data_length < expected_length
      raise DecodeError.new("CID too long: #{data}") if data_length > expected_length

      if cbor_prefix
        raise DecodeError.new("Unexpected first byte of CID: #{data[0]}") unless data.getbyte(0) == 0

        return if data.start_with?(TAG_DRISL_BINARY_PREFIX) && (expected_codec.nil? || expected_codec == DRISL_CODEC_ID)
        return if data.start_with?(TAG_RAW_BINARY_PREFIX) && (expected_codec.nil? || expected_codec == RAW_CODEC_ID)
      else
        return if data.start_with?(DRISL_BINARY_PREFIX) && (expected_codec.nil? || expected_codec == DRISL_CODEC_ID)
        return if data.start_with?(RAW_BINARY_PREFIX) && (expected_codec.nil? || expected_codec == RAW_CODEC_ID)
      end

      # At this point we're rejecting the CID, we just check with what error message:

      buffer = StringIO.new(data)
      buffer.pos = 1 if cbor_prefix

      version = buffer.read_varint
      raise UnsupportedError.new("Unexpected CID version: #{version}") unless version == 1

      codec = buffer.read_varint
      supported_codec = expected_codec ? (codec == expected_codec) : (codec == DRISL_CODEC_ID || codec == RAW_CODEC_ID)
      raise UnsupportedError.new("Unexpected CID codec: #{codec}") unless supported_codec

      hash = buffer.read_varint
      raise UnsupportedError.new("Unexpected CID hash: #{hash}") unless hash == 0x12

      length = buffer.read_varint
      raise UnsupportedError.new("Unexpected CID length: #{length}") unless length == 32

      raise UnsupportedError.new("Non-canonical CID prefix")
    end
  end
end
