# frozen_string_literal: true

require_relative 'car_archive'
require 'cbor'

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

    # Decodes the body from CBOR, without performing ATProto JSON specific conversions.
    #
    # The result is decoded once and memoized. CID links are represented as {CBOR::Tagged}
    # objects, and byte strings remain binary strings.
    #
    # @return [Object] section data decoded from CBOR

    def decoded_body
      @decoded_body ||= CBOR.decode(@data)
    end

    # Decodes the body and converts it to an ATProto JSON compatible format.
    #
    # The conversion involves:
    # - replacing binary strings with `$bytes` objects with Base64-encoded data
    # - converting CBOR CID tags to `$link` objects holding an {Oxygene::CID}
    #
    # The result is decoded and stored separately from {#decoded_body}, so calling this
    # method does not mutate the value returned by {#decoded_body}.
    #
    # @return [Hash, Array] decoded ATProto JSON compatible body
    # @raise [DecodeError] if the decoded top-level value is not a hash or array

    def json_body
      @json_body ||= CARArchive.convert_data(CBOR.decode(@data))
    end

    alias body json_body
  end
end
