# frozen_string_literal: true

require_relative 'base32'
require_relative 'errors'

require 'base32'

# CIDs in DAG-CBOR: https://ipld.io/specs/codecs/dag-cbor/spec/
# CIDs in JSON: https://ipld.io/specs/codecs/dag-json/spec/
# multibase: https://github.com/multiformats/multibase

module Oxygene
  class CID

    def self.from_cbor_tag(tag)
      data = tag.value
      raise DecodeError.new("Unexpected first byte of CID: #{data[0]}") unless data[0] == "\x00"

      CID.new(data, true, true)
    end

    def self.from_json(string)
      raise DecodeError.new("Unexpected CID length") unless string.length == 59
      raise DecodeError.new("Unexpected CID prefix") unless string[0] == 'b'

      CID.new(string, false)
    end

    def initialize(data, binary_form = true, includes_prefix = nil)
      raise ArgumentError.new("Data cannot be nil") if data.nil?

      if binary_form
        if includes_prefix == true
          @binary_data = data
        else
          @binary_data = "\x00" + data
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
      @binary_data ||= "\x00" + ::Base32.decode(@json_form[1..-1].upcase)
    end

    def json_form
      @json_form ||= Oxygene::Base32.encode(@binary_data, 1, 'b')
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
