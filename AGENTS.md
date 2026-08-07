* Ruby versions:
  - for any testing, use the Ruby 3.4 configured in `asdf` instead of the ancient system Ruby 2.6
  - since Ruby 3.2 you don't need to require 'set', it's a built-in class

* unit tests:
  - don't add automated tests to the repo while adding/changing library code unless specifically asked, or when changing the code breaks some existing tests and they need to be fixed
  - use the classic RSpec `foo.should be_...` matcher style instead of `expect()`, except for calling matchers on blocks as in `expect { ... }.to(not) raise_error...`
  - use the classic `it "should do this"` naming for test cases instead of `it "does this"`
  - use raw `describe` instead of `RSpec.describe`
