# frozen_string_literal: true

require_relative 'car_archive'
require_relative 'errors'

module Oxygene

  #
  # A CAR archive containing an account's ATProto repository, as returned by the
  # `com.atproto.sync.getRepo` PDS endpoint.
  #
  # Oxygene currently supports repositories in the v3 format version.
  #
  # Related specifications:
  # - [ATProto repository](https://atproto.com/specs/repository)
  #

  class CARRepo < CARArchive

    # Returns the CAR archive section containing the repository's root commit.
    # @return [CARSection] section identified by the first CAR root CID
    attr_reader :commit_section

    # Creates an ATProto repository reader from an in-memory CAR file.
    #
    # @param data [String] CAR archive file as a binary string
    # @raise [DecodeError] if the CAR header has missing or invalid fields, the root commit is missing, or a section has invalid data
    # @raise [UnsupportedError] if the archive, section CID or repository is in an unsupported version
    #
    def initialize(data)
      super

      raise DecodeError, "CAR repository has no root commit" if roots.empty?

      @commit_section = section_with_cid(roots.first, use_map: true, return_body: false)
      raise DecodeError, "Root commit not found in the archive: #{roots.first.inspect}" if @commit_section.nil?

      commit_body = @commit_section.decoded_body
      raise DecodeError, "Commit object should be a hash" unless commit_body.is_a?(Hash)

      repo_version = commit_body['version']
      raise UnsupportedError, "Unexpected repository version: #{repo_version.inspect}" unless repo_version == 3
    end

    # Returns the repository commit data.
    #
    # The commit is decoded from the body of the {#commit_section}. The data is
    # returned in the ATProto JSON representation – CID links and binary strings
    # are represented using `$link` and `$bytes` objects respectively. Use
    # {#commit_section} to access the original CBOR bytes or decoded CBOR values
    # without conversion.
    #
    # See the [ATProto repository spec](https://atproto.com/specs/repository#commit-objects)
    # for what fields the commit object is expected to contain.
    #
    # @return [Hash] root commit data

    def commit
      commit_section.json_body
    end

    # Walks through the repository MST tree, running the passed block for each record
    # in the repo in alphabetical key order.
    #
    # Records are stored in the Merkle Search Tree structure in nodes with assigned keys,
    # where each key is a record path (NSID collection + rkey, e.g.
    # `app.bsky.feed.post/3juhznhw65225`). The iterator returns all records one by one
    # sorted alphabetically, so the list is sorted by collection first and then by rkey
    # within a collection. The callback is passed the path key and the {CID} of the section
    # which contains the actual record data, The CID can be used to extract the data
    # through a call to {#section_with_cid} (you almost certainly want to pass
    # `use_map: true`).
    #
    # Normally you can skip the `starting_node_cid` parameter, in which case the tree
    # traversal begins at the repository root referenced by the CAR header and covers the
    # entire tree. If a starting CID is passed, the traversal will start from a given node
    # covering only a subtree.
    #
    # @param starting_node_cid [CID, String, nil] CID of the tree node to start from, or `nil` to start at the repository root
    #
    # @yield [key, cid] path key of a given record and the CID of its value block
    # @yieldparam key [String] record path key, i.e. collection + / + rkey
    # @yieldparam cid [CID] content identifier of the section containing the record value
    # @raise [DecodeError] if a requested section is missing, a section is truncated or malformed, or a CID is invalid
    # @raise [UnsupportedError] if a section uses an unsupported CID encoding

    def walk_all_nodes(starting_node_cid = nil, &block)
      if starting_node_cid.nil?
        commit = commit_section.decoded_body
        tree_top_cid = commit['data'].value
        return walk_all_nodes(tree_top_cid, &block)
      end

      data = section_with_cid(starting_node_cid, use_map: true, return_body: false)&.decoded_body
      raise DecodeError, "MST node not found in the archive: #{starting_node_cid.inspect}" if data.nil?

      if data['l']
        walk_all_nodes(data['l'].value, &block)
      end

      previous = nil

      (data['e'] || []).each do |e|
        if previous
          key = previous[0...e['p']]
          key << e['k']
        else
          key = e['k']
        end

        previous = key

        block.call(key, CID.from_cbor_tag(e['v']))

        if e['t']
          walk_all_nodes(e['t'].value, &block)
        end
      end
    end
  end
end
