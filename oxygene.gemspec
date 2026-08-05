# frozen_string_literal: true

require_relative "lib/oxygene/version"

Gem::Specification.new do |spec|
  spec.name = "oxygene"
  spec.version = Oxygene::VERSION
  spec.authors = ["Kuba Suder"]
  spec.email = ["jakub.suder@gmail.com"]

  spec.summary = "Various data decoding primitives for ATProto (CAR, CID, CBOR)"
  spec.homepage = "https://ruby.sdk.blue"

  spec.license = "Zlib"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata = {
    "bug_tracker_uri" => "https://tangled.org/mackuba.eu/oxygene/issues",
    "changelog_uri"   => "https://tangled.org/mackuba.eu/oxygene/blob/master/CHANGELOG.md",
    "source_code_uri" => "https://tangled.org/mackuba.eu/oxygene",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir['*.md'] + Dir['*.txt'] + Dir['lib/**/*'] + Dir['sig/**/*']
  end

  spec.require_paths = ["lib"]

  spec.add_dependency 'base32', '~> 0.3'
  spec.add_dependency 'base64', '~> 0.1'
  spec.add_dependency 'cbor', '~> 0.5.9'
end
