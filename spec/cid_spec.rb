# frozen_string_literal: true

describe Oxygene::CID do
  test_cids = [
    [
      "bafyreihsl77homddrramzhzdrgfneatthwnlz47ikzy4mezxz7kxndmjsm",
      "\x01q\x12 \xF2_\xFEw0c\x8C@\xCC\x9F#\x89\x8A\xD2\x02s=\x9A\xBC\xF3\xE8Vq\xC6\x137\xCF\xD5v\x8D\x89\x93".b
    ],
    [
      "bafyreigpanzjuqvy3uzqwhbymw7vok2ue5v5cp7dhf2bgnz3wg53cuumn4",
      "\x01q\x12 \xCF\x03r\x9AB\xB8\xDD3\v\x1C8e\xBFW+T'k\xD1?\xE39t\x137;\xB1\xBB\xB1R\x8Co".b
    ],
    [
      "bafyreia2rdzvv7fjlpilxfzwvx7pp4afj3h3aphdmk4ankikmnxqt2vtjy",
      "\x01q\x12 \x1A\x88\xF3Z\xFC\xA9[\xD0\xBB\x976\xAD\xFE\xF7\xF0\x05N\xCF\xB0<\xE3b\xB8\x06\xA9\nco\t\xEA\xB3N".b
    ]
  ]

  describe ".from_cbor_tag" do
    it "should decode real CID data" do
      test_cids.each do |string, data|
        tag = CBOR::Tagged.new(42, ("\x00".b + data).freeze)

        cid = Oxygene::CID.from_cbor_tag(tag)
        cid.data.should == tag.value
        cid.should == Oxygene::CID.from_json(string)
      end
    end

    it "should reject CID data without the identity prefix" do
      data = test_cids.first.last
      tag = CBOR::Tagged.new(42, ("\x01".b + data).freeze)

      expect { Oxygene::CID.from_cbor_tag(tag) }.to raise_error(Oxygene::DecodeError)
    end
  end

  describe ".from_json" do
    it "should decode real CID strings" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.from_json(string)

        cid.data.should == "\x00".b + data
        cid.to_s.should == string

        cid = Oxygene::CID.from_json(string)

        cid.to_s.should == string
        cid.data.should == "\x00".b + data
      end
    end

    it "should reject CIDs with a wrong length" do
      string = (test_cids.first.first + "a").freeze

      expect { Oxygene::CID.from_json(string) }.to raise_error(Oxygene::DecodeError)
    end

    it "should reject CIDs with a wrong multibase prefix" do
      string = ("z" + test_cids.first.first[1..-1]).freeze

      expect { Oxygene::CID.from_json(string) }.to raise_error(Oxygene::DecodeError)
    end
  end

  describe "CID.new" do
    it "should accept binary data without the \\x00 prefix" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.new(data)
        cid.data.should == "\x00".b + data
        cid.should == Oxygene::CID.from_json(string)
      end
    end
  end

  describe "#to_s" do
    it "should return the JSON form of the CID" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.new(data)

        cid.to_s.should == string
      end
    end
  end

  describe "#inspect" do
    it "should include the CID in its JSON form" do
      string, data = test_cids.first
      cid = Oxygene::CID.new(data)

      cid.inspect.should == %(CID("#{string}"))
    end
  end

  describe "#==" do
    it "should compare CID data" do
      first = Oxygene::CID.from_json(test_cids[0][0])
      same = Oxygene::CID.new(first.data.dup, true, true)
      different = Oxygene::CID.from_json(test_cids[1][0])

      (first == same).should == true
      (first == different).should == false
      (first == first.data).should == false
    end
  end
end
