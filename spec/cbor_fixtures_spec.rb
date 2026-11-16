# frozen_string_literal: true

require 'json'

describe Oxygene::CBOR do
  context "with the DASL Testing fixtures" do
    fixture_paths = Dir[File.expand_path('fixtures/dasl-testing/*.json', __dir__)]
    included_tags = %w[basic dag-cbor dasl-cid]

    not_valid_atproto = {
      'largest CBOR integer, 2^64-1' => 'outside the signed 64-bit integer range',
      'smallest CBOR integer, -(2^64)' => 'outside the signed 64-bit integer range',
      'Big DASL CID' => 'uses BLAKE3'
    }

    fixture_paths.each do |path|
      suite = File.basename(path, '.json')

      JSON.parse(File.read(path)).each do |item|
        next if (item.fetch('tags') & included_tags).empty?

        name = item.fetch('name')

        error_reason = if ['invalid_in', 'invalid_out'].include?(item.fetch('type'))
          item.fetch('desc')
        elsif suite == 'floats'
          'ATProto forbids floats'
        else
          not_valid_atproto[name]
        end

        if Oxygene::CBOR.native_module?
          next unless %w[cid concat tags].include?(suite)
          next if name == 'long CID tag'

          if error_reason
            it "should reject '#{name}' from #{suite}.json (#{error_reason})" do
              binary = [item.fetch('data')].pack('H*')

              expect { Oxygene::CBOR.decode(binary, json: true) }.to raise_error(Oxygene::Error)
            end
          else
            it "should accept '#{name}' from #{suite}.json" do
              binary = [item.fetch('data')].pack('H*')

              expect { Oxygene::CBOR.decode(binary, json: true) }.not_to raise_error
            end
          end
        else
          if error_reason
            it "should reject '#{name}' from #{suite}.json (#{error_reason})" do
              binary = [item.fetch('data')].pack('H*')

              expect { Oxygene::CBOR.decode(binary) }.to raise_error(Oxygene::Error)
            end
          else
            it "should accept '#{name}' from #{suite}.json" do
              binary = [item.fetch('data')].pack('H*')

              expect { Oxygene::CBOR.decode(binary) }.not_to raise_error
            end
          end
        end
      end
    end
  end

  context "with the Common Lisp ATProto DRISL fixtures" do
    fixture_paths = Dir[File.expand_path('fixtures/cl-atproto-drisl/*/*.dag-cbor', __dir__)]

    unsupported_cids = %w[
      cid-bafkqabiaaebagba
      cid-bagcqcera73rupyla6bauseyk75rslfys3st25spm75ykhvgusqvv2zfqtucq
      cid-bagyacvradn6dsgl6sw2jwoh7s3d37hq5wsu7g22wtdwnmaaaaaaaaaaaaaaa
      cid-bagyqcvraypzcitp3hsbtyyxhfyc3p7i3226lullm2rkzqsqqlhnxus7tqnea
      cid-bahaacvrabdhd3fzrwaambazyivoiustl2bo2c3rgweo2ug4rogcoz2apaqaa
      cid-bahaacvrasyauh7rmlyrmyc7qzvktjv7x6q2h6ttvei6qon43tl3riaaaaaaa
      garbage-00
      garbage-01
    ]

    out_of_range_integers = %w[int--11959030306112471732 int-11959030306112471731 int-18446744073709551615]

    def normalize_bytes(value)
      case value
      when Hash
        if value.keys == ['$bytes']
          # The fixtures may include optional Base64 padding. Oxygene omits it.
          { '$bytes' => value.fetch('$bytes').gsub(/=+\z/, '') }
        else
          value.transform_values { |item| normalize_bytes(item) }
        end
      when Array
        value.map { |item| normalize_bytes(item) }
      else
        value
      end
    end

    fixture_paths.each do |path|
      dir = File.dirname(path)
      name = File.basename(dir)

      out_of_range = out_of_range_integers.include?(name)

      if out_of_range
        next if Oxygene::CBOR.native_module?

        it "should reject #{name} (outside the signed 64-bit integer range)" do
          expect { Oxygene::CBOR.decode(File.binread(path), json: true) }.to raise_error(Oxygene::Error)
        end
      elsif unsupported_cids.include?(name)
        it "should reject #{name} (contains an unsupported CID)" do
          expect { Oxygene::CBOR.decode(File.binread(path), json: true) }.to raise_error(Oxygene::Error)
        end
      else
        it "should decode #{name} to the expected JSON" do
          json_path = Dir[File.join(dir, '*.dag-json')].fetch(0)
          expected = normalize_bytes(JSON.parse(File.read(json_path)))

          decoded = Oxygene::CBOR.decode(File.binread(path), json: true)

          JSON.parse(JSON.generate(decoded)).should == expected
        end
      end
    end
  end
end
