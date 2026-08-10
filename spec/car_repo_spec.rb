# frozen_string_literal: true

describe Oxygene::CARRepo do
  fixture_path = File.expand_path("fixtures/bsky_repo.car", __dir__)
  fixture_data = File.binread(fixture_path)

  let(:repo) { Oxygene::CARRepo.new(fixture_data) }

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
  end
end
