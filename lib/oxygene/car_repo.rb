# frozen_string_literal: true

require_relative 'car_archive'

module Oxygene
  class CARRepo < CARArchive
    def initialize(data)
      super
      raise DecodeError, "CAR repository has no root commit" if roots.empty?
    end

    def walk_all_nodes(starting_node_cid = nil, &block)
      if starting_node_cid.nil?
        root_cid = roots.first
        root_section = section_with_cid(root_cid, use_map: true, return_body: false)&.decoded_body
        raise DecodeError, "Root commit not found in the archive: #{root_cid.inspect}" if root_section.nil?

        tree_top_cid = root_section['data'].value
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

        if e['t']
          walk_all_nodes(e['t'].value, &block)
        end

        block.call(key, CID.from_cbor_tag(e['v']))
      end
    end
  end
end
