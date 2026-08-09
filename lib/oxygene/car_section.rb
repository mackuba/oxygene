# frozen_string_literal: true

require_relative 'car_archive'
require 'cbor'

module Oxygene
  class CARSection
    attr_reader :cid, :data

    def initialize(cid, data)
      @cid = cid
      @data = data
    end

    def decoded_body
      @decoded_body ||= CBOR.decode(@data)
    end

    def json_body
      @json_body ||= CARArchive.convert_data(CBOR.decode(@data))
    end

    alias body json_body
  end
end
