# frozen_string_literal: true

describe Oxygene::CARSection do
  cid_data = "\x00\x01\x71\x12\x20".b + ("\x11".b * 32)
  tagged_cid = CBOR::Tagged.new(42, cid_data)

  body_object = {
    "type" => "example",
    "bytes" => "\x00\x01\x02\xFF".b,
    "link" => tagged_cid
  }

  encoded_data = CBOR.encode(body_object)

  let(:cid) { Oxygene::CID.new(cid_data, true, true) }
  let(:section) { Oxygene::CARSection.new(cid, encoded_data) }

  describe "#data" do
    it "should return the CBOR data that was passed to initializer" do
      section.data.should == encoded_data
    end
  end

  describe "#decoded_body" do
    it "should return decoded CBOR values without DAG-JSON conversion" do
      body = section.decoded_body
      body.should be_a(Hash)

      body['type'].should == "example"
      body['bytes'].should == "\x00\x01\x02\xFF".b
      body['link'].should be_a(CBOR::Tagged)
      body['link'].value.should == cid_data
    end
  end

  describe "#json_body" do
    it "should convert byte strings and CID tags to DAG-JSON values" do
      body = section.json_body
      body.should be_a(Hash)

      body['type'].should == "example"
      body['bytes'].should == { "$bytes" => "AAEC/w" }
      body['link'].should == { "$link" => Oxygene::CID.new(cid_data, true, true) }
    end

    it "should not modify the value returned from #decoded_body" do
      decoded_body = section.decoded_body

      section.json_body

      decoded_body['bytes'].should == "\x00\x01\x02\xFF".b
      decoded_body['link'].should be_a(CBOR::Tagged)
    end
  end

  describe "#body" do
    it "should be an alias for #json_body" do
      section.body.should equal(section.json_body)
    end
  end
end
