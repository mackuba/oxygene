## [0.1.0] - 2026-08-17

* added custom, much faster Base32 encoder/decoder, dropping `base32` gem dependency
* added `CARRepo` (subclass of `CARArchive`) for parsing and processing ATProto repo CAR archives:
  - use `#walk_all_nodes { |path, section_cid| ... }` to iterate over all records in the repo
  - use `#commit` or `#commit_section` to access repo commit data
* reorganized `CID` class:
  - it now stores only the initial JSON/binary form and avoids generating the other until requested
  - `#json_form` returns JSON string starting with 'b' (`to_s` is an alias)
  - `#cbor_form` returns the binary string starting with `\x00`
  - `#raw_data` returns the binary string *without* the CBOR `\x00` prefix
  - `#data` is an alias for `#raw_data` for backwards compatibility
  - both the input and output strings for JSON/binary form are frozen so they can't be modified from outside
  - added more data validations
* optimized section parsing & lookup in `CARArchive`:
  - it keeps an internal Hash of sections as { raw CID data => section }, but doesn't build it by default unless explicitly enabled
  - use `section_with_cid(cid, use_map: true)` to populate and use the lookup hashmap
  - either a `CID` object or its `#cbor_form` can be used for lookup
  - use `section_with_cid(cid, return_body: false)` to return a `CARSection` instead of its decoded body object directly; this will be the default behavior in a future version
  - various internal optimizations in the decoding code
  - added more data validations
  - added `#parsed_sections` helper
* changed the API of `CARSection`:
  - use `#json_body` to return the body with values recursively converted to use `$bytes` and `$link` where needed, as before
  - use `#decoded_body` to return the body only decoded from CBOR, but without the recursive conversion
  - `#body` is an alias for `#json_body` for now for backwards compatibility
* added unit tests & YARD docs

## [0.0.1] - 2026-08-05

- initial release - extracted `CID` and `CARArchive` from Skyfall
