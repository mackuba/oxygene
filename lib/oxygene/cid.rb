# frozen_string_literal: true

require_relative 'base32'
require_relative 'errors'

# CIDs in DAG-CBOR: https://ipld.io/specs/codecs/dag-cbor/spec/
# CIDs in JSON: https://ipld.io/specs/codecs/dag-json/spec/
# multibase: https://github.com/multiformats/multibase

module Oxygene
  class CID
    JSON_PREFIX = 'b'
    JSON_PREFIX_CODE = JSON_PREFIX.ord
    CBOR_TAG_PREFIX = "\x00".b.freeze

    private_constant :JSON_PREFIX_CODE

    def self.from_cbor_tag(tag)
      data = tag.value
      raise DecodeError.new("Unexpected first byte of CID: #{data[0]}") unless data.getbyte(0) == 0

      CID.new(data, binary: true, cbor_prefix: true)
    end

    def self.from_json(string)
      raise DecodeError.new("Unexpected CID length") unless string.length == 59
      raise DecodeError.new("Unexpected CID prefix") unless string.getbyte(0) == JSON_PREFIX_CODE

      CID.new(string, binary: false)
    end

    def initialize(data, binary: true, cbor_prefix: false)
      raise ArgumentError.new("Data cannot be nil") if data.nil?

      if binary
        if cbor_prefix
          @cbor_form = data.freeze
        else
          @cbor_form = (CBOR_TAG_PREFIX + data).freeze
        end
      else
        raise ArgumentError.new("cbor_prefix cannot be used with JSON input") if cbor_prefix

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
  end
end
