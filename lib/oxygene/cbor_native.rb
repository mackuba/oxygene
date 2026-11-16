# frozen_string_literal: true

require 'cbor'

require_relative 'cbor'
require_relative 'errors'

module Oxygene
  module CBOR
    def self.native_module?
      true
    end

    def self.decode(data, json: false)
      decoded = ::CBOR.decode(data)
      decoded = convert_data(decoded) if json
      decoded
    rescue EOFError, ::CBOR::UnpackError => e
      raise DecodeError, e.message
    end

    def self.decode_sequence(data, json: false)
      unpacker = ::CBOR::Unpacker.new
      unpacker.feed(data)

      items = []

      while !unpacker.buffer.empty?
        item = unpacker.read
        item = convert_data(item) if json
        items << item
      end

      items
    rescue EOFError, ::CBOR::UnpackError => e
      raise DecodeError, e.message
    end

    def self.convert_data(value)
      case value
      when Hash
        value.transform_values! { |item| convert_data(item) }
      when Array
        value.map! { |item| convert_data(item) }
      when ::CBOR::Tagged
        raise UnsupportedError, "Only CBOR tag 42 (CID) is supported (got: #{value.tag})" unless value.tag == 42

        bytes = value.value

        if !bytes.is_a?(String)
          raise DecodeError, "CBOR tag 42 must contain a byte string (got: #{bytes.class})"
        elsif bytes.encoding != Encoding::BINARY
          raise DecodeError, "CBOR tag 42 must contain a byte string (got a #{bytes.encoding} string)"
        end

        cid = CID.from_cbor_bytes(bytes)

        { '$link' => cid }
      when String
        (value.encoding == Encoding::BINARY) ? Oxygene::CBOR.make_bytes(value) : value
      else
        value
      end
    end

    private_class_method :convert_data
  end
end
