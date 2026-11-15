# frozen_string_literal: true

require 'oxygene/varint_reader'

describe Oxygene::VarintReader do
  it "should start at offset zero and read consecutive varints" do
    reader = Oxygene::VarintReader.new("\x00\x10\x7F\x80\x01".b)

    reader.offset.should == 0

    reader.read_next.should == 0
    reader.offset.should == 1

    reader.read_next.should == 16
    reader.offset.should == 2

    reader.read_next.should == 127
    reader.offset.should == 3

    reader.read_next.should == 128
    reader.offset.should == 5
  end

  it "should read from an explicit byte offset and then continue from the new offset" do
    reader = Oxygene::VarintReader.new("\xC3\xA9\xAC\x02\x07")

    reader.read(2).should == 300
    reader.offset.should == 4

    reader.read_next.should == 7
    reader.read(2).should == 300
  end

  it "should read the largest nine-byte varint" do
    reader = Oxygene::VarintReader.new(("\xFF".b * 8) + "\x7F".b)

    reader.read_next.should == (2**63 - 1)
    reader.offset.should == 9
  end

  it "should reject input without a varint" do
    reader = Oxygene::VarintReader.new("".b)

    expect { reader.read_next }.to raise_error(Oxygene::DecodeError, "Unexpected end of data while reading varint")
  end

  it "should leave the offset unchanged after a truncated varint" do
    reader = Oxygene::VarintReader.new("\x01\x80".b)
    reader.read_next.should == 1

    expect { reader.read_next }.to raise_error(Oxygene::DecodeError, "Unexpected end of data while reading varint")

    reader.offset.should == 1
  end

  it "should reject non-minimal encodings" do
    ["\x80\x00".b, "\x81\x80\x00".b].each do |bytes|
      reader = Oxygene::VarintReader.new(bytes)

      expect { reader.read_next }.to raise_error(Oxygene::NonMinimalEncodingError)

      reader.offset.should == 0
    end
  end

  it "should reject varints longer than the maximum allowed number of bytes" do
    data = "\x80".b * 9

    [data, data + "\x01".b].each do |bytes|
      reader = Oxygene::VarintReader.new(bytes)

      expect { reader.read_next }.to raise_error(Oxygene::DecodeError, "Varint length exceeds limit")

      reader.offset.should == 0
    end
  end

  it "should reject negative offsets" do
    reader = Oxygene::VarintReader.new("\x01".b)

    expect { reader.read(-1) }.to raise_error(ArgumentError, "Negative varint offset")
  end
end
