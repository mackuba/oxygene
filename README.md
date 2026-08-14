# Oxygène

[![Gem Version](https://badge.fury.io/rb/oxygene.svg?icon=si%3Arubygems&icon_color=%23ff6251)](https://rubygems.org/gems/oxygene) [![YARD Docs](http://img.shields.io/badge/yard-docs-blue.svg)](https://rubydoc.info/gems/oxygene)

*(n) Gaz incolore, inodore et sans saveur qui compose 1/5ème de l'air atmosphérique.*

Various data decoding primitives for working with AT Protocol and the Atmosphere (including CAR, CID, CBOR).

> [!NOTE]
> Part of ATProto Ruby SDK: [ruby.sdk.blue](https://ruby.sdk.blue)


## Purpose

Oxygene includes various data decoding related primitives for working with AT Protocol repositories and firehose events. Provides at least partial implementations of standards such as [CAR](https://dasl.ing/car.html), [CID](https://dasl.ing/cid.html) and [Base 32](https://datatracker.ietf.org/doc/html/rfc4648#section-6).

This gem was extracted from [Skyfall](https://ruby.sdk.blue/skyfall/) and is mostly used there for the CBOR firehose decoding, but can also be used standalone for other ATProto data handling purposes, like decoding downloaded .car account repos.

The functionality currently includes:

- Base32 encoder/decoder
- CAR archive/repo parser
- CID wrapper
- and CBOR decoding (through the [cbor gem](https://github.com/cabo/cbor-ruby) for now)

The gem intentionally only includes support for the parts of these standards that are in use in ATProto, i.e. it doesn't handle all possible types of CIDs defined in the CID standard, only generates lowercase Base32, and so on.


## Installation

To use Oxygene, you need a reasonably new version of Ruby – it should run on Ruby 2.6 and above, although it's recommended to use a version that's still getting maintainance updates, i.e. currently 3.3+. A compatible version should be preinstalled on macOS Big Sur and above and on many Linux systems. Otherwise, you can install one using tools such as [RVM](https://rvm.io), [asdf](https://asdf-vm.com), [ruby-install](https://github.com/postmodern/ruby-install) or [ruby-build](https://github.com/rbenv/ruby-build), or `rpm` or `apt-get` on Linux (see more installation options on [ruby-lang.org](https://www.ruby-lang.org/en/downloads/)).

To install the gem, run the command:

    [sudo] gem install oxygene

Or add this to your app's `Gemfile`:

    gem 'oxygene', '~> 0.1'


## Usage

### CID

The `Oxygene::CID` class is an immutable object wrapper for CIDs (Content Identifiers), both in the binary/CBOR form and in the Base32-encoded JSON string form.

To create one from a CBOR tag object (`CBOR::Tagged`):

```rb
data = CBOR.decode(file)
cid = CID.from_cbor_tag(data['cid'])
```

To create one from a JSON representation:

```rb
cid = CID.from_json(event['cid'])
```

Both can be converted to the other representation:

```rb
cid.cbor_form
# => "\x00\x01q\x12 \x1A\x88\xF3Z\xFC..."

cid.raw_data
# same but without the 0 prefix
# => "\x01q\x12 \x1A\x88\xF3Z\xFC..."

cid.json_form
# => "bafyreia2rdzvv7fjlp..."
```


### CAR archives & repos

`Oxygene::CARArchive` is a wrapper for any CAR archive file, including e.g. in particular the kind that's contained in a `blocks` field in a `:commit` firehose message.

Create it passing it the binary data to decode:

```rb
car = Oxygene::CARArchive.new(message.blocks)
```

The decoder automatically parses the CAR file header containing the "root" CIDs, and makes those available as `#roots` array. The remaining sections are parsed lazily on demand.

You can parse and access the sections in the following ways:

- `#sections` returns an array of all sections in the archive, parsing them if needed
- `#parsed_sections` returns the sections parsed so far (initially `[]`)
- `section_with_cid(cid)` looks up a section by CID; if it was already parsed, it's returned immediately, otherwise remaining sections are parsed until a match is found (or the end of the file is reached)
    - **Note:** parsed sections are searched sequentially with `detect`. If you need to look up multiple sections repeatedly, use the second variant below.
- `section_with_cid(cid, use_map: true)` also looks up a section, but builds up and uses a `Hash` mapping CIDs to sections for quick lookup. For performance, creating this section index is opt-in, since it's not needed if only one section will be looked up.

Sections are represented as `Oxygene::CARSection` objects. A section has a `#cid`, and can return the body decoded from the binary CBOR data in two ways:

- `#decoded_body` decodes the CBOR into a Ruby `Hash`, but besides that leaves it as is; this means that e.g. CIDs are included as `CBOR::Tagged` objects
- `#json_body` additionally makes a recursive conversion of the object to an "ATProto JSON" as described in [ATProto Data Model](https://atproto.com/specs/data-model):
  - CIDs are converted to `{ "$link": "(base32 representation)" }`
  - binary strings are converted to `{ "$bytes": "(base64 encoded data)" }`

For backwards compatibility reasons, `#section_with_cid` currently returns the `#json_body` of a section directly, unless you pass `return_body: false` to return a `CARSection`. This will be changed in a future version.

For .car account repos, there is additionally a subclass of `CARArchive` called `CARRepo`, which lets you extract the repo's records from the archive's Merkle Search Tree.

Create a repo reader like this:

```rb
car = Oxygene::CARRepo.new(File.read(repo_path))
```

Then, iterate over the records using the `#walk_all_nodes` method. The records are indexed by the record "path", which is the NSID collection + the rkey joined with a `/`, and are returned in alphabetical order sorted by that path key (so by collection first and then by rkey within a collection):

```rb
car.walk_all_nodes do |key, cid|
  collection, rkey = key.split('/')
  if collection == 'app.bsky.feed.post'
    record = car.section_with_cid(cid, use_map: true)
    # ... save or print record w/ rkey
  end
end
```


### Base32

To encode a binary string into Base32:

```rb
string = Oxygene::Base32.encode(data)
```

To decode Base32 into binary data:

```rb
data = Oxygene::Base32.decode(string)
```

As an optimization, both methods also allow you to specify an offset in the input string from which to start reading, and a prefix to put at the beginning of the output buffer, so you can avoid some string allocations in a hot code path:

```rb
# skip the \x00 and add a starting 'b'
json_cid = Oxygene::Base32.encode(cbor_tag_cid, 1, 'b')

# skip the 'b' and add a starting \x00
binary_cid = Oxygene::Base32.decode(json_cid, 1, "\x00")
```


## Credits

Copyright © 2026 Kuba Suder ([@mackuba.eu](https://bsky.app/profile/did:plc:oio4hkxaop4ao4wz2pp3f4cr)).

The code is available under the terms of the [zlib license](https://choosealicense.com/licenses/zlib/) (permissive, similar to MIT).
