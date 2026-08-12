# frozen_string_literal: true

describe Oxygene::CARRepo do
  fixture_path = File.expand_path("fixtures/bsky_repo.car", __dir__)
  fixture_data = File.binread(fixture_path)
  root_cid = Oxygene::CARArchive.new(fixture_data).roots.first

  def build_repo(root_cid, commit_body)
    header = CBOR.encode({ "version" => 1, "roots" => [CBOR::Tagged.new(42, root_cid.cbor_form)] })
    section = root_cid.raw_data + CBOR.encode(commit_body)
    [header.bytesize].pack("C") + header + [section.bytesize].pack("C") + section
  end

  let(:repo) { Oxygene::CARRepo.new(fixture_data) }

  describe ".new" do
    it "should reject an archive without a root commit" do
      header = CBOR.encode({ "version" => 1, "roots" => [] })
      archive_data = [header.bytesize].pack("C") + header

      expect { Oxygene::CARRepo.new(archive_data) }.to raise_error(
        Oxygene::DecodeError, "CAR repository has no root commit"
      )
    end

    it "should reject an archive whose root commit is missing" do
      header_size = fixture_data.getbyte(0) + 1
      data = fixture_data.byteslice(0, header_size)

      expect { Oxygene::CARRepo.new(data) }.to raise_error(
        Oxygene::DecodeError, /Root commit not found in the archive:/
      )
    end

    it "should reject a root commit that is not a hash" do
      invalid_data = build_repo(root_cid, [])

      expect { Oxygene::CARRepo.new(invalid_data) }.to raise_error(
        Oxygene::DecodeError, "Commit object should be a hash"
      )
    end

    it "should reject repos in an older version" do
      version_2_data = build_repo(root_cid, { "version" => 2 })

      expect { Oxygene::CARRepo.new(version_2_data) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected repository version: 2"
      )
    end

    it "should reject repos in an unknown newer version" do
      version_4_data = build_repo(root_cid, { "version" => 4 })

      expect { Oxygene::CARRepo.new(version_4_data) }.to raise_error(
        Oxygene::UnsupportedError, "Unexpected repository version: 4"
      )
    end
  end

  describe "#commit_section" do
    it "should return the section identified by the first root CID" do
      section = repo.commit_section

      section.should be_a(Oxygene::CARSection)
      section.cid.should == repo.roots.first
      section.decoded_body["version"].should == 3
      section.should equal(repo.commit_section)
      repo.parsed_sections.should_not be_empty
    end
  end

  describe "#commit" do
    it "should return the root commit in ATProto JSON representation" do
      commit = repo.commit

      commit.should equal(repo.commit_section.json_body)
      commit["did"].should == "did:plc:z72i7hdynmk6r22z27h6tvur"
      commit["version"].should == 3
      commit["rev"].should == "3msipndrkvm2h"
      commit["prev"].should be_nil
      commit["data"]["$link"].should be_a(Oxygene::CID)
      commit["sig"].keys.should == ["$bytes"]
    end
  end

  describe "#walk_all_nodes" do
    it "should walk all records in the repository in path order" do
      keys = []
      cid_map = {}

      repo.walk_all_nodes do |key, cid|
        keys << key
        cid_map[key] = cid
      end

      keys.length.should == 10_640
      keys.should == keys.sort

      cid_map["app.bsky.actor.profile/self"].to_s.should == "bafyreihmkky5jpvhacnmt2vwxzejm4exit677ao2z6mevdib7lqnyvizsq"
      cid_map["app.bsky.feed.like/3jt6wh4b3tv2z"].to_s.should == "bafyreibhlhpbwy5xv7ilkpbmw475nfaxgfidptul62ljl5uu4pnvbnd6oe"
      cid_map["chat.bsky.actor.declaration/self"].to_s.should == "bafyreid7e7r3m3aqk3qdooo2s4vm53rr37fdgc5e2f43fvaonhthi3rpfy"

      profile = repo.section_with_cid(cid_map["app.bsky.actor.profile/self"])
      profile["$type"].should == "app.bsky.actor.profile"
      profile["displayName"].should == "Bluesky"
    end

    context "given a starting CID" do
      it "should start from a section with that CID" do
        records = []
        starting_cid = Oxygene::CID.from_json("bafyreiajotznusc27wzjwm3li6okuvnmdstm6ymy6bk26jqauj4qidjqfe")

        repo.walk_all_nodes(starting_cid) do |key, cid|
          records << key
        end

        records.should == [
          'app.bsky.feed.generator/thevids',
          'app.bsky.feed.generator/whats-hot',
          'app.bsky.feed.generator/with-friends',
          'app.bsky.feed.like/3jt6wh3ckcc2y',
          'app.bsky.feed.like/3jt6wh4b3tv2z',
        ]
      end
    end

    context "given a starting CID as binary data string with 0 prefix" do
      it "should start from a section with that CID" do
        records = []
        starting_cid = Oxygene::CID.from_json("bafyreiajotznusc27wzjwm3li6okuvnmdstm6ymy6bk26jqauj4qidjqfe")

        repo.walk_all_nodes(starting_cid.cbor_form) do |key, cid|
          records << key
        end

        records.should == [
          'app.bsky.feed.generator/thevids',
          'app.bsky.feed.generator/whats-hot',
          'app.bsky.feed.generator/with-friends',
          'app.bsky.feed.like/3jt6wh3ckcc2y',
          'app.bsky.feed.like/3jt6wh4b3tv2z',
        ]
      end
    end

    context "given a starting CID that is missing from the archive" do
      it "should raise a decode error" do
        missing_cid = Oxygene::CID.new("\x01\x71\x12\x20".b + ("\x00".b * 32))

        expect { repo.walk_all_nodes(missing_cid) {} }.to raise_error(
          Oxygene::DecodeError, /MST node not found in the archive:/
        )
      end
    end
  end
end
