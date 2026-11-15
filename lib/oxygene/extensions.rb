# frozen_string_literal: true

require 'stringio'
require_relative 'errors'

module Oxygene

  # @private
  module Extensions

    refine StringIO do
      # https://en.wikipedia.org/wiki/LEB128
      def read_varint
        shift = 1
        value = 0

        loop do
          byte = self.readbyte
          value += byte % 128 * shift
          break if byte < 128
          shift *= 128
        end

        value
      rescue EOFError
        raise DecodeError, "Unexpected end of data while reading varint"
      end
    end

  end
end
