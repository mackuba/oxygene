# frozen_string_literal: true

require_relative 'car_archive'

module Oxygene
  class CARRepo < CARArchive
    def walk_all_nodes(starting_node_cid = nil, &block)
      if starting_node_cid.nil?
        root_section = section_with_cid(self.roots[0], use_map: true, return_body: false).decoded_body
        cid = root_section['data'].value
        return walk_all_nodes(cid, &block)
      elsif starting_node_cid.is_a?(CID)
        starting_node_cid = starting_node_cid.cbor_form
      end

      data = section_with_cid(starting_node_cid, use_map: true, return_body: false).decoded_body

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
