# frozen_string_literal: true

describe Oxygene::CARArchive do
  fixture_path = File.expand_path("fixtures/friday.car", __dir__)
  fixture_data = File.binread(fixture_path)

  root_cid = "bafyreiaplw3orif2rpycru2nqgtq4g6o3y32veldq2uboq6owkehn43gzi"
  data_cid = "bafyreibkjye2pyd4lo3geoy7prk7k63zohttpkzgvvtbm2zbwgdolorzse"
  record_cid = "bafyreif2ezn3unua3qk7j6cc2zamkjb2zxkyont7ipmbrd3pzzyp3wbaki"
  header_size = fixture_data.getbyte(0) + 1
  first_section_cid_offset = fixture_data.index("\x01\x71\x12\x20".b, header_size)

  def build_archive_header(metadata)
    header = CBOR.encode(metadata)
    [header.bytesize].pack("C") + header
  end

  let(:archive) { Oxygene::CARArchive.new(fixture_data) }

  def parsed_sections
    archive.parsed_sections
  end

  describe ".new" do
    it "should reject a zero-length header" do
      expect { Oxygene::CARArchive.new("\x00".b) }.to raise_error(Oxygene::DecodeError, "Header length cannot be 0")
    end

    it "should reject a truncated header" do
      truncated_data = fixture_data.byteslice(0, 20)

      expect { Oxygene::CARArchive.new(truncated_data) }.to raise_error(Oxygene::DecodeError, /Header too short/)
    end

    it "should reject an unsupported CAR version" do
      unsupported_data = fixture_data.sub("gversion\x01".b, "gversion\x02".b)

      expect { Oxygene::CARArchive.new(unsupported_data) }.to raise_error(Oxygene::UnsupportedError, "Unexpected CAR version: 2")
    end

    it "should reject a metadata object that is not a hash" do
      invalid_data = build_archive_header([])

      expect { Oxygene::CARArchive.new(invalid_data) }.to raise_error(Oxygene::DecodeError, "Metadata object should be a hash")
    end

    it "should reject a metadata object without a roots array" do
      invalid_data = build_archive_header({ "version" => 1 })

      expect { Oxygene::CARArchive.new(invalid_data) }.to raise_error(Oxygene::DecodeError, "Missing 'roots' field")
    end

    it "should reject a roots field that is not an array" do
      invalid_data = build_archive_header({ "version" => 1, "roots" => "invalid" })

      expect { Oxygene::CARArchive.new(invalid_data) }.to raise_error(Oxygene::DecodeError, /Invalid 'roots' field:/)
    end

    it "should reject a value in the roots array that is not a CBOR CID tag" do
      invalid_data = build_archive_header({ "version" => 1, "roots" => ["invalid"] })

      expect { Oxygene::CARArchive.new(invalid_data) }.to raise_error(Oxygene::DecodeError, /Unexpected value in the roots array:/)
    end

    it "should reject a root with a CBOR tag other than 42" do
      root_data = Oxygene::CID.from_json(root_cid).cbor_form
      invalid_root = CBOR::Tagged.new(41, root_data)
      invalid_data = build_archive_header({ "version" => 1, "roots" => [invalid_root] })

      expect { Oxygene::CARArchive.new(invalid_data) }.to raise_error(Oxygene::DecodeError, /Unexpected value in the roots array/)
    end
  end

  describe "lazy section loading" do
    it "should not load sections until requested" do
      parsed_sections.should be_empty
    end

    it "should load only up to a section requested by CID" do
      archive.section_with_cid(Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4"))
      parsed_sections.length.should == 3

      archive.section_with_cid(Oxygene::CID.from_json(record_cid))
      parsed_sections.length.should == 10
      parsed_sections.last.cid.to_s.should == record_cid
    end

    it "should not load more sections if the requested section is already loaded" do
      archive.section_with_cid(Oxygene::CID.from_json(record_cid))
      parsed_sections.length.should == 10

      archive.section_with_cid(Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4"))
      parsed_sections.length.should == 10
    end

    it "should load every section when a non-existing section is requested" do
      archive.section_with_cid(Oxygene::CID.from_json("bafyreihqweqweqweqweg27d53547wrc4zwcohkah76hq55nohacsdacfm4"))

      parsed_sections.length.should == 11
    end

    it "should load every section when .sections is called" do
      archive.sections

      parsed_sections.length.should == 11
      parsed_sections.last.cid.to_s.should == root_cid
    end
  end

  describe "#parsed_sections" do
    it "should return a frozen snapshot without parsing more sections" do
      snapshot = parsed_sections

      snapshot.should be_empty
      snapshot.should be_frozen
      expect { snapshot << Object.new }.to raise_error(FrozenError)

      archive.section_with_cid(Oxygene::CID.from_json(record_cid))

      snapshot.should be_empty
      parsed_sections.length.should == 10
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

    it "should free the data buffer for GC cleanup" do
      archive.instance_variable_get(:@buffer).should_not be_nil

      sections = archive.sections

      archive.instance_variable_get(:@buffer).should be_nil
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

    it "should reject a non-canonically encoded CID prefix" do
      cid_body = "\x00".b * 32
      dag_cbor_codec = "\x71".b
      sha256_multihash = "\x12\x20".b + cid_body
      canonical_cid = "\x00\x01".b + dag_cbor_codec + sha256_multihash

      header = CBOR.encode({
        "roots" => [CBOR::Tagged.new(42, canonical_cid)],
        "version" => 1
      })

      # 81 00 is a non-canonical but technically valid two-byte varint encoding of the CID version 1
      weird_version_tag = "\x81\x00".b
      section = weird_version_tag + dag_cbor_codec + sha256_multihash + CBOR.encode({})

      archive_data = [header.bytesize].pack("C") + header + [section.bytesize].pack("C") + section
      archive = Oxygene::CARArchive.new(archive_data)

      expect { archive.sections }.to raise_error(Oxygene::UnsupportedError, "Non-canonical CID prefix")
    end
  end

  describe "#section_with_cid" do
    it "should find a section with given CID and return its body" do
      cid = Oxygene::CID.from_json(record_cid)

      body = archive.section_with_cid(cid)
      body.should be_a(Hash)
    end

    context "with return_body: true" do
      it "should find a section with given CID and return its body" do
        cid = Oxygene::CID.from_json(record_cid)

        body = archive.section_with_cid(cid, return_body: true)
        body.should be_a(Hash)
      end

      it "should return the body converted to ATProto JSON representation" do
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

    context "with return_body: false" do
      it "should find a section with given CID and return the section object" do
        cid = Oxygene::CID.from_json(record_cid)

        section = archive.section_with_cid(cid, return_body: false)
        section.should be_a(Oxygene::CARSection)
        section.cid.should == cid
      end
    end

    it "should also accept CID binary data as a string" do
      cid = Oxygene::CID.from_json(record_cid)

      section = archive.section_with_cid(cid.cbor_form, return_body: false)
      section.should_not be_nil
      section.cid.should == cid

      section2 = archive.section_with_cid(cid.cbor_form, return_body: false)
      section2.should equal(section)
    end

    context "when the CID is not in the archive" do
      let(:missing_cid) { Oxygene::CID.from_json("bafyreihsl77homddrramzhzdrgfneatthwnlz47ikzy4mezxz7kxndmjsm") }

      it "should return nil" do
        archive.section_with_cid(missing_cid).should be_nil
      end

      it "should free the data buffer for GC cleanup" do
        archive.instance_variable_get(:@buffer).should_not be_nil

        archive.section_with_cid(missing_cid)

        archive.instance_variable_get(:@buffer).should be_nil
      end
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

    context "with use_map: true" do
      let(:early_cid) { Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4") }
      let(:section_map) { archive.instance_variable_get(:@section_map) }

      def map_needs_update
        archive.instance_variable_get(:@map_needs_update)
      end

      it "should add lazily parsed sections to the map" do
        section = archive.section_with_cid(early_cid, use_map: true, return_body: false)
        section.should_not be_nil

        parsed_sections.length.should == 3
        section_map.values.should == parsed_sections
        section_map[early_cid.cbor_form].should equal(section)
      end

      context "if some sections were earlier parsed without being added to map" do
        it "should update the map on next call with use_map" do
          # loading some sections with use_map
          s = archive.section_with_cid(early_cid, use_map: true)
          s.should_not be_nil

          # loading some more without use_map
          record_section = archive.section_with_cid(Oxygene::CID.from_json(record_cid), return_body: false)
          record_section.should_not be_nil

          parsed_sections.length.should == 10
          section_map.length.should == 3
          map_needs_update.should == true

          # map should be updated and used for lookup
          section = archive.section_with_cid(record_section.cid, use_map: true, return_body: false)
          section.should equal(record_section)

          section_map.length.should == 10
          section_map[record_section.cid.cbor_form].should equal(record_section)
          map_needs_update.should == false
        end
      end

      context "after a call to #sections loads all sections" do
        it "should update the map on next call with use_map" do
          # loading some sections with use_map
          s = archive.section_with_cid(early_cid, use_map: true)
          s.should_not be_nil

          # archive.sections loads the rest, without map
          archive.sections

          parsed_sections.length.should == 11
          section_map.length.should == 3
          map_needs_update.should == true

          # map should be updated and used for lookup
          root = archive.section_with_cid(archive.roots.first, use_map: true, return_body: false)
          root.should_not be_nil

          section_map.length.should == 11
          section_map[archive.roots.first.cbor_form].should equal(root)
          map_needs_update.should == false
        end

        it "should not mark the map as dirty if sections were already all loaded" do
          # load up to last section
          s = archive.section_with_cid(Oxygene::CID.from_json(root_cid), use_map: true)
          s.should_not be_nil

          # archive.sections finds eof
          archive.sections

          map_needs_update.should == false
        end

        it "should not mark the map as dirty on second call to sections" do
          # loading some sections with use_map
          s = archive.section_with_cid(early_cid, use_map: true)
          s.should_not be_nil

          # archive.sections loads the rest, without map
          archive.sections

          # force map refresh
          s = archive.section_with_cid(early_cid, use_map: true)
          s.should_not be_nil

          archive.sections
          map_needs_update.should == false
        end
      end

      it "should also accept CID binary data as a string" do
        cid = Oxygene::CID.from_json(record_cid)

        section = archive.section_with_cid(cid.cbor_form, use_map: true, return_body: false)
        section.should_not be_nil
        section.cid.should == cid

        section2 = archive.section_with_cid(cid.cbor_form, use_map: true, return_body: false)
        section2.should equal(section)
      end
    end

    context "with use_map: false" do
      let(:early_cid) { Oxygene::CID.from_json("bafyreihglybf3ix6ctig27d53547wrc4zwcohkah76hq55nohacsdacfm4") }
      let(:section_map) { archive.instance_variable_get(:@section_map) }

      it "should not add parsed sections to the map" do
        section = archive.section_with_cid(early_cid, use_map: false, return_body: false)
        section.should_not be_nil

        parsed_sections.length.should == 3
        section_map.length.should == 0
      end

      it "should not use the map for lookup" do
        section = archive.section_with_cid(early_cid, use_map: false, return_body: false)
        section.should_not be_nil

        record_section = archive.section_with_cid(Oxygene::CID.from_json(record_cid), use_map: false, return_body: false)
        record_section.should_not be_nil

        section2 = archive.section_with_cid(early_cid, use_map: false, return_body: false)
        section2.should equal(section)

        parsed_sections.length.should == 10
        section_map.length.should == 0
      end
    end
  end

  describe ".make_bytes" do
    it "should convert a binary string to a JSON representation with Base64 encoding" do
      binary = "base64".b

      Oxygene::CARArchive.make_bytes(binary).should == { "$bytes" => "YmFzZTY0" }
    end

    it "should include no '=' padding" do
      binary = "\xEB\e8Z\xE1\xDC\x8F\xE1\xBA\xD3\xB9\xF4\xF7P\x89\x01".b

      Oxygene::CARArchive.make_bytes(binary).should == { "$bytes" => "6xs4WuHcj+G607n091CJAQ" }
    end

    it "should remove intermediate newlines from longer Base64 data" do
      data = "a".b * 64
      base64_string = Base64.encode64(data)
      base64_string.chomp.should include("\n")

      output = Oxygene::CARArchive.make_bytes(data)
      output.should == { '$bytes' => base64_string.gsub(/\n/, '').gsub(/=+$/, '') }
    end
  end
end
