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
  end
end
