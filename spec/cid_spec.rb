# frozen_string_literal: true

describe Oxygene::CID do
  test_cids = [
    [
      "bafyreihsl77homddrramzhzdrgfneatthwnlz47ikzy4mezxz7kxndmjsm",
      "\x01q\x12 \xF2_\xFEw0c\x8C@\xCC\x9F#\x89\x8A\xD2\x02s=\x9A\xBC\xF3\xE8Vq\xC6\x137\xCF\xD5v\x8D\x89\x93".b.freeze
    ],
    [
      "bafyreigpanzjuqvy3uzqwhbymw7vok2ue5v5cp7dhf2bgnz3wg53cuumn4",
      "\x01q\x12 \xCF\x03r\x9AB\xB8\xDD3\v\x1C8e\xBFW+T'k\xD1?\xE39t\x137;\xB1\xBB\xB1R\x8Co".b.freeze
    ],
    [
      "bafyreia2rdzvv7fjlpilxfzwvx7pp4afj3h3aphdmk4ankikmnxqt2vtjy",
      "\x01q\x12 \x1A\x88\xF3Z\xFC\xA9[\xD0\xBB\x976\xAD\xFE\xF7\xF0\x05N\xCF\xB0<\xE3b\xB8\x06\xA9\nco\t\xEA\xB3N".b.freeze
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

    it "should store the CID data with the 0 prefix" do
      data = test_cids.first.last
      tag = CBOR::Tagged.new(42, ("\x00".b + data).freeze)

      cid = Oxygene::CID.from_cbor_tag(tag)
      cid.instance_variable_get('@binary_data').should == tag.value
    end

    it "should not generate JSON form until needed" do
      data = test_cids.first.last
      tag = CBOR::Tagged.new(42, ("\x00".b + data).freeze)

      cid = Oxygene::CID.from_cbor_tag(tag)
      cid.instance_variable_get('@json_form').should be_nil

      cid.to_s
      cid.instance_variable_get('@json_form').should_not be_nil
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

    it "should not generate binary form until needed" do
      string = test_cids.first.first

      cid = Oxygene::CID.from_json(string)
      cid.instance_variable_get('@binary_data').should be_nil

      cid.data
      cid.instance_variable_get('@binary_data').should_not be_nil
    end
  end

  describe "CID.new" do
    it "should accept binary data including the prefix" do
      string, data = test_cids.first
      prefixed_data = "\x00".b + data
      cid = Oxygene::CID.new(prefixed_data, true, true)

      cid.data.should == prefixed_data
      cid.json_form.should == string
    end

    it "should freeze the binary data it stores without copying it" do
      data = ("\x00".b + test_cids.first.last).dup
      cid = Oxygene::CID.new(data, true, true)

      cid.data.should equal(data)
      cid.data.should be_frozen

      expect { data.setbyte(0, 1) }.to raise_error(FrozenError)
    end

    it "should accept binary data explicitly marked as not including the prefix" do
      string, data = test_cids.first
      cid = Oxygene::CID.new(data, true, false)

      cid.data.should == "\x00".b + data
      cid.json_form.should == string
    end

    it "should treat binary data as not including the prefix by default" do
      string, data = test_cids.first
      cid = Oxygene::CID.new(data, true)

      cid.data.should == "\x00".b + data
      cid.json_form.should == string
    end

    it "should treat data as binary without prefix if only one argument is passed" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.new(data)

        cid.data.should == "\x00".b + data
        cid.json_form.should == string
      end
    end

    it "should accept JSON form input when second argument is false" do
      string, data = test_cids.first

      [nil, true].each do |includes_prefix|
        cid = Oxygene::CID.new(string, false, includes_prefix)

        cid.json_form.should == string
        cid.data.should == "\x00".b + data
      end
    end

    it "should freeze the JSON data it stores without copying it" do
      string = test_cids.first.first.dup
      cid = Oxygene::CID.new(string, false)

      cid.json_form.should equal(string)
      cid.json_form.should be_frozen

      expect { string.setbyte(0, "z".ord) }.to raise_error(FrozenError)
    end

    it "should reject JSON data with includes_prefix = false" do
      string = test_cids.first.first

      expect { Oxygene::CID.new(string, false, false) }.to raise_error(ArgumentError)
    end

    it "should reject nil data" do
      expect { Oxygene::CID.new(nil) }.to raise_error(ArgumentError, "Data cannot be nil")
      expect { Oxygene::CID.new(nil, true) }.to raise_error(ArgumentError, "Data cannot be nil")
      expect { Oxygene::CID.new(nil, false) }.to raise_error(ArgumentError, "Data cannot be nil")
    end
  end

  describe "#data" do
    it "should return input data for binary CIDs with prefix" do
      string, data = test_cids.first

      cid = Oxygene::CID.new(data, true, true)
      cid.data.should equal(data)
    end

    it "should return input data with prefix added for binary CIDs without prefix" do
      string, data = test_cids.first

      cid = Oxygene::CID.new(data, true)
      cid.data.should == "\x00".b + data
    end

    it "should decode JSON to prefixed binary data for JSON CIDs" do
      string, data = test_cids.first

      cid = Oxygene::CID.new(string, false)
      cid.data.should == "\x00".b + data
    end

    it "should freeze generated binary data" do
      cid = Oxygene::CID.new(test_cids.first.first, false)

      cid.data.should be_frozen
      cid.data.should equal(cid.data)

      expect { cid.data.setbyte(0, 1) }.to raise_error(FrozenError)
    end
  end

  describe "#json_form" do
    it "should encode binary data without including the binary prefix" do
      string, data = test_cids.first

      cid = Oxygene::CID.new("\x00".b + data, true, true)
      cid.json_form.should == string
    end

    it "should return JSON input unchanged" do
      string = test_cids.first.first

      cid = Oxygene::CID.new(string, false)
      cid.json_form.should equal(string)
    end

    it "should freeze generated JSON data" do
      cid = Oxygene::CID.new(test_cids.first.last)

      cid.json_form.should be_frozen
      cid.json_form.should equal(cid.json_form)

      expect { cid.json_form.setbyte(0, "z".ord) }.to raise_error(FrozenError)
    end
  end

  describe "#to_s" do
    it "should return the JSON form of the CID" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.new(data)
        cid.to_s.should == string

        cid = Oxygene::CID.new(string, false)
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

    context "for two binary CIDs" do
      it "should only look at their binary forms" do
        first = Oxygene::CID.new(test_cids[0][1])
        first2 = Oxygene::CID.new(test_cids[0][1])
        second = Oxygene::CID.new(test_cids[1][1])

        (first == first2).should == true
        (first == second).should == false

        first.instance_variable_get('@json_form').should be_nil
        first2.instance_variable_get('@json_form').should be_nil
        second.instance_variable_get('@json_form').should be_nil
      end
    end

    context "for two JSON CIDs" do
      it "should only look at their JSON forms" do
        first = Oxygene::CID.new(test_cids[0][0], false)
        first2 = Oxygene::CID.new(test_cids[0][0], false)
        second = Oxygene::CID.new(test_cids[1][0], false)

        (first == first2).should == true
        (first == second).should == false

        first.instance_variable_get('@binary_data').should be_nil
        first2.instance_variable_get('@binary_data').should be_nil
        second.instance_variable_get('@binary_data').should be_nil
      end
    end

    context "for one binary and one JSON CID" do
      it "should compare their binary forms" do
        first_j = Oxygene::CID.new(test_cids[0][0], false)
        first2_b = Oxygene::CID.new(test_cids[0][1])
        second_b = Oxygene::CID.new(test_cids[1][1])

        (first_j == first2_b).should == true
        (first_j == second_b).should == false

        first_j.instance_variable_get('@binary_data').should_not be_nil
        first2_b.instance_variable_get('@json_form').should be_nil
        second_b.instance_variable_get('@json_form').should be_nil

        third_b = Oxygene::CID.new(test_cids[0][1])
        third2_j = Oxygene::CID.new(test_cids[0][0], false)
        fourth_j = Oxygene::CID.new(test_cids[1][0], false)

        (third_b == third2_j).should == true
        (third_b == fourth_j).should == false

        third_b.instance_variable_get('@json_form').should be_nil
        third2_j.instance_variable_get('@binary_data').should_not be_nil
        fourth_j.instance_variable_get('@binary_data').should_not be_nil
      end
    end
  end

  describe "#hash" do
    it "should use hash of the binary data" do
      binary_cid = Oxygene::CID.new(test_cids[0][1])
      json_cid = Oxygene::CID.new(test_cids[0][0], false)

      binary_cid.hash.should == binary_cid.data.hash
      json_cid.hash.should == json_cid.data.hash
    end
  end
end
