# frozen_string_literal: true

require_relative 'cbor'

module Oxygene

  #
  # Represents a single CID-addressed block from a {CARArchive}.
  #

  class CARSection

    # @return [CID] CID of this section
    attr_reader :cid

    # @return [String] raw CBOR body binary data
    attr_reader :data

    # Creates a section from its CID and encoded body.
    #
    # @param cid [CID] content identifier of the section
    # @param data [String] raw CBOR body data
    #
    def initialize(cid, data)
      @cid = cid
      @data = data
    end

    # Decodes the body from CBOR, without performing all ATProto JSON specific conversions.
    #
    # CID links are represented as {CID} objects, and byte strings as binary strings.
    #
    # @note When the `oxygene/cbor_native` adapter for the native C module `cbor` gem is loaded,
    #   CID links are returned as {CBOR::Tagged} objects instead.
    #
    # @return [Object] section data decoded from CBOR

    def decoded_body
      @decoded_body ||= Oxygene::CBOR.decode(@data)
    end

    # Decodes the body from CBOR and converts it to an ATProto JSON compatible format.
    #
    # The conversion involves:
    # - replacing binary strings with `$bytes` objects with Base64-encoded data
    # - wrapping {CID} values decoded from CBOR CID tags into `$link` objects
    # - if `oxygene/cbor_native` adapter is loaded, also converting the CIDs from {CBOR::Tagged} objects first
    #
    # @return [Hash, Array] decoded ATProto JSON compatible body
    # @raise [DecodeError] if the decoded top-level value is not a hash or array

    def json_body
      @json_body ||= begin
        validate_section_cbor_type(@data)
        Oxygene::CBOR.decode(@data, json: true)
      end
    end

    alias body json_body


    private

    def validate_section_cbor_type(data)
      head = data.getbyte(0)
      major = head && (head >> 5)

      unless major && (major == 4 || major == 5)
        raise DecodeError, "Expected a CBOR map or array in record (got major: #{major})"
      end
    end
  end
end
