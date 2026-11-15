# frozen_string_literal: true

require 'json'

describe Oxygene::CBOR do
  def cbor(hex)
    [hex.delete(' ')].pack('H*')
  end

  let(:drisl_cid) { cbor('00 01 71 12 20') + ("\x11".b * 32) }
  let(:raw_cid) { cbor('00 01 55 12 20') + ("\x22".b * 32) }
  let(:link) { cbor('d8 2a 58 25') + drisl_cid }

  let(:record) do
    # { "a": [link, { "b": h'fbff', "t": "é" }] }
    cbor('a1 61 61 82') + link + cbor('a2 61 62 42 fb ff 61 74 62 c3 a9')
  end

  describe ".decode" do
    it "should decode nested links, byte strings, and UTF-8 text" do
      decoded_link, values = Oxygene::CBOR.decode(record).fetch('a')

      decoded_link.should be_a(Oxygene::CID)
      decoded_link.cbor_form.should == drisl_cid

      values.fetch('b').should == "\xfb\xff".b
      values.fetch('b').encoding.should == Encoding::BINARY

      values.fetch('t').should == 'é'
      values.fetch('t').encoding.should == Encoding::UTF_8
    end

    context 'with json: true' do
      it "should wrap nested links and byte strings in JSON mode" do
        decoded = Oxygene::CBOR.decode(record, json: true)
        wrapped_link, values = decoded.fetch('a')
        cid = wrapped_link.fetch('$link')

        cid.should be_a(Oxygene::CID)
        cid.cbor_form.should == drisl_cid
        values.should == { 'b' => { '$bytes' => '+/8' }, 't' => 'é' }

        JSON.parse(JSON.generate(decoded)).fetch('a').first.should == { '$link' => cid.json_form }
      end      
    end

    it "should decode a raw-codec CID" do
      cid = Oxygene::CBOR.decode(cbor('d8 2a 58 25') + raw_cid)

      cid.should be_a(Oxygene::CID)
      cid.cbor_form.should == raw_cid
    end

    it "should decode positive and negative 64-bit integers" do
      Oxygene::CBOR.decode(cbor('1b 7fffffffffffffff')).should == (2**63 - 1)
      Oxygene::CBOR.decode(cbor('3b 7fffffffffffffff')).should == -(2**63)
    end

    it "should decode integers at each argument width boundary" do
      data = cbor('85 17 18 18 19 0100 1a 00010000 1b 0000000100000000')

      Oxygene::CBOR.decode(data).should == [23, 24, 256, 65_536, 4_294_967_296]
    end

    it "should decode supported simple values and empty containers" do
      Oxygene::CBOR.decode(cbor('85 f4 f5 f6 80 a0')).should == [false, true, nil, [], {}]
    end

    it "should reject empty input and any trailing bytes" do
      ['', '00 01', '00 ff'].each do |hex|
        expect { Oxygene::CBOR.decode(cbor(hex)) }.to raise_error(Oxygene::DecodeError)
      end
    end

    it "should reject a tag 42 payload that is a text string or an integer" do
      ['d8 2a 61 61', 'd8 2a 00'].each do |hex|
        expect { Oxygene::CBOR.decode(cbor(hex)) }.to raise_error(Oxygene::DecodeError)
      end
    end

    it "should reject a truncated CID" do
      expect { Oxygene::CBOR.decode(link.byteslice(0...-1)) }.to raise_error(Oxygene::DecodeError)
    end

    it "should reject a CID with an unsupported codec" do
      data = cbor('d8 2a 58 25 00 01 72 12 20') + ("\x11".b * 32)

      expect { Oxygene::CBOR.decode(data) }.to raise_error(Oxygene::UnsupportedError)
    end

    it "should reject an unknown tag" do
      expect { Oxygene::CBOR.decode(cbor('d8 64 00')) }.to raise_error(Oxygene::UnsupportedError)
    end
  end

  describe ".decode_sequence" do
    it "should decode empty, single-item, and longer sequences" do
      Oxygene::CBOR.decode_sequence(''.b).should == []

      Oxygene::CBOR.decode_sequence(cbor('01')).should == [1]

      Oxygene::CBOR.decode_sequence(cbor('01 63 74776f a1 65 7468726565 03')).should == [1, 'two', { 'three' => 3 }]
    end

    it "should leave a firehose payload's block bytes in binary by default" do
      # { "op": 1 }, { "blocks": h'00ff' }
      frame = cbor('a1 62 6f70 01 a1 66 626c6f636b73 42 00ff')
      header, payload = Oxygene::CBOR.decode_sequence(frame)

      header.should == { 'op' => 1 }
      payload.should == { 'blocks' => "\x00\xff".b }
      payload.fetch('blocks').encoding.should == Encoding::BINARY
    end

    context 'with json: true' do
      it "should apply JSON mode to every item in the sequence" do
        bytes, wrapped_link = Oxygene::CBOR.decode_sequence(cbor('41 fb') + link, json: true)

        bytes.should == { '$bytes' => '+w' }
        wrapped_link.fetch('$link').cbor_form.should == drisl_cid
      end      
    end

    it "should reject a sequence with an incomplete final item" do
      expect { Oxygene::CBOR.decode_sequence(cbor('01 82 02')) }.to raise_error(Oxygene::DecodeError)
    end
  end

  unless $native_cbor
    context "with the pure Ruby decoder" do
      it "should accept map keys sorted by UTF-8 byte length and then by bytes" do
        keys = Oxygene::CBOR.decode(cbor('a3 61 7a 00 62 6161 01 62 c3a9 02')).keys

        keys.should == ['z', 'aa', 'é']
      end

      it "should accept at most 128 nested containers" do
        nested = cbor('81') * 127 + cbor('80')

        expect { Oxygene::CBOR.decode(nested) }.not_to raise_error
        expect { Oxygene::CBOR.decode(cbor('81') + nested) }.to raise_error(Oxygene::DecodeError)
      end

      it "should reject a map beyond the nesting limit" do
        nested = cbor('81') * 128 + cbor('a0')

        expect { Oxygene::CBOR.decode(nested) }.to raise_error(Oxygene::DecodeError)
      end

      it "should reject a non-minimal tag number or CID byte-string length" do
        expect { Oxygene::CBOR.decode(cbor('d9 002a 58 25') + drisl_cid) }.to raise_error(Oxygene::DecodeError)
        expect { Oxygene::CBOR.decode(cbor('d8 2a 59 0025') + drisl_cid) }.to raise_error(Oxygene::DecodeError)
      end

      {
        'a non-minimal integer' => '18 17',
        'a non-minimal byte-string length' => '58 01 ff',
        'a non-minimal text-string length' => '78 01 61',
        'a non-minimal array length' => '98 01 00',
        'a non-minimal map length' => 'b8 01 61 61 00',
        'an indefinite-length byte string' => '5f 41 ff ff',
        'an indefinite-length text string' => '7f 61 61 ff',
        'an indefinite-length array' => '9f 00 ff',
        'an indefinite-length map' => 'bf 61 61 00 ff',
        'an integer above the signed 64-bit range' => '1b 8000000000000000',
        'an integer below the signed 64-bit range' => '3b 8000000000000000',
        'a half-precision float' => 'f9 3e00',
        'a single-precision float' => 'fa 3fc00000',
        'a double-precision float' => 'fb 3ff8000000000000',
        'the undefined simple value' => 'f7',
        'a reserved argument' => '1c',
        'invalid UTF-8 in a text value' => '62 c080',
        'invalid UTF-8 in a one-byte key' => 'a1 61 80 00',
        'invalid UTF-8 in a longer key' => 'a1 62 c080 00',
        'a byte-string map key' => 'a1 41 61 00',
        'an array map key' => 'a1 80 00',
        'duplicate map keys' => 'a2 61 61 01 61 61 02',
        'same-length map keys out of order' => 'a2 61 62 00 61 61 00',
        'different-length map keys out of order' => 'a2 62 c3a9 00 61 7a 00',
        'a truncated wide argument' => '1a 010203',
        'a missing one-byte text-string length' => '78',
        'a truncated text-string payload' => '62 61',
        'a truncated byte-string payload' => '42 ff',
        'a missing map key header' => 'a1',
        'a truncated short map key' => 'a1 63 61',
        'an oversized map-key length in a short input' => 'a1 7b ffffffffffffffff'
      }.each do |description, hex|
        it "should reject #{description}" do
          expect { Oxygene::CBOR.decode(cbor(hex)) }.to raise_error(Oxygene::DecodeError)
        end
      end
    end
  end
end
