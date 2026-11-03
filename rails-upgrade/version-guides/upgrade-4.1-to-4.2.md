# Rails 4.1 → 4.2 Upgrade Guide

**Ruby Requirement:** 1.9.3+ (2.0+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs), the official Rails 4.2 upgrade guide, and the FastRuby.io upgrade blog post.**

---

## Overview

Rails 4.2 is a minor release that introduces async infrastructure and several extractions:
- **ActiveJob** framework + ActionMailer integration (`deliver_now` / `deliver_later`)
- **Web Console** in development (IRB on error pages, `<%= console %>` helper)
- **Adequate Record** query performance improvements (transparent)
- **Native foreign-key DSL** in migrations
- **Loofah-based HTML sanitizer** replaces html-scanner
- **Masked per-request CSRF tokens** (SSL attack mitigation)
- **`responders` gem** now external (`respond_with`, class-level `respond_to`)

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### ActionMailer `#deliver` / `#deliver!` Deprecated

**Pattern:** `MAILER_DELIVER`, `ACTIVE_JOB_ADAPTER`

**What Changed:**
`deliver` and `deliver!` are deprecated. The direct, bang-preserving replacements are `deliver_now` and `deliver_now!` (synchronous). `deliver_later` is a new async option that enqueues the mail via ActiveJob.

Calling a mailer method is also now lazy — the instance method runs when you call `deliver_now` / `deliver_later`, not when you call the class method. Code that relied on the old eager behavior for non-mailing work should move to class methods on the mailer.

**Detection Pattern:**
```ruby
UserMailer.welcome(user).deliver
NotificationMailer.daily_summary(user).deliver!
```

**Fix:**
```ruby
# BEFORE
UserMailer.welcome(user).deliver
NotificationMailer.daily_summary(user).deliver!

# AFTER — synchronous (direct drop-in replacements)
UserMailer.welcome(user).deliver_now
NotificationMailer.daily_summary(user).deliver_now!

# AFTER — enqueued via ActiveJob (preferred for non-urgent mail)
UserMailer.welcome(user).deliver_later
```

`deliver_later` requires an ActiveJob queue adapter (Sidekiq, Resque, etc.) for production use.

---

#### `respond_with` / Class-Level `respond_to` Extracted

**Pattern:** `RESPOND_WITH`, `CLASS_RESPOND_TO`

