# frozen_string_literal: true

using Oxygene::Extensions

describe StringIO do
  describe "#read_varint" do
    it "should reject input without a varint" do
      expect { StringIO.new("".b).read_varint }.to raise_error(
        Oxygene::DecodeError, "Unexpected end of data while reading varint"
      )
    end

    it "should reject a truncated multi-byte varint" do
      expect { StringIO.new("\x80".b).read_varint }.to raise_error(
        Oxygene::DecodeError, "Unexpected end of data while reading varint"
      )
    end
  end
end

describe CBOR do
  def encoded_sequence(items)
    items.map { |item| CBOR.encode(item) }.join
  end

  describe ".decode_sequence" do
    it "should decode a sequence with no items" do
      CBOR.decode_sequence("".b).should == []
    end

    it "should decode a sequence with one item" do
      items = [1]

      CBOR.decode_sequence(encoded_sequence(items)).should == items
    end

    it "should decode a sequence with two items" do
      items = [1, "two"]

      CBOR.decode_sequence(encoded_sequence(items)).should == items
    end

    it "should decode a sequence with three items" do
      items = [1, "two", { "three" => 3 }]

      CBOR.decode_sequence(encoded_sequence(items)).should == items
    end
  end
end
