# frozen_string_literal: true

describe Oxygene::Base32 do
  describe ".encode" do
    it "should encode strings to lowercase base32 without padding" do
      {
        "" => "",
        "f" => "my",
        "fo" => "mzxq",
        "foo" => "mzxw6",
        "foob" => "mzxw6yq",
        "fooba" => "mzxw6ytb",
        "foobar" => "mzxw6ytboi"
      }.each do |input, output|
        Oxygene::Base32.encode(input).should == output
      end
    end

    it "should encode binary strings" do
      data = "\x00\x01\xFE\xFF".b

      Oxygene::Base32.encode(data).should == "aaa757y"
    end

    it "should not modify original string" do
      data = "frozen".freeze

      Oxygene::Base32.encode(data)
    end

    it "should start encoding at a given byte offset" do
      Oxygene::Base32.encode("testsomething", 4).should == "onxw2zlunbuw4zy"
      Oxygene::Base32.encode("something").should == "onxw2zlunbuw4zy"
    end

    it "should add a prefix if passed" do
      prefix = "base32:".freeze

      Oxygene::Base32.encode("teststringtotest", 0, prefix).should == "base32:orsxg5dtorzgs3thorxxizltoq"
    end

    it "should combine a byte offset with a prefix" do
      Oxygene::Base32.encode("discardfoobar", 7, "b").should == "bmzxw6ytboi"
    end

    it "should return only the prefix when the offset is at the end" do
      Oxygene::Base32.encode("foobar", 6, "b").should == "b"
    end

    it "should reject a negative start offset" do
      expect { Oxygene::Base32.encode("test", -1) }.to raise_error(ArgumentError, "Start offset can't be negative")
    end

    it "should reject a start offset past the end" do
      expect { Oxygene::Base32.encode("test", 5) }.to raise_error(ArgumentError, "Start offset is larger than the length of data")
    end
  end

  describe ".decode" do
    it "should decode lowercase Base32 strings without padding" do
      {
        "" => "",
        "my" => "f",
        "mzxq" => "fo",
        "mzxw6" => "foo",
        "mzxw6yq" => "foob",
        "mzxw6ytb" => "fooba",
        "mzxw6ytboi" => "foobar"
      }.each do |input, output|
        Oxygene::Base32.decode(input).should == output
      end
    end

    it "should decode uppercase and padded Base32 strings" do
      Oxygene::Base32.decode("MZXW6YTBOI======").should == "foobar"
    end

    it "should decode binary strings" do
      Oxygene::Base32.decode("aaa757y").should == "\x00\x01\xFE\xFF".b
    end

    it "should return a binary string" do
      Oxygene::Base32.decode("mzxw6").encoding.should == Encoding::BINARY
    end

    it "should not modify the original string" do
      data = "aaa757y".freeze

      Oxygene::Base32.decode(data)
    end

    it "should start decoding at a given byte offset" do
      Oxygene::Base32.decode("testonxw2zlunbuw4zy", 4).should == "something"
      Oxygene::Base32.decode("onxw2zlunbuw4zy").should == "something"
    end

    it "should add a prefix if passed" do
      prefix = "00".freeze

      Oxygene::Base32.decode("mzxw6ytboi", 0, prefix).should == "00foobar"
    end

    it "should combine a byte offset with a binary prefix" do
      Oxygene::Base32.decode("bmzxw6ytboi", 1, "\x00".b).should == "\x00foobar".b
    end

    it "should return only the prefix when the offset is at the end" do
      Oxygene::Base32.decode("discard", 7, "\x00".b).should == "\x00".b
    end

    it "should reject a negative start offset" do
      expect { Oxygene::Base32.decode("mzxw6", -1) }.to raise_error(ArgumentError, "Start offset can't be negative")
    end

    it "should reject a start offset past the end" do
      expect { Oxygene::Base32.decode("mzxw6", 6) }.to raise_error(ArgumentError, "Start offset is larger than the length of data")
    end

    it "should reject invalid characters" do
      expect { Oxygene::Base32.decode("mzx!6") }.to raise_error(ArgumentError, /Invalid Base32 character/)
      expect { Oxygene::Base32.decode("mzxw6yt+") }.to raise_error(ArgumentError, /Invalid Base32 character/)
    end

    it "should reject invalid lengths" do
      expect { Oxygene::Base32.decode("m") }.to raise_error(ArgumentError, "Invalid Base32 length")
    end

    it "should reject invalid padding" do
      expect { Oxygene::Base32.decode("my=====") }.to raise_error(ArgumentError, "Invalid Base32 padding")
    end

    it "should reject non-zero trailing bits" do
      expect { Oxygene::Base32.decode("mz") }.to raise_error(ArgumentError, "Invalid Base32 trailing bits")
    end
  end
end
