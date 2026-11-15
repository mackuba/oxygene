# frozen_string_literal: true

require 'json'
require 'oxygene/star_archive'

describe Oxygene::STARArchive do
  valid_fixtures = JSON.parse(File.read(File.expand_path("fixtures/star/valid-star-fixtures.json", __dir__)))
  invalid_fixtures = JSON.parse(File.read(File.expand_path("fixtures/star/invalid-star-fixtures.json", __dir__)))

  valid_fixtures.each do |item|
    it "should accept '#{item['comment']}'" do
      hex = item['star_hex']
      binary = [hex].pack('H*')
      meta = item['decoded']['meta']

      pairs = item['decoded']['pairs'].map { |data| [
        [data['key_hex']].pack('H*'),
        [data['value_hex']].pack('H*')
      ]}

      star = Oxygene::STARArchive.new(binary)

      star.metadata.should == meta
      star.data_pairs.should == pairs
    end
  end

  invalid_fixtures.each do |item|
    comment = item['comment']

    if $native_cbor
      next if comment.include?('invalid drisl') || comment == 'non-canonical meta serialization'
    end

    it "should reject '#{comment}'" do
      hex = item['star_hex']
      binary = [hex].pack('H*')

      expect { Oxygene::STARArchive.new(binary) }.to raise_error(Oxygene::DecodeError)
    end
  end
end
