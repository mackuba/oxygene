# frozen_string_literal: true

require_relative 'car_archive'

module Oxygene
  class CARRepo < CARArchive
    def walk_all_nodes(starting_node_cid = nil, &block)
      if starting_node_cid.nil?
        root_section = section_with_cid(self.roots[0])
        cid = root_section['data']['$link']
        return walk_all_nodes(cid, &block)
      end

      data = section_with_cid(starting_node_cid)

      if data['l']
        walk_all_nodes(data['l']['$link'], &block)
      end

      previous = nil

      (data['e'] || []).each do |e|
        key = Base64.decode64(e['k']['$bytes'])
        key = previous[0...e['p']] + key if previous
        previous = key

        if e['t']
          walk_all_nodes(e['t']['$link'], &block)
        end

        block.call(key, e['v']['$link'])
      end
    end
  end
end
