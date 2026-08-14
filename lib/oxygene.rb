# frozen_string_literal: true

require_relative 'oxygene/base32'
require_relative 'oxygene/car_archive'
require_relative 'oxygene/car_repo'
require_relative 'oxygene/cid'
require_relative 'oxygene/version'

#
# Various data decoding related primitives for working with AT Protocol repositories
# and firehose events.
#
# This gem was extracted from [Skyfall](https://ruby.sdk.blue/skyfall/) and is mostly
# used there for the CBOR firehose decoding, but can also be used standalone for other
# ATProto data handling purposes, like decoding downloaded .car account repos.
#
# The functionality currently includes: Base32 encoder/decoder, CAR archive/repo parser,
# CID wrapper, and CBOR decoding (through the `cbor` gem for now).
#
# The gem intentionally only includes support for the parts of these standards that are
# in use in ATProto, i.e. doesn't handle all possible types of CIDs defined in the CID
# standard, only generates lowercase Base32, and so on.
#

module Oxygene
end