**What Changed:**
The `respond_with` helper and class-level `respond_to` declarations were extracted from Rails core into the [`responders`](https://github.com/heartcombo/responders) gem.

Action-level `respond_to do |format| ... end` blocks are NOT affected — they remain in Rails core.

**Detection Pattern:**
```ruby
class UsersController < ApplicationController
  respond_to :html, :json  # class-level — affected

  def show
    @user = User.find(params[:id])
    respond_with(@user)    # affected
  end

  def index
    @users = User.all
    respond_to do |format|  # NOT affected — stays in core
      format.html
      format.json { render json: @users }
    end
  end
end
```

**Fix:**
```ruby
# Gemfile
gem 'responders', '~> 2.0'
```

No code changes needed after adding the gem.

---

#### Passing AR Object to `.find` / `.exists?` Deprecated

**Pattern:** `FIND_WITH_OBJECT`

**What Changed:**
Passing an ActiveRecord object where an id is expected is deprecated — you must pass the id explicitly.

**Detection Pattern:**
```ruby
Comment.find(comment)
User.exists?(current_user)
```

**Fix:**
```ruby
# BEFORE
Comment.find(comment)
User.exists?(current_user)

# AFTER
Comment.find(comment.id)
User.exists?(current_user.id)
```

---

#### Transactional Callback Exception Suppression

**Pattern:** `TRANSACTIONAL_CALLBACKS`

**What Changed:**
Exceptions raised in `after_commit` or `after_rollback` callbacks are still silently rescued by default in 4.2, but Rails now emits a deprecation warning. Rails 5.0+ removes the suppression entirely and always raises.

**Detection Pattern:**
Missing configuration:
```ruby
# config/application.rb
config.active_record.raise_in_transactional_callbacks = true
```

**Fix:**
Opt into the Rails 5.0 behavior to surface callback bugs now:
```ruby
# config/application.rb
config.active_record.raise_in_transactional_callbacks = true
```

Without this flag, bugs in transactional callbacks become silent warnings that you'll have to address in the Rails 5.0 hop anyway.

---

#### `assert_tag` / `TagAssertions` Deprecated

**Pattern:** `ASSERT_TAG`

**What Changed:**
`assert_tag` and the `TagAssertions` module are deprecated. Use `assert_select` from `SelectorAssertions` (now in the `rails-dom-testing` gem, bundled with Rails 4.2).

**Detection Pattern:**
```ruby
assert_tag :tag => "a", :attributes => { :href => "/foo" }
```

**Fix:**
```ruby
# BEFORE
assert_tag :tag => "a", :attributes => { :href => "/foo" }

# AFTER
assert_select "a[href='/foo']"
```

---

#### Routing `Mapper::Mapping` Patches Stop Running

**Pattern:** `MAPPER_NORMALIZE_CONDITIONS`

**What Changed:**
Rails 4.2 rewrote the private `ActionDispatch::Routing::Mapper::Mapping`. On 4.0 and 4.1, `normalize_conditions!` builds each route's `required_defaults`: every option that is not a `Regexp`, a path segment or an ignored option. Apps patch it to keep custom route options (authorization metadata, for instance) out of `required_defaults`, so `url_for(controller: ..., action: ...)` without the named helper still finds the route. On 4.2:
- `normalize_conditions!`, `normalize_requirements!` and `default_controller_and_action` are gone. `required_defaults` is built in a new private `constraints(options, path_params)`.
- `normalize_defaults!`, `normalize_options!` and `normalize_path!` now take arguments.

What the app sees depends on how the patch hooks in:
- `alias_method` / `alias_method_chain` on a removed method: ``NameError: undefined method `normalize_conditions!' for class `ActionDispatch::Routing::Mapper::Mapping'`` at boot.
- Reopen or `prepend` overriding a removed method: the override never runs, the custom option is required again, and `url_for` raises `ActionController::UrlGenerationError`. Nothing fails at boot.
- A zero-argument override of `normalize_defaults!`, `normalize_options!` or `normalize_path!`: `ArgumentError: wrong number of arguments (given 1, expected 0)` on Ruby 2.3 and later, `(1 for 0)` on earlier Rubies (2 for `normalize_path!`, 5 for `normalize_options!`), when routes are drawn.
- An `initialize` override: 4.2 calls `Mapping.new(scope, set, path, defaults, as, options)` instead of `(set, scope, path, options)`, so a four-argument override raises `ArgumentError` when routes are drawn. The `scope`, `path` and `options` readers are gone, so a hook that reads `options[:authorize]` raises `NameError`.

**Detection Pattern:**
`MAPPER_NORMALIZE_CONDITIONS` flags the removed method names, `Routing::Mapper::Mapping` references and a `Mapping` reopen nested in `module Routing` / `class Mapper` (or written `class Mapper::Mapping` inside `module Routing`), in `app/`, `lib/` and `config/`. The `NextRails.next?` fallback below keeps matching until its 4.1 branch is removed. A bare `Mapper::Mapping` constant written inside `module Routing`, or a nested reopen with other code between `class Mapper` and `class Mapping`, is missed unless it names a removed method.

**Fix:**
Prefer dropping the patch. Options passed under `defaults:` land in `params` but never become required defaults, on 4.1 and 4.2 alike:
```ruby
# BEFORE (needs the Mapping patch so url_for ignores :authorize)
get "/posts/:id" => "posts#show", as: :post, authorize: :admin

# AFTER (no patch; scope defaults: { authorize: :admin } works the same way)
get "/posts/:id" => "posts#show", as: :post, defaults: { authorize: :admin }
```

If the patch must stay, hook the method each side has. Hooking `constraints` on 4.1 raises `ArgumentError` when routes are drawn, so pick it with `NextRails.next?`. An override of `normalize_defaults!`, `normalize_options!` or `normalize_path!` gets the same treatment with the 4.2 signature. `Module#prepend` needs Ruby 2.0; on 1.9.3 use `alias_method_chain` inside the same branches:
```ruby
# config/initializers/route_options.rb
module RouteOptionsOutOfRequiredDefaults
  CUSTOM_ROUTE_OPTIONS = [:authorize]

  if NextRails.next?
    private

    def constraints(options, path_params)
      result = super
      @conditions[:required_defaults] -= CUSTOM_ROUTE_OPTIONS
      result
    end
  else
    private

    def normalize_conditions!
      super
      @conditions[:required_defaults] -= CUSTOM_ROUTE_OPTIONS
    end
  end
end

ActionDispatch::Routing::Mapper::Mapping.send(:prepend, RouteOptionsOutOfRequiredDefaults)
```

Rails 5.0 changes `constraints` again (it returns the options grouped by kind and no longer writes `@conditions`), so a 4.2 hook breaks at the next hop. Move to `defaults:` before then.

---

### 🟡 MEDIUM PRIORITY

#### HTML Sanitizer Rewritten (Loofah/Nokogiri)

**Pattern:** `HTML_SANITIZER`

**What Changed:**
`sanitize`, `sanitize_css`, `strip_tags`, and `strip_links` are now backed by [Loofah](https://github.com/flavorjones/loofah) (via Nokogiri). Output may differ for edge-case inputs. `sanitize` also now accepts a `Loofah::Scrubber` — two new scrubbers ship with Rails: `PermitScrubber` and `TargetScrubber`.

**Detection Pattern:**
```ruby
sanitize(html_string)
strip_tags(html_string)
```

**Fix:**
Review tests that assert on sanitized output. If specific outputs diverge in ways you can't accommodate, temporarily restore the old sanitizer:
```ruby
# Gemfile (temporary fallback — Rails 4.2 only)
gem 'rails-deprecated_sanitizer'
```

---

#### Serialized Attributes with Custom Coder: `nil` Handling

**Pattern:** `SERIALIZED_CUSTOM_CODER`

**What Changed:**
Assigning `nil` to a serialized attribute with a custom coder (e.g., `serialize :metadata, JSON`) now saves `NULL` to the database instead of passing `nil` through the coder. Previously, JSON coder would have stored the string `"null"`.

**Detection Pattern:**
```ruby
class User < ActiveRecord::Base
  serialize :metadata, JSON
end

user.metadata = nil
user.save!  # Now saves NULL, not "null"
```

**Fix:**
Review code and tests that relied on the coder's nil representation. If you need the old behavior, store `JSON.generate(nil)` explicitly.

---

#### `Column#default` Returns the Raw Database String

**Pattern:** `COLUMN_DEFAULT_RAW`

**What Changed:**
Through 4.1, `Column#initialize` typed the default with `extract_default`, so `Model.columns_hash["ttl"].default` was an `Integer` and a boolean column's default was `true` / `false`. From 4.2.0 the column keeps the string the adapter read from the schema and casting moved to the attribute types, so `.default` returns `"604800"`, and `"f"` for a false boolean on SQLite. Nothing warns. Arithmetic on it raises (`Time.now - default` gives `TypeError: can't convert String into an exact number`), `<` / `>` against an Integer raise `ArgumentError: comparison of String with 3 failed`, `==` against a number or a boolean quietly returns false, and a false boolean default is now a non-empty String, so it is truthy. `Model.column_defaults` is unaffected for plain columns: it returns typed values on 4.0, 4.1 and 4.2.

**Detection Pattern:**
The `COLUMN_DEFAULT_RAW` pattern flags `.default`, `&.default` and `try` / `send` / `public_send` with `:default` read off `columns_hash[...]` (also `columns_hash(table)[...]` on the schema cache), `columns_hash.fetch(...)`, `column_for_attribute(...)`, a one-line `columns.find { }` / `detect { }` block, `columns.index_by(&:name)[...]`, and `column`, `@column` or `self.column`. It skips `.default.nil?`, which still works. A block variable with another name (`columns.each { |c| c.default }`) or a receiver-qualified `field.column.default` is not flagged, so also review loops over `columns` and wrappers that hold a column.

**Fix:**
```ruby
# BEFORE (typed on 4.1, a String on 4.2)
expires_at = created_at + self.class.columns_hash["ttl"].default
active = Thing.columns_hash["active"].default

# AFTER (typed on 4.0, 4.1 and 4.2, no conditional needed)
expires_at = created_at + self.class.column_defaults["ttl"]
active = Thing.column_defaults["active"]
```

On 4.2 `column_defaults` goes through the model's attribute types, so a `serialize`d column's default comes back deserialized there. Check those columns on both versions.

For a column read from `connection.columns(table)`, which no model types, cast on 4.2 only:

```ruby
default = NextRails.next? ? column.type_cast_from_database(column.default) : column.default
```

---

#### `ConnectionAdapters::Column` Class-Level Cast Helpers Removed

**Pattern:** `COLUMN_CAST_CLASS_METHODS`

**What Changed:**
Rails 4.2 moved type casting into `ActiveRecord::Type` and dropped the `class << self` block of `ActiveRecord::ConnectionAdapters::Column`. On 4.1 these are public class methods: `value_to_boolean`, `value_to_integer`, `value_to_decimal`, `value_to_date`, `string_to_time`, `string_to_dummy_time`, `binary_to_string`. Seven more are protected on 4.1 and reachable only through `send` or `method`: `new_date`, `new_time`, `fast_string_to_date`, `fast_string_to_time`, `fallback_string_to_date`, `fallback_string_to_time`, `microseconds`. The `PostgreSQLColumn::Cast` helpers (`string_to_hstore`, `string_to_json`, `string_to_array`, `hstore_to_string` and the rest) and the `Cast` module itself go too. Every caller raises `NoMethodError` on 4.2, except `try`, which returns `nil` without a word. 4.1 emits no deprecation warning first. The usual caller is `value_to_boolean`, used to cast checkbox and flag params.

**Detection Pattern:**
The `COLUMN_CAST_CLASS_METHODS` pattern flags these calls on `Column` (the full constant path, a bare `Column` after `include ActiveRecord::ConnectionAdapters`, `Mysql2Adapter::Column`, `MysqlAdapter::Column.string_to_date`), `PostgreSQLColumn` and `SQLite3Column`, called directly or through `send`, `__send__`, `public_send`, `try` or `method`. App classes such as `ReportColumn` or `Reports::Column` are skipped. It misses calls through `column.class` or `self.class` and bare calls inside a `Column` subclass.

**Fix:**
Replace each call with app-owned code. It runs on 4.1 and 4.2 alike, so no `NextRails.next?` branch is needed. Do not reach for `ActiveRecord::Type::Boolean` (absent on 4.1, renamed methods on 5.0, and on 4.2 it logs a deprecation for any value outside its true and false lists) or `Column::TRUE_VALUES` (removed in 5.0).

```ruby
# BEFORE
archived = ActiveRecord::ConnectionAdapters::Column.value_to_boolean(params[:archived])

# AFTER (same results as the 4.1 helper)
require "set"

module BooleanCast
  # A Set, like 4.1: it compares with eql?, so 1.0 and BigDecimal("1") stay false
  TRUE_VALUES = [true, 1, "1", "t", "T", "true", "TRUE", "on", "ON"].to_set.freeze

  def self.call(value)
    return nil if value.is_a?(String) && value.empty?
    TRUE_VALUES.include?(value)
  end
end

archived = BooleanCast.call(params[:archived])
```

For the other helpers:
- `value_to_integer(v)`: map `true` / `false` to `1` / `0`, otherwise `(v.to_i rescue nil)`, since 4.1 returned `nil` for a value with no `to_i`.
- `value_to_decimal(v)`: `v.respond_to?(:to_d) ? v.to_d : v.to_s.to_d` after `require "bigdecimal/util"`.
- `value_to_date`, `string_to_time`, `string_to_dummy_time` and the protected helpers they call: copy the method bodies from activerecord 4.1.16 `connection_adapters/column.rb` into an app module, together with the `Format::ISO_DATE` / `ISO_DATETIME` regexes (removed in 5.0), and spell `Base.default_timezone` as `ActiveRecord::Base.default_timezone`. `ActiveSupport::TimeZone#parse` is not a drop-in: it raises `ArgumentError` for `"2014-13-01 10:00"`, rolls `"2014-02-30"` over to March 2, fills in today for `"10:20"`, and turns `"2014-01-01T23:00:00-05:00"` into January 2 where `value_to_date` returned January 1. On those inputs the helpers returned `nil` or the written date.
- `binary_to_string(v)` on the base `Column` returns its argument: drop the call.
- A call on an adapter subclass (`SQLite3Column.binary_to_string`, `PostgreSQLColumn.string_to_time`, the MySQL `Column.string_to_time` / `string_to_date`, the `PostgreSQLColumn::Cast` helpers): copy that subclass override instead. SQLite3 forces `ASCII-8BIT`, and PostgreSQL maps `"infinity"` to `Float::INFINITY`.

Pin the replacement with a spec that covers every input the old helper saw.

---

#### Writes into `changed_attributes` Raise

**Pattern:** `CHANGED_ATTRIBUTES_WRITE`

**What Changed:**
On Active Record models, `changed_attributes` returns a frozen copy from Rails 4.2.0 (`super.reverse_merge(attributes_changed_in_place).freeze` in `attribute_methods/dirty.rb`). Through 4.1 it returned the live hash, and apps wrote into it to mark a virtual attribute as changed (so save callbacks or versioning gems run) or to drop a change before saving. On 4.2, `changed_attributes[name] = value`, `.delete`, `.merge!`, `.store`, `.clear`, `.except!` and the other in-place Hash writers raise `RuntimeError: can't modify frozen ActiveSupport::HashWithIndifferentAccess`. Reads are unaffected, and so is a plain `ActiveModel::Dirty` class, whose `changed_attributes` is not frozen.

**Detection Pattern:** `CHANGED_ATTRIBUTES_WRITE` flags element writes and in-place Hash writers on `changed_attributes`. It skips reads, copies (`.dup.delete`), the `@changed_attributes` instance variable and any line that mentions `NextRails.next?`, so the one-line dual-boot form below scans clean. A hit in a non-Active Record class, on a local variable with the same name, or inside a string needs no change. Writes through indirection are missed: `send(:changed_attributes)`, a `tap` block, or a copy of the reference (`h = changed_attributes` then `h.delete(k)`).

**Fix:**
`attribute_will_change!` exists on both versions and records what the reader returns now as the old value (nil when there is no reader). It does nothing when the attribute is already changed, so the first old value is kept. Where the old code wrote some other value, use `set_attribute_was` instead. Recording a specific old value and dropping a change use private `ActiveModel::Dirty` methods that only exist from 4.2, so branch on the Rails version until the upgrade ships:
```ruby
# BEFORE (raises on 4.2)
def tag_list=(value)
  changed_attributes["tag_list"] = @tag_list unless value == @tag_list
  @tag_list = value
end

def skip_timestamp_change
  changed_attributes.delete("updated_at")
end

# AFTER (4.1 and 4.2)
def tag_list=(value)
  attribute_will_change!("tag_list") unless value == @tag_list
  @tag_list = value
end

def skip_timestamp_change
  NextRails.next? ? clear_attribute_changes(["updated_at"]) : changed_attributes.delete("updated_at")
end

# A specific old value
NextRails.next? ? set_attribute_was(name, old) : changed_attributes[name] = old

# From another object: the 4.2 methods are private
NextRails.next? ? record.send(:clear_attribute_changes, [:token]) : record.changed_attributes.delete(:token)
```
`clear_attribute_changes` drops only a change recorded through a setter. On 4.2 a serialized or JSON column that was mutated in place (`prefs["x"] = 1`) stays in `changes` and is still written on save.

---

#### Integration Test Paths Need a Leading Slash

**Pattern:** `INTEGRATION_RELATIVE_PATH`

**What Changed:**
Integration sessions (`ActionDispatch::IntegrationTest`, RSpec request specs) now build the request URI as a string: scheme, host and port, then the path as given (`Integration::Session#build_full_uri`, new in 4.2.0). Rails 4.1 resolved the path against `/` with `URI#+`, so `get "users"` worked by accident. On 4.2 the same call requests `http://www.example.com:80users` and rack-test raises `URI::InvalidURIError: bad URI(is not URI?): http://www.example.com:80users` (Ruby 2.x wording). The actionpack 4.2.0 CHANGELOG lists it: the leading slash is now required in the integration test `process` helpers. A path that starts with `?` or `#`, and a full URL, still work. Specs that include `Rack::Test::Methods` directly (Grape or Sinatra apps) are not affected, since rack-test adds the slash itself.

**Detection Pattern:**
The pattern flags `get`/`post`/`put`/`patch`/`delete`/`head` (and the `xhr`, `xml_http_request`, `*_via_redirect` forms, where the path is the second argument) whose path is a string literal with no leading slash, in `spec/requests/`, `spec/integration/`, `spec/api/` and `test/integration/`. It skips rswag-style `get "List users" do` blocks, symbols, path helpers and variables. It misses a path that starts with interpolation (`get "#{id}/edit"`), a request used as an expression (`expect(get "users")`), a request followed by a block, calls on a session object (`sess.get "users"`) and request helpers in `spec/support/` or `test/support/` (left out because controller shared examples there pass action names such as `get "show"`): search those by hand.

**Fix:**
```ruby
# BEFORE
get "users", format: :json
xhr :post, "comments", body: "x"

# AFTER (works on 4.1 and 4.2)
get "/users", format: :json
xhr :post, "/comments", body: "x"
# or a path helper
get users_path(format: :json)
```

---



---

#### `config.active_support.test_order` Not Set

**Pattern:** `TEST_ORDER`

**What Changed:**
Rails 4.2 adds `config.active_support.test_order`. When it is not set, `ActiveSupport::TestCase` keeps the 4.1 order (`:sorted`, alphabetical) and prints a deprecation warning saying the default becomes `:random` in Rails 5. The warning comes from `ActiveSupport::TestCase.test_order`, which runs only when Minitest runs an `ActiveSupport::TestCase` subclass, so a suite that is RSpec only may never print it. Set the option anyway: the 4.2 to 5.0 hop changes the default.

**Detection Pattern:**
The `TEST_ORDER` pattern cannot detect a missing setting, so it flags the configure block of `config/environments/test.rb` for manual review. It matches both `Rails.application.configure do` (generated by Rails 4.1 and later) and `<App>::Application.configure do` (generated by Rails 4.0 and earlier, kept by apps that never regenerated the file). Open the file and check for `test_order`; an app may instead set `ActiveSupport::TestCase.test_order = ...` in `test/test_helper.rb`, which also counts on 4.2. Do not add the setting that way during the dual boot: 4.1 has no `ActiveSupport::TestCase.test_order=`, so that line raises `NoMethodError` on the 4.1 side. The `config.active_support` form below works on both.

**Fix:**
```ruby
# config/environments/test.rb
Rails.application.configure do # or MyApp::Application.configure do
  # Keep the 4.1 order during the upgrade
  config.active_support.test_order = :sorted

  # Or opt into the 4.2 generator value and the Rails 5 default
  # once the suite passes in random order
  # config.active_support.test_order = :random
end
```

The line works on both sides of the dual boot with no conditional. On 4.1 the `active_support.set_configs` initializer skips any key that `ActiveSupport` has no setter for, and 4.1 has no `ActiveSupport.test_order=`, so the line is ignored there.

---

#### `config.serve_static_assets` Renamed

**Pattern:** `SERVE_STATIC_ASSETS`

**What Changed:**
`config.serve_static_assets` was renamed to `config.serve_static_files`. In production, the default generated config now uses an ENV var.

**Detection Pattern:**
```ruby
config.serve_static_assets = true
```

**Fix:**
```ruby
# BEFORE (config/environments/test.rb)
config.serve_static_assets = true

# AFTER
config.serve_static_files = true

# BEFORE (config/environments/production.rb)
config.serve_static_assets = false

# AFTER (Rails 4.2 default)
config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?
```

---

#### Production Log Level Must Be Set Explicitly

**Pattern:** none (the warning fires on a missing setting, which a line regex cannot match)

**What Changed:**
The production default stays `:info` in 4.2, but booting production without a `config.log_level` line in `production.rb` now prints a deprecation warning: Rails 5 unifies the default to `:debug`. The 4.2 app template also writes `config.log_level = :debug` into `production.rb`, so accepting that file from `rake rails:update` makes production logs much noisier.

**Fix:**
```ruby
# BEFORE (config/environments/production.rb, no log_level line)

# AFTER
config.log_level = :info
```
This works on 4.1 as well. When running `rake rails:update`, keep your own `log_level` line instead of the template's `:debug`.

---

#### Masked CSRF Tokens (Per-Request)

**Pattern:** `CSRF_TOKEN_MASKING`

**What Changed:**
`form_authenticity_token` is now masked and varies per request (SSL attack mitigation). Non-Rails forms or external clients that cache a single token will break.

**Detection Pattern:**
```ruby
form_authenticity_token
```

**Fix:**
Rails form helpers handle masking automatically. If you build forms outside Rails (e.g., a static page posting to your app), fetch the token per request rather than caching it.

---

#### `@attributes` Is an `AttributeSet`, Not a Hash

**Pattern:** `ATTRIBUTES_IVAR_REPLACE`

**What Changed:**
Through 4.1 a record kept its raw column values in `@attributes`, a plain Hash. Rails 4.2.0 replaces it with `ActiveRecord::AttributeSet`, which keeps `[]`, `key?`, `keys` and `to_hash` but drops the rest of the Hash API (`[]=`, `fetch`, `merge!`, `delete`, `each` and so on). Code that reaches into the instance variable breaks:

- Swapping in a Hash (`instance_variable_set(:@attributes, attributes.merge(extra))` or `@attributes = ...`, usually in `after_initialize` to make extra non-column keys readable) fails on the first attribute read with ``NoMethodError: undefined method `fetch_value' for ...:Hash``.
- Writes (`@attributes['x'] = v`, `merge!`, `update`, `store`, `delete`) and Hash reads such as `fetch` raise `NoMethodError` on `ActiveRecord::AttributeSet`.
- `@attributes['x']` still works but returns an `ActiveRecord::Attribute` object instead of the value, so a comparison or presence check on it is silently wrong.

**Detection Pattern:**
```ruby
class Post < ActiveRecord::Base
  after_initialize { instance_variable_set(:@attributes, attributes.merge("extra" => 1)) }

  def legacy_title
    @attributes["title"]
  end
end
```

The pattern flags every direct `@attributes` reference in `app/models/` and `config/initializers/`. A plain Ruby class with its own `@attributes` Hash (a form object or a tableless model in `app/models/`) is unaffected: check that each hit is inside an ActiveRecord model or a patch to one. The pattern does not scan `lib/` or the rest of `app/`, where plain Ruby classes with their own `@attributes` are common. Search those by hand for ActiveRecord patches and for `instance_variable_get(:@attributes)` on a record (this skips `app/models/`, which the scanner already covered, and comment lines):
```bash
grep -rnE "(^|[^@[:alnum:]_])@attributes([^[:alnum:]_]|$)" lib app --include="*.rb" --exclude-dir=models \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
```

**Fix:**
Use the public attribute API, which behaves the same on 4.1 and 4.2, so no `NextRails.next?` branch is needed:
```ruby
# BEFORE
def legacy_title
  @attributes["title"]
end

def title=(value)
  @attributes["title"] = value.upcase
end

# AFTER
def legacy_title
  read_attribute_before_type_cast(:title)  # or read_attribute(:title) for the cast value
end

def title=(value)
  write_attribute(:title, value.upcase)
end
```

For extra non-column values, keep them out of `@attributes`:
```ruby
# BEFORE
after_initialize do
  instance_variable_set(:@attributes, attributes.merge("extra" => compute_extra))
end

# AFTER
after_initialize :load_extra
attr_accessor :extra

def reload(*)
  super.tap { load_extra }
end

# becomes (and becomes!) builds the new record with klass.new, so
# after_initialize runs on blank attributes: copy the value across
def becomes(klass)
  super.tap { |record| record.extra = extra if record.respond_to?(:extra=) }
end

# only if callers expect the value in attributes (serializers, audit gems)
def attributes
  super.merge("extra" => extra)
end

private

def load_extra
  self.extra = compute_extra
end
```

With this shape, `record.extra` and `attributes["extra"]` keep working, but `record[:extra]` and `read_attribute(:extra)` return `nil` on both versions. Search for those call forms and switch them to `record.extra`.

Do not call `attribute_will_change!` for the extra name: on 4.2 the partial `UPDATE` then includes it and fails with an unknown-column error: `no such column` on SQLite, `column "extra" of relation ... does not exist` on PostgreSQL, `Unknown column 'extra'` on MySQL. If saving must react to a change in the extra value, track that change yourself.

---

#### `Column#type_cast` Removed

**Pattern:** `COLUMN_TYPE_CAST_INSTANCE`

**What Changed:**
Rails 4.2 removes the public instance method `ActiveRecord::ConnectionAdapters::Column#type_cast(value)`. A 4.2 column hands casting to its `cast_type` and exposes it as `type_cast_from_database` and `type_cast_from_user` (both new in 4.2). `Type::Value#type_cast` is private, so `column.type_cast(value)` raises `NoMethodError`. The usual caller casts a param or a calculation result through `Model.columns_hash[name].type_cast(value)`.

The two-argument `connection.type_cast(value, column)` quoting method is a different API, still present on 4.2, and the pattern skips it. The removed class-level helpers (`Column.value_to_boolean` and friends) are a separate change.

**Detection Pattern:** the `COLUMN_TYPE_CAST_INSTANCE` regex flags one-argument `.type_cast` calls, with or without parentheses, and `send` / `try(:type_cast, value)` with or without parentheses. It skips the two-argument `connection.type_cast(value, column)` quoting method, which still exists, unless its first argument nests parentheses two levels deep (`type_cast(foo(a(b, c)), col)` is flagged, check the argument count). The `try` form does not raise on 4.2: Active Support `try` checks `respond_to?` and returns `nil`, so the cast silently becomes `nil`. Any other object with a public one-argument `type_cast` is flagged too, so check that the receiver is a column.

**Fix:**
First check whether the cast does anything. `minimum` and `maximum` already cast through the column on 4.1 and 4.2, so a cast of their result can simply go. Otherwise branch on the version:

```ruby
# BEFORE
column = Order.columns_hash["total"]
column.type_cast(params[:total])

# AFTER (works on 4.1 and 4.2)
column = Order.columns_hash["total"]
NextRails.next? ? column.type_cast_from_database(params[:total]) : column.type_cast(params[:total])
```

`type_cast_from_database` gives the 4.1 result for string, integer, decimal, boolean and datetime inputs, with one difference: a string column now returns a String for any value (`5` becomes `"5"`). `type_cast_from_user` is what an attribute writer uses, but it differs more: a blank string cast through an integer column gives `nil` instead of `0`. Rails 5.0 replaces both with `Order.type_for_attribute("total").cast(value)`.

---

#### `Numeric#ago` / `#until` / `#since` / `#from_now` Removed

**Pattern:** `NUMERIC_AGO_WITHOUT_UNIT`

**What Changed:**
Rails 4.1 deprecated calling `ago`, `until`, `since` and `from_now` on a plain number (`Calling #ago or #until on a number (e.g. 5.ago) is deprecated and will be removed in the future, use 5.seconds.ago instead`). Rails 4.2 removes them from `Numeric`, so `5.ago` raises ``NoMethodError: undefined method `ago' for 5:Fixnum`` (`for 5:Integer` on Ruby 2.4 and later). The same methods on a Duration (`5.seconds.ago`) are unchanged.

Two shapes are easy to miss. Through 4.2 a Duration has no `*` or `/` of its own: they go through `method_missing` to the Integer value and return a plain Integer, so `(2.hours * 3).ago` and `(1.day / 2).ago` raise too, while `(1.day + 1.hour).ago` keeps working. And a number of seconds stored in a variable (`timeout.ago`), often read from YAML, ENV or a settings table and passed to a gem that calls `ago` on it, cannot be found by a regex: it shows up only as the 4.1 deprecation warning in logs and test output.

**Detection:**
The pattern flags numeric literals and `.to_i` / `.to_f` / `.abs` results followed by one of the four methods, and `.round` / `.floor` / `.ceil` results and parenthesized `*` / `/` expressions followed by one of them with no argument. `Time#ago` and `#since` always take an argument, so `Time.current.round.ago(1.hour)` and `(Time.now - 2 * 3600).since(1.hour)` are left alone. A hit can still be a Duration: `(1.day + 2 * 3.hours).ago` is flagged although the sum keeps its unit, so check the receiver before adding `.seconds`. Other Integer-returning calls (`items.count.ago`) are not flagged. On 4.1, also search the test log for `Calling #ago or #until on a number` and `Calling #since or #from_now on a number`.

**Fix:**
```ruby
# BEFORE
expires_at = 5.ago
cutoff = timeout.from_now
window = (2.hours * 3).ago

# AFTER (works on 4.1 and 4.2)
expires_at = 5.seconds.ago
cutoff = timeout.seconds.from_now
window = (2.hours * 3).seconds.ago
```
For a value read from configuration, convert it once where it is read (`setting.seconds`) so every consumer gets a Duration. A Duration is `==` to its Integer value, does arithmetic like it and serializes to JSON as it. It is not the same object to `Integer === x` (so `case x when Integer`), `eql?` or a Hash key lookup, on 4.1 and on 4.2, so check the setting's other consumers before converting it at read time.

---

### 🟢 LOW PRIORITY

#### Rack Server Bind Host Changed

**Pattern:** `SERVER_BIND`

**What Changed:**
Rails 4.2's bundled Rack binds `rails server` to `localhost` instead of `0.0.0.0` by default. Docker, Vagrant, and remote-access setups break.

**Detection Pattern:**
```
# Procfile without explicit bind
web: bundle exec rails s
```

**Fix:**
```
# Procfile
web: bundle exec rails s -b 0.0.0.0

# Or per command
rails server -b 0.0.0.0 -p 3000
```

---

#### Foreigner → Native Foreign Keys (Optional)

**Pattern:** `FOREIGNER`

**What Changed:**
Rails 4.2 ships with a native foreign-key DSL for migrations. You can now drop the [`foreigner`](https://github.com/matthuhiggins/foreigner) gem if its features are a match.

**Detection Pattern:**
```ruby
# Gemfile
gem 'foreigner'
```

**Fix (optional):**
1. Remove `gem 'foreigner'` from your Gemfile
2. `bundle install`
3. `bin/rake db:schema:dump`
4. Verify `db/schema.rb` still matches your database

Rails' FK support is a subset of Foreigner's — keep the gem if you use its advanced features (e.g., `:dependent => :restrict`).

New migration API:
```ruby
add_foreign_key :posts, :users
# or in a table definition
t.references :user, foreign_key: true
```

---

#### Timecop Replaceable with Built-in Time Helpers

**Pattern:** `TIMECOP`

**What Changed:**
Rails 4.2 adds `travel`, `travel_to`, and `travel_back` test helpers via `ActiveSupport::Testing::TimeHelpers`. These replace most Timecop use cases.

**Detection Pattern:**
```ruby
gem 'timecop'
Timecop.freeze(...)
```

**Fix:**
```ruby
# BEFORE
Timecop.freeze(Time.zone.local(2024, 1, 1)) do
  # test code
end

# AFTER
travel_to Time.zone.local(2024, 1, 1) do
  # test code
end
```

Keep Timecop if you use its rate feature (e.g., "1 second = 1 hour").

---

#### RSpec 2 Not Supported

**Pattern:** `RSPEC_2`

**What Changed:**
Rails 4.2 does not support RSpec 2. You must upgrade to RSpec 3 before (or alongside) the Rails upgrade.

**Fix:**
Upgrade in two steps:
1. Upgrade to `rspec-rails ~> 2.99` (prints all 3.0 deprecation warnings). Fix every deprecation.
2. Upgrade to `rspec-rails ~> 3.x`.

Consider [Transpec](http://yujinakayama.me/transpec/) to automate common 2 → 3 syntax conversions.

---

#### Ruby Version Requirement

**Pattern:** none (the minimum Ruby does not change at this hop)

**What Changed:**
Nothing. The `rails` 4.2 gemspec requires Ruby `>= 1.9.3`, the same as 4.1, so the Ruby that bundles 4.1 also bundles 4.2. The gemspec sets no upper bound; a Ruby released after 4.2 may need its latest patch release.

**Fix:**
None needed for this hop. Upgrade Ruby as a separate step, not in the same deploy as the Rails bump.

---

## New Gemfile Defaults

Rails 4.2 generates new applications with these additions — consider adopting them:

```ruby
# Gemfile

group :development do
  gem 'web-console', '~> 2.0'  # interactive IRB on error pages
  gem 'spring'                  # preloader (moved into :development group)
end

group :development, :test do
  gem 'byebug'                  # replaces the commented-out `debugger`
end
```

Version bumps for defaults:
- `sass-rails` `~> 4.0.3` → `~> 5.0`
- `coffee-rails` `~> 4.0.0` → `~> 4.1.0`

---

## Configuration File Changes

Run `bin/rake rails:update` to walk through config changes interactively. Key diffs to review:

### `config/application.rb`
Add (inside the Application class):
```ruby
config.active_record.raise_in_transactional_callbacks = true
```

### `config/environments/development.rb`
Add:
```ruby
config.assets.digest = true
```

### `config/environments/test.rb`
Add:
```ruby
config.active_support.test_order = :sorted # keeps the 4.1 order; the 4.2 generator writes :random
```

Rename:
```ruby
# BEFORE
config.serve_static_assets = true
# AFTER
config.serve_static_files = true
```

### `config/environments/production.rb`
Rename `serve_static_assets` to `serve_static_files`. The new template sets `config.log_level = :debug`; keep `:info` to preserve 4.1 behavior (see "Production Log Level Must Be Set Explicitly").

### `config/initializers/to_time_preserves_timezone.rb` (NEW)
Forward-compat shim for Rails 5.0:
```ruby
# Preserve the timezone of the receiver when calling to_time.
# Ruby 2.4 will change the behavior of to_time to preserve the timezone.
ActiveSupport.to_time_preserves_timezone = true
```

### `bin/setup` (NEW)
New convention script that installs dependencies and sets up the app. Run `bin/rake rails:update:bin` to generate it.

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-42-upgrade

# Verify Ruby version
ruby -v  # 1.9.3+; 2.0+ recommended
```

### Phase 2: Pre-requisites (before the Rails bump)
1. **Upgrade RSpec to 3.x** if using RSpec 2 (independent of Rails)
2. **Fix all current 4.1 deprecation warnings** — they become errors or silent failures in 4.2
3. **Add `gem 'responders', '~> 2.0'`** if using `respond_with`

### Phase 3: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 4.2.0'
gem 'responders', '~> 2.0'  # only if using respond_with
gem 'sass-rails', '~> 5.0'
gem 'coffee-rails', '~> 4.1.0'

group :development do
  gem 'web-console', '~> 2.0'
  gem 'spring'
end

group :development, :test do
  gem 'byebug'
end
```

```bash
bundle update rails
```

### Phase 4: Configuration
```bash
bin/rake rails:update
```

Cross-check against [RailsDiff 4.1.16 → 4.2.11.3](http://railsdiff.org/4.1.16/4.2.11.3) for the exact diff.

### Phase 5: Fix Breaking Changes
1. Replace `.deliver` / `.deliver!` with `.deliver_now` / `.deliver_now!` (or `.deliver_later` for async)
2. Replace `.find(obj)` / `.exists?(obj)` with `.find(obj.id)` / `.exists?(obj.id)`
3. Replace `assert_tag` with `assert_select`
4. Update `Procfile` with `-b 0.0.0.0` if external access needed
5. Review HTML sanitizer output in tests
6. Replace writes into `changed_attributes` with `attribute_will_change!`, or `set_attribute_was` / `clear_attribute_changes` behind `NextRails.next?` (see "Writes into `changed_attributes` Raise")
7. Add `config.active_record.raise_in_transactional_callbacks = true`
8. Add `config.active_support.test_order = :sorted` (or `:random` once the suite passes in random order)
9. Rename `serve_static_assets` → `serve_static_files`
10. Add a unit to `ago` / `until` / `since` / `from_now` called on a bare number (`5.ago` → `5.seconds.ago`)
11. Add the leading slash to integration and request spec paths (`get "/users"`)
12. If the app patches `Mapper::Mapping` (`normalize_conditions!` and friends), move the custom route options under `defaults:` and drop the patch
13. Replace one-argument `column.type_cast(value)` with `type_cast_from_database` behind `NextRails.next?`
14. Replace `ConnectionAdapters::Column.value_to_boolean` and the other removed class-level cast helpers with app-owned casts
15. Replace `columns_hash[...].default` and `column_for_attribute(...).default` reads with `column_defaults[...]`; cast a model-less `connection.columns(...)` default with `type_cast_from_database` behind `NextRails.next?`
16. Replace direct `@attributes` access in models with `read_attribute` / `write_attribute`
17. Consider replacing Timecop with `travel_to` (optional)
18. Consider dropping Foreigner for native FKs (optional)

### Phase 6: Testing
- Run full test suite
- Test email delivery (`deliver_now` vs `deliver_later`)
- Test `after_commit` / `after_rollback` callbacks
- Test forms with HTML-sanitized content
- Test any code that caches `form_authenticity_token`
- Test serialized attributes that may receive `nil`

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `NoMethodError: undefined method 'deliver' for #<Mail::Message>` | "ActionMailer `#deliver` / `#deliver!` Deprecated" — `deliver_now` / `deliver_later` |
| `undefined method 'respond_with' for ApplicationController` | "`respond_with` / Class-Level `respond_to` Extracted" — `gem 'responders', '~> 2.0'` |
| Data inconsistencies that tests don't catch after `after_commit` | "Transactional Callback Exception Suppression" — `config.active_record.raise_in_transactional_callbacks = true` |
| Can't reach `rails server` from another machine | "Rack Server Bind Host Changed" — `rails server -b 0.0.0.0` |
| Serialized attributes that stored `"null"` now store `NULL` | "Serialized Attributes with Custom Coder: `nil` Handling" — assign `JSON.generate(nil)` only if the string was intentional |
| ``NoMethodError: undefined method `fetch_value' for ...:Hash`` on an attribute read | "`@attributes` Is an `AttributeSet`, Not a Hash": stop replacing `@attributes` |
| ``NoMethodError: undefined method `[]=' for #<ActiveRecord::AttributeSet:0x...>`` (or `merge!`, `fetch`, `delete`) | "`@attributes` Is an `AttributeSet`, Not a Hash": `write_attribute` / `read_attribute` |
| `@attributes['x']` returns an `ActiveRecord::Attribute` instead of the value | "`@attributes` Is an `AttributeSet`, Not a Hash": `read_attribute_before_type_cast` |
| `TypeError` or a wrong branch where code reads `columns_hash[...].default` (now a String such as `"604800"` or `"f"`), or `ArgumentError: comparison of String with ...` | "`Column#default` Returns the Raw Database String", read `column_defaults[...]` |
| `RuntimeError: can't modify frozen ActiveSupport::HashWithIndifferentAccess` from a model | "Writes into `changed_attributes` Raise": `attribute_will_change!`, `clear_attribute_changes` |
| `URI::InvalidURIError: bad URI(is not URI?): http://www.example.com:80users` in a request or integration spec | "Integration Test Paths Need a Leading Slash", add the leading `/` |
| `InvalidAuthenticityToken` on forms submitted from static pages | "Masked CSRF Tokens (Per-Request)" — fetch a fresh token per request |
| `NoMethodError: undefined method 'value_to_boolean' for ActiveRecord::ConnectionAdapters::Column:Class` (or `string_to_time`, `value_to_decimal`, ...) | "`ConnectionAdapters::Column` Class-Level Cast Helpers Removed": app-owned cast |
| ``NoMethodError: undefined method `type_cast' for #<ActiveRecord::ConnectionAdapters::...Column>`` | "`Column#type_cast` Removed", use `type_cast_from_database` |
| ``NameError: undefined method `normalize_conditions!' for class `ActionDispatch::Routing::Mapper::Mapping'`` at boot | "Routing `Mapper::Mapping` Patches Stop Running": drop the patch, move the option under `defaults:` |
| `ActionController::UrlGenerationError` from `url_for` on a route with a custom option that worked on 4.1 | "Routing `Mapper::Mapping` Patches Stop Running": the `normalize_conditions!` patch no longer runs |
| `ArgumentError: wrong number of arguments (given N, expected 0)` (or `(N for 0)` before Ruby 2.3) when routes are drawn | "Routing `Mapper::Mapping` Patches Stop Running": a `normalize_defaults!` / `normalize_options!` / `normalize_path!` override needs the 4.2 signature |
| ``DEPRECATION WARNING: You did not specify a value for the configuration option `active_support.test_order` `` | "`config.active_support.test_order` Not Set", set `:sorted` to keep the 4.1 order |
| ``NoMethodError: undefined method `ago' for 5:Fixnum`` (or `until` / `since` / `from_now`, `for 1.5:Float`, `for 5:Integer` on Ruby 2.4+) | "`Numeric#ago` / `#until` / `#since` / `#from_now` Removed": add a unit: `5.seconds.ago` |

---

## Resources

- [Rails 4.2 Release Notes](https://guides.rubyonrails.org/v4.2/4_2_release_notes.html)
- [Upgrading from Rails 4.1 to Rails 4.2 (official)](https://guides.rubyonrails.org/v4.2/upgrading_ruby_on_rails.html#upgrading-from-rails-4-1-to-rails-4-2)
- [FastRuby.io: Upgrade Rails from 4.1 to 4.2](https://www.fastruby.io/blog/rails/upgrades/upgrade-rails-from-4-1-to-4-2.html)
- [RailsDiff 4.1.16 → 4.2.11.3](http://railsdiff.org/4.1.16/4.2.11.3)
- [`responders` gem](https://github.com/heartcombo/responders)
- [`web-console` gem](https://github.com/rails/web-console)
- [ActiveSupport::Testing::TimeHelpers](https://api.rubyonrails.org/v4.2/classes/ActiveSupport/Testing/TimeHelpers.html)
