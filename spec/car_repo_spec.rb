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
  end
end
