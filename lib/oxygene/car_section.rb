# frozen_string_literal: true

require_relative 'car_archive'
require 'cbor'

module Oxygene
  class CARSection
    attr_reader :cid

    def initialize(cid, body_data)
      @cid = cid
      @body_data = body_data
    end

    def body
      @body ||= CARArchive.convert_data(CBOR.decode(@body_data))
    end
  end
end
