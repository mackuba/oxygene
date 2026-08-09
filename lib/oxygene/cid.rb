# frozen_string_literal: true

require_relative 'base32'
require_relative 'errors'

require 'base32'

# CIDs in DAG-CBOR: https://ipld.io/specs/codecs/dag-cbor/spec/
# CIDs in JSON: https://ipld.io/specs/codecs/dag-json/spec/
# multibase: https://github.com/multiformats/multibase

module Oxygene
  class CID
    JSON_PREFIX = 'b'
    JSON_PREFIX_CODE = JSON_PREFIX.ord
    BINARY_PREFIX = "\x00".b.freeze

    private_constant :JSON_PREFIX_CODE

    def self.from_cbor_tag(tag)
      data = tag.value
      raise DecodeError.new("Unexpected first byte of CID: #{data[0]}") unless data.getbyte(0) == 0

      CID.new(data, true, true)
    end

    def self.from_json(string)
      raise DecodeError.new("Unexpected CID length") unless string.length == 59
      raise DecodeError.new("Unexpected CID prefix") unless string.getbyte(0) == JSON_PREFIX_CODE

      CID.new(string, false)
    end

    def initialize(data, binary_form = true, includes_prefix = nil)
      raise ArgumentError.new("Data cannot be nil") if data.nil?

      if binary_form
        if includes_prefix == true
          @binary_data = data
        else
          @binary_data = BINARY_PREFIX + data
        end
      else
        if includes_prefix == nil || includes_prefix == true
          @json_form = data
        else
          raise ArgumentError.new("CID currently doesn't support binary_form = false with includes_prefix = false")
        end
      end
    end

    def data
      @binary_data ||= BINARY_PREFIX + ::Base32.decode(@json_form[1..-1].upcase)
    end

    def json_form
      @json_form ||= Oxygene::Base32.encode(@binary_data, 1, JSON_PREFIX)
    end

    def to_s
      json_form
    end

    def inspect
      "CID(\"#{json_form}\")"
    end

    def ==(other)
      return false unless other.is_a?(CID)

      if @binary_data && (other_data = other.instance_variable_get('@binary_data'))
        @binary_data == other_data
      elsif @json_form && (other_json = other.instance_variable_get('@json_form'))
        @json_form == other_json
      else
        self.data == other.data
      end
    end

    alias eql? ==

    def hash
      self.data.hash
    end
  end
end
