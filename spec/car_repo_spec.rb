# frozen_string_literal: true

describe Oxygene::CARRepo do
  fixture_path = File.expand_path("fixtures/bsky_repo.car", __dir__)
  fixture_data = File.binread(fixture_path)

  let(:repo) { Oxygene::CARRepo.new(fixture_data) }

  describe ".new" do
    it "should reject an archive without a root commit" do
      header = CBOR.encode({ "version" => 1, "roots" => [] })
      archive_data = [header.bytesize].pack("C") + header

      expect { Oxygene::CARRepo.new(archive_data) }.to raise_error(
        Oxygene::DecodeError, "CAR repository has no root commit"
      )
    end
  end

  describe "#walk_all_nodes" do
    it "should walk all records in the repository" do
      keys = []
      cid_map = {}

      repo.walk_all_nodes do |key, cid|
        keys << key
        cid_map[key] = cid
      end

      keys.length.should == 10_640

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
          'app.bsky.feed.like/3jt6wh3ckcc2y',
          'app.bsky.feed.like/3jt6wh4b3tv2z',
          'app.bsky.feed.generator/with-friends',
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
          'app.bsky.feed.like/3jt6wh3ckcc2y',
          'app.bsky.feed.like/3jt6wh4b3tv2z',
          'app.bsky.feed.generator/with-friends',
        ]
      end
    end

    context "when the root commit is missing from the archive" do
      it "should raise a decode error" do
        header_size = fixture_data.getbyte(0) + 1
        incomplete_repo = Oxygene::CARRepo.new(fixture_data.byteslice(0, header_size))

        expect { incomplete_repo.walk_all_nodes {} }.to raise_error(
          Oxygene::DecodeError, /Root commit not found in the archive:/
        )
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
