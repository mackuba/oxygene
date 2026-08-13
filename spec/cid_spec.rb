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
    ],
    [
      "bafkreiegubtpnqvpcbaj6h3yg4aj3vgu6jscqnxsi35nahotykczoo6kqa",
      "\x01U\x12 \x86\xA0f\xF6\xC2\xAF\x10@\x9F\x1Fx7\x00\x9D\xD4\xD4\xF2d(6\xF2F\xFA\xD0\x1D\xD3\xC2\x85\x97;\xCA\x80".b.freeze
    ]
  ]

  drisl_cid = test_cids[0]
  raw_cid = test_cids[-1]

  shared_examples "a JSON CID constructor" do |build_cid:|
    it "should decode real CID strings" do
      test_cids.each do |string, data|
        cid = build_cid.call(string)

        cid.json_form.should == string
        cid.raw_data.should == data
        cid.cbor_form.should == "\x00".b + data
      end
    end

    it "should reject CIDs with a wrong length" do
      expect { build_cid.call(test_cids.first.first + "a") }.to raise_error(Oxygene::DecodeError)
    end

    it "should reject CIDs with a wrong multibase prefix" do
      string = "z" + test_cids.first.first[1..-1]

      expect { build_cid.call(string) }.to raise_error(Oxygene::DecodeError)
    end

    it "should reject CIDs with a wrong header" do
      string = test_cids.first.first.dup
      string[2] = 't'

      expect { build_cid.call(string) }.to raise_error(Oxygene::UnsupportedError)

      string = test_cids.first.first.dup
      string[7] = 's'

      expect { build_cid.call(string) }.to raise_error(Oxygene::UnsupportedError)
    end

    it "should reject uppercase Base32 characters" do
      string = "b" + test_cids.first.first[1..-1].upcase

      expect { build_cid.call(string) }.to raise_error(Oxygene::DecodeError, "Unexpected characters in CID")
    end

    it "should reject Base32 padding" do
      string = test_cids.first.first.sub(/.$/, "=")

      expect { build_cid.call(string) }.to raise_error(Oxygene::DecodeError, "Unexpected characters in CID")
    end

    it "should reject invalid characters" do
      string = test_cids.first.first.sub(/4/, "9")

      expect { build_cid.call(string) }.to raise_error(Oxygene::DecodeError, "Unexpected characters in CID")
    end

    it "should reject non-zero trailing bits" do
      string = test_cids.first.first.dup
      string.setbyte(58, "b".ord)

      expect { build_cid.call(string) }.to raise_error(Oxygene::DecodeError, "Unexpected CID trailing bits")
    end

    it "should store and freeze the JSON form without generating binary forms" do
      string = test_cids.first.first.dup
      cid = build_cid.call(string)

      cid.json_form.should equal(string)
      cid.json_form.should be_frozen
      cid.instance_variable_get('@cbor_form').should be_nil
      cid.instance_variable_get('@raw_data').should be_nil

      expect { string.setbyte(0, "z".ord) }.to raise_error(FrozenError)
    end

    it "should accept CIDs with either codec" do
      expect { build_cid.call(drisl_cid.first) }.not_to raise_error
      expect { build_cid.call(raw_cid.first) }.not_to raise_error
    end

    it "should reject CIDs with a different than allowed codec" do
      bad_json = test_cids.first.first.dup
      bad_json[3] = 'q'

      expect { build_cid.call(bad_json) }.to raise_error(Oxygene::UnsupportedError)
    end
  end

  shared_examples "a binary CID constructor" do |build_cid:, wrap_binary_data:|
    it "should reject a binary CID with an unsupported version" do
      data = test_cids.first.last.dup
      data.setbyte(0, 2)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected CID version: 2"
      )
    end

    it "should accept CIDs with either supported codec" do
      expect { build_cid.call(wrap_binary_data.call(drisl_cid.last)) }.not_to raise_error
      expect { build_cid.call(wrap_binary_data.call(raw_cid.last)) }.not_to raise_error
    end

    it "should reject CIDs using an unsupported codec" do
      data = test_cids.first.last.dup
      data.setbyte(1, 0x70)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected CID codec: 112"
      )
    end

    it "should reject CIDs with an unsupported hash id" do
      data = test_cids.first.last.dup
      data.setbyte(2, 0x13)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected CID hash: 19"
      )
    end

    it "should reject CIDs with an unsupported hash length" do
      data = test_cids.first.last.dup
      data.setbyte(3, 31)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected CID length: 31"
      )
    end

    it "should reject a binary CID with a non-canonical prefix" do
      data = "\x81\x00".b + test_cids.first.last.byteslice(1, 34)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(
        Oxygene::UnsupportedError, "Non-canonical CID prefix"
      )
    end

    it "should reject a too short binary CID" do
      data = test_cids.first.last.byteslice(0, 35)

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(Oxygene::DecodeError, /CID too short:/)
    end

    it "should reject a too long binary CID" do
      data = test_cids.first.last + "\x00"

      expect { build_cid.call(wrap_binary_data.call(data)) }.to raise_error(Oxygene::DecodeError, /CID too long:/)
    end

    it "should not generate JSON form until needed" do
      data = test_cids.first.last
      cid = build_cid.call(wrap_binary_data.call(data))
      
      cid.instance_variable_get('@json_form').should be_nil

      cid.to_s
      cid.instance_variable_get('@json_form').should_not be_nil
    end
  end

  shared_examples "a prefixed binary CID constructor" do |build_cid:|
    it "should decode real CID data" do
      test_cids.each do |string, data|
        prefixed_data = "\x00".b + data
        cid = build_cid.call(prefixed_data)

        cid.cbor_form.should == prefixed_data
        cid.raw_data.should == data
        cid.json_form.should == string
      end
    end

    it "should reject CID data without the \\x00 prefix" do
      data = "\x01".b + test_cids.first.last
      expect { build_cid.call(data) }.to raise_error(Oxygene::DecodeError)

      data = test_cids.first.last
      expect { build_cid.call(data) }.to raise_error(Oxygene::DecodeError)
    end

    it "should store and freeze the prefixed data without copying it" do
      data = "\x00".b + test_cids.first.last
      cid = build_cid.call(data)

      cid.cbor_form.should equal(data)
      cid.cbor_form.should be_frozen

      expect { data.setbyte(0, 1) }.to raise_error(FrozenError)
    end
  end

  describe ".from_json" do
    include_examples "a JSON CID constructor", build_cid: ->(data) { Oxygene::CID.from_json(data) }
  end

  describe ".from_cbor_tag" do
    include_examples "a binary CID constructor",
      build_cid: ->(data) { Oxygene::CID.from_cbor_tag(CBOR::Tagged.new(42, data)) },
      wrap_binary_data: ->(data) { "\x00".b + data }

    include_examples "a prefixed binary CID constructor",
      build_cid: ->(data) { Oxygene::CID.from_cbor_tag(CBOR::Tagged.new(42, data)) }
  end

  describe "CID.new" do
    context "with JSON data" do
      include_examples "a JSON CID constructor", build_cid: ->(data) { Oxygene::CID.new(data, binary: false) }

      it "should reject nil data" do
        expect { Oxygene::CID.new(nil, binary: false) }.to raise_error(ArgumentError, "Data cannot be nil")
      end

      it "should reject cbor_prefix: true" do
        string = test_cids.first.first

        expect { Oxygene::CID.new(string, binary: false, cbor_prefix: true) }.to raise_error(
          ArgumentError, "cbor_prefix cannot be used with JSON input"
        )
      end

      it "should reject an unknown codec name" do
        expect { Oxygene::CID.new(test_cids.first.first, binary: false, codec: :unknown) }.to raise_error(
          ArgumentError, "Unexpected CID codec: :unknown"
        )
      end

      it "should validate that the CID uses a requested codec, without generating binary forms" do
        cid = Oxygene::CID.new(drisl_cid.first, binary: false, codec: :drisl)

        cid.instance_variable_get('@cbor_form').should be_nil
        cid.instance_variable_get('@raw_data').should be_nil

        cid2 = Oxygene::CID.new(raw_cid.first, binary: false, codec: :raw)

        cid2.instance_variable_get('@cbor_form').should be_nil
        cid2.instance_variable_get('@raw_data').should be_nil

        expect { Oxygene::CID.new(drisl_cid.first, binary: false, codec: :raw) }.to raise_error(Oxygene::UnsupportedError)
        expect { Oxygene::CID.new(raw_cid.first, binary: false, codec: :drisl) }.to raise_error(Oxygene::UnsupportedError)

        bad_json = test_cids.first.first.dup
        bad_json[3] = 'q'

        expect { Oxygene::CID.new(bad_json, binary: false, codec: :drisl) }.to raise_error(Oxygene::UnsupportedError)
        expect { Oxygene::CID.new(bad_json, binary: false, codec: :raw) }.to raise_error(Oxygene::UnsupportedError)
      end
    end

    context "with prefixed binary data" do
      include_examples "a prefixed binary CID constructor",
        build_cid: ->(data) { Oxygene::CID.new(data, cbor_prefix: true) }

      include_examples "a binary CID constructor",
        build_cid: ->(data) { Oxygene::CID.new(data, cbor_prefix: true) },
        wrap_binary_data: ->(data) { "\x00".b + data }

      it "should reject nil data" do
        expect { Oxygene::CID.new(nil, binary: true, cbor_prefix: true) }.to raise_error(ArgumentError, "Data cannot be nil")
      end

      it "should reject an unknown codec name" do
        expect { Oxygene::CID.new("\x00".b + test_cids.first.last, cbor_prefix: true, codec: :unknown) }.to raise_error(
          ArgumentError, "Unexpected CID codec: :unknown"
        )
      end

      it "should validate that the CID uses a requested codec" do
        expect { Oxygene::CID.new("\x00".b + drisl_cid[1], cbor_prefix: true, codec: :drisl) }.to_not raise_error
        expect { Oxygene::CID.new("\x00".b + raw_cid[1], cbor_prefix: true, codec: :raw) }.to_not raise_error

        expect { Oxygene::CID.new("\x00".b + drisl_cid[1], cbor_prefix: true, codec: :raw) }.to raise_error(
          Oxygene::UnsupportedError, /Unexpected CID codec/
        )
        expect { Oxygene::CID.new("\x00".b + raw_cid[1], cbor_prefix: true, codec: :drisl) }.to raise_error(
          Oxygene::UnsupportedError, /Unexpected CID codec/
        )

        bad_data = test_cids.first.last.dup
        bad_data[1] = "\x44"

        expect { Oxygene::CID.new("\x00".b + bad_data, cbor_prefix: true, codec: :drisl) }.to raise_error(
          Oxygene::UnsupportedError, /Unexpected CID codec/
        )
        expect { Oxygene::CID.new("\x00".b + bad_data, cbor_prefix: true, codec: :raw) }.to raise_error(
          Oxygene::UnsupportedError, /Unexpected CID codec/
        )
      end
    end

    context "with unprefixed binary data" do
      include_examples "a binary CID constructor",
        build_cid: ->(data) { Oxygene::CID.new(data) },
        wrap_binary_data: ->(data) { data }

      it "should reject nil data" do
        expect { Oxygene::CID.new(nil, binary: true) }.to raise_error(ArgumentError, "Data cannot be nil")
      end

      it "should decode real CID data" do
        test_cids.each do |string, data|
          cid = Oxygene::CID.new(data)

          cid.raw_data.should == data
          cid.cbor_form.should == "\x00".b + data
          cid.json_form.should == string
        end
      end

      it "should reject an unknown codec name" do
        expect { Oxygene::CID.new(test_cids.first.last, codec: :unknown) }.to raise_error(
          ArgumentError, "Unexpected CID codec: :unknown"
        )
      end

      it "should validate that the CID uses a requested codec" do
        expect { Oxygene::CID.new(drisl_cid[1], codec: :drisl) }.to_not raise_error
        expect { Oxygene::CID.new(raw_cid[1], codec: :raw) }.to_not raise_error

        expect { Oxygene::CID.new(drisl_cid[1], codec: :raw) }.to raise_error(Oxygene::UnsupportedError, /Unexpected CID codec/)
        expect { Oxygene::CID.new(raw_cid[1], codec: :drisl) }.to raise_error(Oxygene::UnsupportedError, /Unexpected CID codec/)

        bad_data = test_cids.first.last.dup
        bad_data[1] = "\x44"

        expect { Oxygene::CID.new(bad_data, codec: :drisl) }.to raise_error(Oxygene::UnsupportedError, /Unexpected CID codec/)
        expect { Oxygene::CID.new(bad_data, codec: :raw) }.to raise_error(Oxygene::UnsupportedError, /Unexpected CID codec/)
      end
    end

    it "should accept binary data explicitly marked as not including the prefix" do
      string, data = test_cids.first
      cid = Oxygene::CID.new(data, cbor_prefix: false)

      cid.raw_data.should == data
      cid.cbor_form.should == "\x00".b + data
      cid.json_form.should == string
    end

    it "should treat binary data as not including the prefix by default" do
      string, data = test_cids.first
      cid = Oxygene::CID.new(data, binary: true)

      cid.raw_data.should == data
      cid.cbor_form.should == "\x00".b + data
      cid.json_form.should == string
    end

    it "should treat data as binary without prefix if only one argument is passed" do
      test_cids.each do |string, data|
        cid = Oxygene::CID.new(data)

        cid.raw_data.should == data
        cid.cbor_form.should == "\x00".b + data
        cid.json_form.should == string
      end
    end
  end

  describe "#cbor_form" do
    context "for CIDs created from CBOR data" do
      it "should return input CBOR data unchanged" do
        data = "\x00".b + test_cids.first.last

        cid = Oxygene::CID.new(data, cbor_prefix: true)
        cid.cbor_form.should equal(data)
        cid.cbor_form.should equal(cid.cbor_form)
        cid.cbor_form.should be_frozen

        expect { cid.cbor_form.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end

    context "for CIDs created from binary data without prefix" do
      it "should add the 0 prefix" do
        data = test_cids.first.last

        cid = Oxygene::CID.new(data, binary: true)
        cid.cbor_form.should == "\x00".b + data

        cid.cbor_form.should be_frozen
        cid.cbor_form.should equal(cid.cbor_form)

        expect { cid.cbor_form.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end

    context "for CIDs created from JSON data" do
      it "should decode JSON to CBOR data" do
        string, data = test_cids.first

        cid = Oxygene::CID.new(string, binary: false)
        cid.cbor_form.should == "\x00".b + data

        cid.cbor_form.should be_frozen
        cid.cbor_form.should equal(cid.cbor_form)

        expect { cid.cbor_form.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end
  end

  describe "#raw_data" do
    context "for CIDs created from CBOR data" do
      it "should return input raw data unchanged" do
        data = test_cids.first.last

        cid = Oxygene::CID.new("\x00".b + data, cbor_prefix: true)
        cid.raw_data.should == data
        cid.raw_data.should equal(cid.raw_data)
        cid.raw_data.should be_frozen

        expect { cid.raw_data.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end

    context "for CIDs created from binary data without prefix" do
      it "should remove the 0 prefix from CBOR data" do
        data = test_cids.first.last.dup
        cid = Oxygene::CID.new(data)

        cid.raw_data.should == data
        cid.raw_data.should equal(cid.raw_data)
        cid.raw_data.should be_frozen

        expect { cid.raw_data.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end

    context "for CIDs created from JSON data" do
      it "should decode JSON to raw data" do
        string, data = test_cids.first

        cid = Oxygene::CID.new(string, binary: false)
        cid.raw_data.should == data
        cid.raw_data.should equal(cid.raw_data)
        cid.raw_data.should be_frozen

        expect { cid.raw_data.setbyte(0, 1) }.to raise_error(FrozenError)
      end
    end
  end

  describe "#data" do
    it "should be an alias for #raw_data" do
      cid = Oxygene::CID.from_cbor_tag(CBOR::Tagged.new(42, "\x00".b + test_cids.first.last))

      cid.data.should equal(cid.raw_data)
      cid.data.should == test_cids.first.last
    end
  end

  describe "#json_form" do
    it "should encode binary data without including the binary prefix" do
      string, data = test_cids.first

      cid = Oxygene::CID.new("\x00".b + data, cbor_prefix: true)
      cid.json_form.should == string
    end

    it "should return JSON input unchanged" do
      string = test_cids.first.first

      cid = Oxygene::CID.new(string, binary: false)
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

        cid = Oxygene::CID.new(string, binary: false)
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
      same = Oxygene::CID.new(first.cbor_form.dup, cbor_prefix: true)
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

        first.instance_variable_get('@raw_data').should be_nil
        first2.instance_variable_get('@raw_data').should be_nil
        second.instance_variable_get('@raw_data').should be_nil
      end
    end

    context "for two JSON CIDs" do
      it "should only look at their JSON forms" do
        first = Oxygene::CID.new(test_cids[0][0], binary: false)
        first2 = Oxygene::CID.new(test_cids[0][0], binary: false)
        second = Oxygene::CID.new(test_cids[1][0], binary: false)

        (first == first2).should == true
        (first == second).should == false

        first.instance_variable_get('@raw_data').should be_nil
        first2.instance_variable_get('@raw_data').should be_nil
        second.instance_variable_get('@raw_data').should be_nil

        first.instance_variable_get('@cbor_form').should be_nil
        first2.instance_variable_get('@cbor_form').should be_nil
        second.instance_variable_get('@cbor_form').should be_nil
      end
    end

    context "for one binary and one JSON CID" do
      it "should compare their CBOR forms" do
        first_j = Oxygene::CID.new(test_cids[0][0], binary: false)
        first2_b = Oxygene::CID.new(test_cids[0][1])
        second_b = Oxygene::CID.new(test_cids[1][1])

        (first_j == first2_b).should == true
        (first_j == second_b).should == false

        first_j.instance_variable_get('@cbor_form').should_not be_nil
        first_j.instance_variable_get('@raw_data').should be_nil

        first2_b.instance_variable_get('@raw_data').should be_nil
        first2_b.instance_variable_get('@json_form').should be_nil

        second_b.instance_variable_get('@raw_data').should be_nil
        second_b.instance_variable_get('@json_form').should be_nil

        third_b = Oxygene::CID.new(test_cids[0][1])
        third2_j = Oxygene::CID.new(test_cids[0][0], binary: false)
        fourth_j = Oxygene::CID.new(test_cids[1][0], binary: false)

        (third_b == third2_j).should == true
        (third_b == fourth_j).should == false

        third_b.instance_variable_get('@json_form').should be_nil
        third_b.instance_variable_get('@raw_data').should be_nil

        third2_j.instance_variable_get('@cbor_form').should_not be_nil
        third2_j.instance_variable_get('@raw_data').should be_nil

        fourth_j.instance_variable_get('@cbor_form').should_not be_nil
        fourth_j.instance_variable_get('@raw_data').should be_nil
      end
    end
  end

  describe "#hash" do
    it "should use hash of the CBOR form" do
      binary_cid = Oxygene::CID.new(test_cids[0][1])
      json_cid = Oxygene::CID.new(test_cids[0][0], binary: false)

      binary_cid.hash.should == binary_cid.cbor_form.hash
      json_cid.hash.should == json_cid.cbor_form.hash
    end
  end
end
