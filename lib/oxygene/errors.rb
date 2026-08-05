# frozen_string_literal: true

module Oxygene
  #
  # Wrapper base class for Oxygene error classes.
  #
  class Error < StandardError
  end

  #
  # Raised when some part of the data being decoded has invalid format.
  #
  class DecodeError < Error
  end

  #
  # Raised when a piece of data is technically formatted correctly, but not in a version
  # that this library currently supports (or that is used in ATProto).
  #
  class UnsupportedError < Error
  end
end
