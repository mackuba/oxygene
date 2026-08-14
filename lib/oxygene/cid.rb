# frozen_string_literal: true

require_relative 'base32'
require_relative 'errors'
require_relative 'extensions'

module Oxygene

  #
  # Represents a Content Identifier (CID) of some piece of content like an ATProto
  # record or a CAR section.
  #
  # Only the [DASL](https://dasl.ing)-compatible CID versions that are used in ATProto are supported:
  # 
  # - only CIDv1, not v0
  # - in binary CBOR form: with SHA-256 hash, 32 bytes hash size, and codec being
  #   either 0x71 (DRISL) or 0x55 (raw) (DRISL is used in CIDs of CAR sections,
  #   and raw codec is used in CIDs of blobs)
  # - in JSON string form: with 'b' prefix and Base32-encoded data, using lowercase
  #   alphabet and no '=' padding, and the CBOR form parameters listed above,
  #   resulting in an either "bafyrei" or "bafkrei" prefix
  #
  # The CID instances can be created either from JSON strings or binary CBOR form,
  # and the binary form can optionally include the \\x00 prefix byte that is used
  # when the binary CID is encoded in a CBOR tag 42 object. The instances will lazily
  # convert between the two forms only when needed.
  #
  # The code in this class is heavily optimized for performance when creating and
  # processing a large number of CIDs e.g. when parsing a CAR repo or processing
  # firehose events, for example:
  #
  # - the input JSON or binary string is stored without copying or allocating new
  #   strings for modified versions, if possible
  # - the other form (JSON/CBOR) is memoized and only created on demand, not up front
  # - equality check tries to use whichever form exists in both instances if possible,
  #   to avoid unnecessary conversion
  # - validation code uses pre-generated header constants to avoid checking the headers
  #   byte by byte, and operates mostly on byte code numbers to avoid unnecessary string allocations
  #
  # Related specifications:
  #
  # - [IPFS CID spec](https://specs.ipfs.tech/cid/)
  # - [DASL CID spec](https://dasl.ing/cid.html)
  # - [ATProto link and CID formats](https://atproto.com/specs/data-model#link-and-cid-formats)
  # - [CIDs in DAG-CBOR](https://ipld.io/specs/codecs/dag-cbor/spec/)
  # - [CIDs in DAG-JSON](https://ipld.io/specs/codecs/dag-json/spec/)
  # - [multicodec](https://github.com/multiformats/multicodec),
  #   [multihash](https://github.com/multiformats/multihash)
  #   and [multibase](https://github.com/multiformats/multibase)
  #

  class CID
    using Oxygene::Extensions

    # Multibase prefix code for Base32, required for CIDs in JSON string form.
    JSON_PREFIX = 'b'

    # Pre-generated JSON string headers for quick checking
    DRISL_JSON_PREFIX = "bafyrei"
    RAW_JSON_PREFIX   = "bafkrei"

    private_constant :DRISL_JSON_PREFIX, :RAW_JSON_PREFIX

    # Multibase "identity" prefix code, required for binary CIDs stored in a CBOR tag 42 object.
    CBOR_TAG_PREFIX = "\x00".b.freeze

    # The two possible CID codec IDs from multicodec:

    # DAG-CBOR or DRISL (used e.g. in CIDs of CAR sections)
    DRISL_CODEC_ID = 0x71

    # Raw binary (used in CIDs of blobs)
    RAW_CODEC_ID   = 0x55

    # Pre-generated binary string headers for quick checking
    DRISL_BINARY_PREFIX = "\x01\x71\x12\x20".b.freeze
    RAW_BINARY_PREFIX   = "\x01\x55\x12\x20".b.freeze

    # Pre-generated binary string header variants with identity prefix byte added
    TAG_DRISL_BINARY_PREFIX = (CBOR_TAG_PREFIX + DRISL_BINARY_PREFIX).freeze
    TAG_RAW_BINARY_PREFIX   = (CBOR_TAG_PREFIX + RAW_BINARY_PREFIX).freeze

    private_constant :DRISL_BINARY_PREFIX, :RAW_BINARY_PREFIX, :TAG_DRISL_BINARY_PREFIX, :TAG_RAW_BINARY_PREFIX


    # Builds a CID from a CBOR tag 42 value.
    #
    # Expects a `CBOR::Tagged` object returned from `CBOR.decode` or `CBOR.decode_sequence`.
    #
    # @param tag [CBOR::Tagged] tagged CBOR object containing binary CID data with identity (0) prefix
    # @return [CID] CID object wrapping that content identifier
    # @raise [DecodeError] if the CID has an invalid size or is missing an expected prefix/suffix
    # @raise [UnsupportedError] if the CID is in a form that is technically valid, but not supported here
    #
    def self.from_cbor_tag(tag)
      CID.new(tag.value, binary: true, cbor_prefix: true)
    end

    # Builds a CID from a Base32-encoded JSON form string.
    #
    # @param string [String] 59-character string with a `b` prefix encoded with Base32
    # @return [CID] CID object wrapping that content identifier
    # @raise [ArgumentError] if the input string is nil
    # @raise [DecodeError] if the CID has an invalid size or is missing an expected prefix/suffix
    # @raise [UnsupportedError] if the CID is in a form that is technically valid, but not supported here
    #
    def self.from_json(string)
      CID.new(string, binary: false)
    end

    # Creates a CID instance from binary/CBOR data or a JSON string form.
    #
    # Three possible kinds of values are accepted as input:
    # - a binary string with \\x00 identity prefix, as used when included in a
    #   CBOR tag object's value - use `binary: true` and `cbor_prefix: true`
    # - a binary string without the identity prefix, as used e.g. when decoded
    #   from a CAR archive - use `binary: true` without `cbor_prefix`
    # - a JSON string - use `binary: false`
    #
    # For backwards compatibility, the default when only the input argument is
    # passed is to assume the "binary without CBOR prefix" form. For performance,
    # for the "binary with CBOR prefix" and the JSON form types, the input string
    # itself is stored without copying and frozen to prevent modification. If you
    # need to modify the string later at the call site, call {dup} when passing the
    # input argument here. (For the non-prefixed binary version, the input string is
    # copied to add the prefix.)
    #
    # Optionally, the initializer can also enforce that the CID has to use a selected one
    # of the two available codecs (DRISL/DAG-CBOR vs. raw binary).
    #
    # @param data [String] raw CID bytes, identity-prefixed CBOR bytes, or a Base32 JSON string
    # @param binary [Boolean] true if `data` is in binary form, false if it's a JSON string
    # @param cbor_prefix [Boolean] true if the `data` includes the leading null byte used inside CBOR tag 42
    # @param codec [:drisl, :raw, nil] required content codec, or `nil` to accept either of the two supported codecs
    #
    # @raise [ArgumentError] if data is nil, codec param is invalid, or invalid combination of options is used
    # @raise [DecodeError] if the CID has an invalid size or is missing an expected prefix/suffix
    # @raise [UnsupportedError] if the CID is in a form that is technically valid, but not supported here
    #
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

    # Returns the CID data in binary form with a null byte identity prefix, as stored in CBOR tag 42.
    #
    # If the CID was created from a JSON form, the data is decoded from Base32 (and memoized).
    # If it was created from a CBOR tag, the input is returned directly.
    #
    # @return [String] frozen binary string beginning with {CBOR_TAG_PREFIX}
    # @raise [ArgumentError] if a JSON-form CID contains invalid Base32

    def cbor_form
      @cbor_form ||= Base32.decode(@json_form, 1, CBOR_TAG_PREFIX).freeze
    end

    # Returns the CID data in binary form, without the null byte identity prefix from CBOR tag.
    #
    # If the CID was created from a JSON form, the data is decoded from Base32 (and memoized).
    #
    # @return [String] frozen binary CID bytes
    # @raise [ArgumentError] if a JSON-form CID contains invalid Base32

    def raw_data
      @raw_data ||= if @cbor_form
        @cbor_form.byteslice(1, @cbor_form.bytesize - 1).freeze
      else
        Base32.decode(@json_form, 1).freeze
      end
    end

    alias data raw_data

    # Returns the CID's Base32-encoded JSON string representation.
    #
    # If the CID was created from a binary form, the data is encoded into Base32 (and memoized).
    # If it was created from a JSON form, the input is returned directly.
    #
    # @return [String] frozen CID string beginning with {JSON_PREFIX}

    def json_form
      #TMP
      @binary_data = (CBOR_TAG_PREFIX + @data).freeze if @data

      @json_form ||= Base32.encode(@cbor_form, 1, JSON_PREFIX).freeze
    end

    # Returns the CID's Base32-encoded JSON string representation (same as {#json_form}).
    #
    # @return [String] the CID in the JSON form

    def to_s
      json_form
    end

    # @return [String] a representation of the CID object for debugging
    #
    def inspect
      "CID(\"#{json_form}\")"
    end

    # Compares this CID with another CID to see if they're equal.
    #
    # If both CIDs have a generated CBOR or JSON form, those forms are used
    # for comparison without conversion. If the two only have different forms,
    # the JSON CID is converted to binary for comparison.
    #
    # @param other [Object] object to compare
    # @return [Boolean] whether `other` is a CID with the same value

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

    # Returns a hash code for the purposes of a {Set} or {Hash}.
    #
    # The binary CBOR form of the CID is used to derive the hash.
    #
    # @return [Integer] hash code generated from the CID's binary form

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
