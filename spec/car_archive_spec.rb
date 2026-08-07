# frozen_string_literal: true

describe Oxygene::CARArchive do
  fixture_path = File.expand_path("fixtures/friday.car", __dir__)
  fixture_data = File.binread(fixture_path)

  root_cid = "bafyreiaplw3orif2rpycru2nqgtq4g6o3y32veldq2uboq6owkehn43gzi"
  data_cid = "bafyreibkjye2pyd4lo3geoy7prk7k63zohttpkzgvvtbm2zbwgdolorzse"
  record_cid = "bafyreif2ezn3unua3qk7j6cc2zamkjb2zxkyont7ipmbrd3pzzyp3wbaki"
  header_size = fixture_data.getbyte(0) + 1
  first_section_cid_offset = fixture_data.index("\x01\x71\x12\x20".b, header_size)

  let(:archive) { Oxygene::CARArchive.new(fixture_data) }

  describe ".new" do
    it "should reject a truncated header" do
      truncated_data = fixture_data.byteslice(0, 20)

      expect { Oxygene::CARArchive.new(truncated_data) }.to raise_error(Oxygene::DecodeError, /Header too short/)
    end

    it "should reject an unsupported CAR version" do
      unsupported_data = fixture_data.sub("gversion\x01".b, "gversion\x02".b)

      expect { Oxygene::CARArchive.new(unsupported_data) }.to raise_error(Oxygene::UnsupportedError, "Unexpected CAR version: 2")
    end
  end

  describe "lazy section loading" do
    it "should not load sections until requested" do
      loaded_sections = archive.instance_variable_get(:@sections)
      loaded_sections.should be_empty
    end

    it "should load only up to a section requested by CID" do
      loaded_sections = archive.instance_variable_get(:@sections)

      archive.section_with_cid(Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4"))
      loaded_sections.length.should == 3

      archive.section_with_cid(Oxygene::CID.from_json(record_cid))
      loaded_sections.length.should == 10
      loaded_sections.last.cid.to_s.should == record_cid
    end

    it "should not load more sections if the requested section is already loaded" do
      loaded_sections = archive.instance_variable_get(:@sections)

      archive.section_with_cid(Oxygene::CID.from_json(record_cid))
      loaded_sections.length.should == 10

      archive.section_with_cid(Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4"))
      loaded_sections.length.should == 10
    end

    it "should load every section when a non-existing section is requested" do
      loaded_sections = archive.instance_variable_get(:@sections)

      archive.section_with_cid(Oxygene::CID.from_json("bafyreihqweqweqweqweg27d53547wrc4zwcohkah76hq55nohacsdacfm4"))

      loaded_sections.length.should == 11
    end

    it "should load every section when .sections is called" do
      loaded_sections = archive.instance_variable_get(:@sections)

      archive.sections

      loaded_sections.length.should == 11
      loaded_sections.last.cid.to_s.should == root_cid
    end
  end

  describe "#roots" do
    it "should return the CID of the archive roots" do
      archive.roots.map(&:to_s).should == [root_cid]
    end
  end

  describe "#sections" do
    it "should decode all sections" do
      sections = archive.sections

      sections.length.should == 11
      sections.first.cid.to_s.should == data_cid
      sections[-2].cid.to_s.should == record_cid
      sections.last.cid.should == archive.roots.first
    end

    it "should reject truncated sections" do
      truncated_data = fixture_data.byteslice(0, fixture_data.bytesize - 1)
      truncated_archive = Oxygene::CARArchive.new(truncated_data)

      expect { truncated_archive.sections }.to raise_error(Oxygene::DecodeError, /Section too short/)
    end

    it "should reject unsupported CID version" do
      unsupported_data = fixture_data.dup
      unsupported_data.setbyte(first_section_cid_offset, 2)
      unsupported_archive = Oxygene::CARArchive.new(unsupported_data)

      expect { unsupported_archive.sections }.to raise_error(Oxygene::UnsupportedError, "Unexpected CID version: 2")
    end

    it "should reject unsupported CID codec" do
      unsupported_data = fixture_data.dup
      unsupported_data.setbyte(first_section_cid_offset + 1, 0x70)
      unsupported_archive = Oxygene::CARArchive.new(unsupported_data)

      expect { unsupported_archive.sections }.to raise_error(Oxygene::UnsupportedError, "Unexpected CID codec: 112")
    end

    it "should reject unsupported CID hash" do
      unsupported_data = fixture_data.dup
      unsupported_data.setbyte(first_section_cid_offset + 2, 0x13)
      unsupported_archive = Oxygene::CARArchive.new(unsupported_data)

      expect { unsupported_archive.sections }.to raise_error(Oxygene::UnsupportedError, "Unexpected CID hash: 19")
    end

    it "should reject unsupported CID length" do
      unsupported_data = fixture_data.dup
      unsupported_data.setbyte(first_section_cid_offset + 3, 31)
      unsupported_archive = Oxygene::CARArchive.new(unsupported_data)

      expect { unsupported_archive.sections }.to raise_error(Oxygene::UnsupportedError, "Unexpected CID length: 31")
    end

    it "should reject a truncated CID" do
      short_section = fixture_data.byteslice(first_section_cid_offset, 20)
      truncated_data = fixture_data.byteslice(0, header_size) + "\x14".b + short_section
      truncated_archive = Oxygene::CARArchive.new(truncated_data)

      expect { truncated_archive.sections }.to raise_error(Oxygene::DecodeError, /CID too short/)
    end
  end

  describe "#section_with_cid" do
    it "should find a section with given CID and return its body" do
      cid = Oxygene::CID.from_json(record_cid)

      body = archive.section_with_cid(cid)
      body.should be_a(Hash)
    end

    it "should return nil when the CID is not in the archive" do
      missing_cid = Oxygene::CID.from_json("bafyreihsl77homddrramzhzdrgfneatthwnlz47ikzy4mezxz7kxndmjsm")

      archive.section_with_cid(missing_cid).should be_nil
    end

    it "should decode the firehose record body" do
      cid = Oxygene::CID.from_json(record_cid)

      archive.section_with_cid(cid).should == {
        "text" => "I have some amazing news everyone. It’s Friday.",
        "$type" => "app.bsky.feed.post",
        "langs" => ["en"],
        "createdAt" => "2026-08-07T11:15:44.513Z"
      }
    end

    it "should convert CID links and byte strings in section data" do
      root = archive.section_with_cid(archive.roots.first)

      root["did"].should == "did:plc:rnpkyqnmsw4ipey6eotbdnnf"
      root["rev"].should == "3msigk4u5hz2z"
      root["version"].should == 3
      root["prev"].should be_nil
      root["data"].should == { "$link" => Oxygene::CID.from_json(data_cid) }
      root["sig"].keys.should == ["$bytes"]
      Base64.decode64(root["sig"]["$bytes"]).bytesize.should == 64
    end
  end
end
