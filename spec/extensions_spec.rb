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
