# frozen_string_literal: true

require_relative "lib/oxygene/version"

Gem::Specification.new do |spec|
  spec.name = "oxygene"
  spec.version = Oxygene::VERSION
  spec.authors = ["Kuba Suder"]
  spec.email = ["jakub.suder@gmail.com"]

  spec.summary = "TODO: Write a short summary, because RubyGems requires one."
  spec.description = "TODO: Write a longer description or delete this line."
  spec.homepage = "TODO: Put your gem's website or public repo URL here."

  spec.license = "Zlib"
  spec.required_ruby_version = ">= 2.6.0"
  
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir['*.md'] + Dir['*.txt'] + Dir['lib/**/*'] + Dir['sig/**/*']
  end

  spec.require_paths = ["lib"]

  spec.add_dependency 'base32', '~> 0.3'
  spec.add_dependency 'base64', '~> 0.1'
  spec.add_dependency 'cbor', '~> 0.5.9'
end
