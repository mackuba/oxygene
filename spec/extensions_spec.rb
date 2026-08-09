# frozen_string_literal: true

using Oxygene::Extensions

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
