# Rails 4.0 → 4.1 Upgrade Guide

**Ruby Requirement:** 1.9.3+ (2.0+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs), the [official Rails 4.1 upgrade guide](https://guides.rubyonrails.org/v4.1/upgrading_ruby_on_rails.html#upgrading-from-rails-4-0-to-rails-4-1), and the Rails 4.1 release notes.**

---

## Overview

Rails 4.1 is a minor release that polishes 4.0 and introduces several new features:
- **Spring** application preloader (new default)
- **`secrets.yml`** for centralized secret/credential management
- **Action Mailer previews** (browser-viewable emails in development)
- **ActiveRecord enums** (`enum status: [...]`)
- **Variants** (`request.variant = :tablet`)
- **`Module#concerning`** API

The breaking changes are smaller than 3.2 → 4.0 but several silently change behavior. Dynamic-finder removal, implicit-join removal, and PostgreSQL `json`/`hstore` key semantics are the most common sources of runtime failures.

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### Dynamic Finders Removed

**What Changed:**
`activerecord-deprecated_finders` was removed as a Rails dependency. `find_all_by_*`, `find_last_by_*`, `scoped_by_*`, `find_or_initialize_by_*`, and `find_or_create_by_*` no longer work out of the box.

**Detection Pattern:**
```ruby
User.find_all_by_email(email)
User.find_last_by_email(email)
User.scoped_by_status("active")
User.find_or_initialize_by_email(email)
User.find_or_create_by_email(email)
```

**Fix:**
```ruby
# BEFORE
User.find_all_by_email(email)
User.find_last_by_email(email)
User.scoped_by_status("active")
User.find_or_initialize_by_email_and_name(email, name)
User.find_or_create_by_email(email)

# AFTER
User.where(email: email)
User.where(email: email).last
User.where(status: "active")
User.find_or_initialize_by(email: email, name: name)
User.find_or_create_by(email: email)
```

If you cannot migrate callers now, restore the bridge gem:
```ruby
# Gemfile
gem 'activerecord-deprecated_finders'
```

---

#### `return` Inside Inline Callback Blocks

**What Changed:**
Using `return` inside an **inline callback block** now raises `LocalJumpError` at callback-execution time. This was never officially supported; a rewrite of `ActiveSupport::Callbacks` in 4.1 closed the accidental support.

**Scope:** this affects *inline blocks only* (`before_save { return false }`). Method-form callbacks (`before_save :guard` where `guard` contains `return false`) are unaffected — `return` there behaves normally and `false` still halts the chain on 4.1.

**Detection Pattern:**
```ruby
before_save { return false if invalid_state? }
```

**Fix:**
```ruby
# BEFORE
before_save { return false if invalid_state? }

# AFTER — evaluate to the value
before_save { false if invalid_state? }

# OR — extract to a method where `return` is fine
before_save :halt_if_invalid

def halt_if_invalid
  return false if invalid_state?
end
```

Note: in Rails 5+ the halt mechanism changes again — `false` no longer halts, use `throw :abort`.

See [rails/rails#13271](https://github.com/rails/rails/pull/13271).

---

#### Implicit Join References Removed

**What Changed:**
`includes(...).where("other_table.col = ...")` no longer auto-joins the referenced table. The string-parsing heuristic was removed because it produced incorrect SQL in edge cases.

**Detection Pattern:**
```ruby
Post.includes(:comments).where("comments.title = ?", "foo")
```

**Fix:**
```ruby
# BEFORE
Post.includes(:comments).where("comments.title = ?", "foo")

# AFTER — explicit join (no eager load)
Post.joins(:comments).where("comments.title = ?", "foo")

# AFTER — eager load
Post.eager_load(:comments).where("comments.title = ?", "foo")

# AFTER — equivalent with includes + references
Post.includes(:comments).where("comments.title = ?", "foo").references(:comments)
```

If you see this warning:
```
DEPRECATION WARNING: Implicit join references were removed with Rails 4.1. Make sure to remove this configuration because it does nothing.
```
remove `config.active_record.disable_implicit_join_references` from your config.

See [rails/rails#9712](https://github.com/rails/rails/issues/9712) for background.

---

#### PostgreSQL `json` / `hstore` / `array` Columns Return String-Keyed Data

**What Changed:**
In 4.0, PostgreSQL `json`, `hstore`, and `array` columns (and any `store_accessor` built on top of them) returned a `HashWithIndifferentAccess` or `ArrayWithIndifferentAccess` — symbol and string access both worked. In 4.1 they return plain `Hash` or `Array` with **string keys only**. Symbol access silently returns `nil`.

**Detection Pattern:**
```ruby
class Profile < ActiveRecord::Base
  # :preferences is a json or hstore column
  store_accessor :preferences, :theme
end

profile.preferences[:theme]   # 4.0: "dark" | 4.1: nil
profile.preferences["theme"]  # both: "dark"
```

**Fix:**
Use string keys consistently when reading from `json` / `hstore` attributes:
```ruby
# BEFORE
profile.preferences[:theme]

# AFTER
profile.preferences["theme"]
```

`store_accessor`-generated methods (`profile.theme`) still work — the change only bites direct hash lookups. Audit serializers, presenters, and `as_json` overrides that index into these attributes.

---

#### `cache_digests` Gem Collides with Core Cache Digests

**What Changed:**
Rails 4.1 ships cache digests in core as `ActionView::Digestor`. The `cache_digests` gem that backported them to 4.0 does not merely go unused, it **collides**. actionview's `action_view/tasks/dependencies.rake` declares `class CacheDigests` inside a `namespace :cache_digests do` block, and a Rake namespace does not scope Ruby constants, so that defines top-level `::CacheDigests`. The gem defines `module CacheDigests`. Class against module on one constant raises while Rails loads its rake tasks:

```
rake aborted!
TypeError: CacheDigests is not a class
actionview-4.1.16/lib/action_view/tasks/dependencies.rake:14
```

The blast radius is the whole rake surface, not one task: every `rake` invocation dies before running, so asset precompile, db tasks, and any CI step that shells out to rake fail together. It does **not** reproduce under `rails runner` or the test suite, because neither loads rake tasks. A boot smoke test and a green suite can both pass while CI is entirely red.

**Detection Pattern:**
```ruby
# Gemfile
gem 'cache_digests'

# anywhere in app/ lib/ config/
CacheDigests::TemplateDigestor.digest(...)
CacheDigests.cache = ...
```

**Fix:**
```ruby
# Gemfile — gate it out of the 4.1 bundle; do not delete it while the current
# bundle is still 4.0 and depends on it
gem 'cache_digests' unless NextRails.next?
```

Then confirm nothing first-party reaches the gem's API, because core's is not call-compatible:

| `cache_digests` gem | Rails 4.1 core |
|---|---|
| `CacheDigests::TemplateDigestor.digest(name, format, finder, options)` (positional) | `ActionView::Digestor.digest(name:, finder:, dependencies:, partial:)` (single options hash) |
| `cache_prefix`, swappable `cache` accessor | gone — fixed `ThreadSafe::Cache` under a monitor, stored only when `Resolver.caching?` |
| `cache ['v3', @post]` explicitly-versioned key | gone — only `skip_digest: true` remains |
| `view_cache_dependency` | unchanged, in `ActionView::Helpers::CacheHelper` |

Core's ERB dependency tracker also detects **more** dependencies than the gem's (it parses `layout:` keys and method chains), so fragment digests can move. That is a cold fragment cache on the first deploy, not an error. An app with no `cache` call in any view has nothing to verify here.

Delete the gem outright once the current Rails is 4.1.

---

#### `JoinDependency` Internals Changed (`parent_table_name`, `join_to`)

**What Changed:**
Rails 4.1 rewrote `ActiveRecord::Associations::JoinDependency`. `JoinAssociation` no longer keeps a parent, so `parent_table_name` (4.0 delegated it to the parent) is gone, along with `parent`, `parent_table`, `join_dependency`, `join_type` and `aliased_prefix`, and `join_to(manager)` became `join_constraints(foreign_table, foreign_klass, node, join_type, tables, scope_chain, chain)`. The class is `:nodoc:`, but two kinds of app code reach into it:

- **An association scope that takes an argument.** When the association is used in `joins`, Rails passes the `JoinAssociation` to the scope. A scope that builds SQL from `parent_table_name` raises on 4.1:
  ```
  NoMethodError: undefined method `parent_table_name' for #<ActiveRecord::Associations::JoinDependency::JoinAssociation:0x...>
  ```
- **A monkeypatch on `join_to`.** `alias_method_chain :join_to, ...` raises `NameError` at load. A module prepended to override `join_to` loads fine and is never called, so whatever SQL it added silently disappears from every join.

**Detection Pattern:**
```ruby
has_many :live_posts, ->(join) {
  where("#{join.aliased_table_name}.deleted_at IS NULL AND #{join.parent_table_name}.active = 1")
}, class_name: "Post"

module SoftDeleteJoin
  def join_to(manager) ... end
end
ActiveRecord::Associations::JoinDependency::JoinAssociation.send(:prepend, SoftDeleteJoin)

class ActiveRecord::Associations::JoinDependency
  class JoinAssociation
    def join_to_with_soft_delete(manager) ... end
    alias_method_chain :join_to, :soft_delete
  end
end
```

The pattern also flags `.parent_table`, `.aliased_prefix` and `.join_dependency`. It skips `.parent` and `.join_type`, which are too common elsewhere, so read every association scope that takes an argument for those two by hand.

**Fix:**
```ruby
# BEFORE
has_many :live_posts, ->(join) {
  where("#{join.aliased_table_name}.deleted_at IS NULL AND #{join.parent_table_name}.active = 1")
}, class_name: "Post"

# AFTER: aliased_table_name still exists on 4.1; name the parent table directly
has_many :live_posts, ->(join) {
  where("#{join.aliased_table_name}.deleted_at IS NULL AND #{Author.quoted_table_name}.active = 1")
}, class_name: "Post"
```

Naming the parent table directly only works when that table is not aliased in the query. If it can be (self-joins, the same association joined twice), move the condition into a scope applied where the query is built.

For a `join_to` patch, write a `join_constraints` version for 4.1 and pick between the two with `NextRails.next?`. Then compare `to_sql` for the affected joins on both bundles: a patch that silently stops running changes queries without necessarily failing a test.

---

### 🟡 MEDIUM PRIORITY

#### MultiJSON Removed from Rails

**What Changed:**
Rails 4.1 no longer depends on [`MultiJSON`](https://github.com/intridea/multi_json). Apps that reference `MultiJSON` directly will raise `NameError` once the transitive dependency goes away.

**Detection Pattern:**
```ruby
require 'multi_json'
MultiJSON.dump(obj)
MultiJSON.load(str)
```

**Fix:**
```ruby
# Option A — keep MultiJSON explicitly
# Gemfile
gem 'multi_json'

# Option B — migrate to core JSON
# BEFORE
MultiJSON.dump(obj)
MultiJSON.load(str)

# AFTER
obj.to_json
JSON.parse(str)
```

**Do not** blindly substitute `JSON.dump` / `JSON.load` — those are the `JSON` gem's arbitrary-object (de)serializers and are unsafe on untrusted input.

---

#### Cookies Serializer Opt-In (Marshal → JSON / Hybrid)

**What Changed:**
Apps created before 4.1 keep `Marshal` as the signed/encrypted cookie serializer. Rails 4.1 introduces a JSON serializer and a `:hybrid` mode that reads legacy Marshal cookies and writes new JSON ones — but the default is still `Marshal` unless you opt in.

**Detection Pattern:**
Missing initializer. No `cookies_serializer` set in `config/initializers/` or `config/application.rb`.

**Fix:**
Add an initializer to migrate transparently:
```ruby
# config/initializers/cookies_serializer.rb
Rails.application.config.action_dispatch.cookies_serializer = :hybrid
```

Once all live cookies have rotated, switch to `:json` for the leaner path. Note that JSON cannot round-trip arbitrary Ruby objects — `Date`/`Time` become strings, symbol keys become strings. Store primitives only in cookie-backed sessions/flash.

---

#### `default_scope` Chains with Other Scopes

**What Changed:**
In Rails 4.1, `default_scope` conditions are now combined (ANDed) with subsequent scopes instead of being overridden by them. Scopes that intentionally contradicted the default scope now produce zero rows.

**Detection Pattern:**
```ruby
class User < ActiveRecord::Base
  default_scope { where(active: true) }
  scope :inactive, -> { where(active: false) }
end

# Rails 4.0:  SELECT ... WHERE active = false
# Rails 4.1:  SELECT ... WHERE active = true AND active = false
User.inactive
```

**Fix:**
Use `unscoped`, `unscope(...)`, or the new `rewhere` method:
```ruby
scope :inactive, -> { unscope(where: :active).where(active: false) }
# or
scope :inactive, -> { rewhere(active: false) }
```

See [this commit](https://github.com/rails/rails/commit/f950b2699f97749ef706c6939a84dfc85f0b05f2).

---

#### `ActiveRecord::Relation` Mutator Methods Removed

**What Changed:**
`#map!`, `#delete_if`, `#compact!`, and other mutator methods are no longer delegated from `Relation` to the underlying array. Call `#to_a` first.

**Detection Pattern:**
```ruby
Project.where(title: "Rails Upgrade").compact!
Project.where(...).map! { |p| ... }
Project.where(...).delete_if { |p| ... }
```

**Fix:**
```ruby
# BEFORE
Project.where(name: "Rails Upgrade").compact!

# AFTER
projects = Project.where(name: "Rails Upgrade").to_a
projects.compact!
```

---

#### CSRF Protection Now Covers GET with JS Responses

**What Changed:**
GET requests with JS responses now enforce CSRF. Test helpers that issue `get` / `post :create, format: :js` must switch to `xhr` so Rails treats the request as XHR.

**Detection Pattern:**
```ruby
post :create, format: :js
get :index, format: :js
```

**Fix:**
```ruby
# BEFORE
post :create, format: :js

# AFTER
xhr :post, :create, format: :js
```

If you legitimately want to serve JS to remote `<script>` tags, skip CSRF on that specific action.

Forward-compat note: the `xhr :verb, :action, ...` syntax is itself removed in Rails 5.0. The 5.0 replacement is `verb :action, params: {...}, xhr: true` (or `process :action, method: :verb, xhr: true`). You will revisit these test calls in the 4.2 → 5.0 hop.

See [rails/rails#13345](https://github.com/rails/rails/pull/13345).

---

#### Flash Message Keys Are Strings

**What Changed:**
Keys in `flash.to_hash` are now strings, not symbols. Code that filters the hash with symbol keys silently no-ops.

**Detection Pattern:**
```ruby
flash.to_hash.except(:notify)
flash.to_hash.slice(:alert, :notice)
```

**Fix:**
```ruby
# BEFORE
flash.to_hash.except(:notify)

# AFTER
flash.to_hash.except("notify")
```

Direct access with either symbol or string still works — the break is specifically in `to_hash`-derived iteration/filtering.

---

#### I18n Enforces Available Locales

**What Changed:**
`config.i18n.enforce_available_locales` defaults to `true` in 4.1. Any locale that is not in `I18n.available_locales` raises `I18n::InvalidLocale`. Apps that accepted user-supplied locale parameters without validation will raise on previously-accepted input.

**Detection Pattern:**
```ruby
I18n.locale = params[:locale]  # previously accepted anything
```

**Fix:**
Preferred — fix data and keep enforcement on. Make sure every locale the app actually uses is declared:
```ruby
# config/application.rb
config.i18n.available_locales = [:en, :es, :fr]
```

Escape hatch — disable enforcement (not recommended; the default exists for a security reason):
```ruby
# config/application.rb
config.i18n.enforce_available_locales = false
```

---

#### `as_json` Millisecond Precision for Time/DateTime/TWZ

**What Changed:**
`Time`, `DateTime`, and `ActiveSupport::TimeWithZone` serialize to JSON with millisecond precision by default (`2024-01-01T00:00:00.000Z` instead of `2024-01-01T00:00:00Z`). API clients that parse the timestamp as a fixed-length string or match it against a regex break.

**Detection Pattern:**
Contract tests or client code that expects second-precision ISO-8601 timestamps in JSON responses.

**Fix:**
Preserve 4.0 behavior globally:
```ruby
# config/initializers/time_precision.rb
ActiveSupport::JSON::Encoding.time_precision = 0
```

Or update consumers to accept fractional seconds.

---

#### `Relation#all` Returns a Relation, Not an Array

**What Changed:**
On 4.0, `Relation#all` comes from the bundled `activerecord-deprecated_finders` gem: calling it on a relation or an association emits a deprecation warning and returns an `Array`. Rails 4.1 drops that gem, so the same call falls through to the model's class-level `all` and returns a `Relation`. Iteration keeps working. Code that treats the result as an `Array` does not: `sort!`, `pop`, `shift` and the other bang mutators raise `NoMethodError`, and `is_a?(Array)` turns `false`. The finder-options form (`.all(conditions: ...)`) raises `ArgumentError` on 4.1.

`Model.all` on a constant is the replacement, not the problem. It returns a `Relation` on both versions and does not warn.

**Detection Pattern:**
```ruby
Post.where(published: true).all
@post.comments.all
User.active.all.sort_by!(&:name)
```

**Fix:**
```ruby
# BEFORE
posts = Post.where(published: true).all
names = User.active.all.sort_by!(&:name)

# AFTER
posts = Post.where(published: true).to_a
names = User.active.to_a.sort_by!(&:name)
```

Use `to_a`, not the `load` the deprecation message also suggests: `load` returns the `Relation`, so it changes the return type. Dropping `.all` entirely is fine where the caller only iterates, but keep `to_a` when the result is appended to with `<<`: on a `has_many` association of a saved record, `<<` saves the new record instead of adding to a local list.

The pattern flags every `.all` not followed directly by `(`. Most hits are `Model.all`. Capybara's `page.all(".row")` is skipped, but `page.all ".row"` without parentheses matches, and so does `.all (...)` with a space before the parenthesis. Objects with their own `all` method also match. Check the receiver before rewriting. `gem 'activerecord-deprecated_finders'` restores the 4.0 behavior on 4.1 as a short-term bridge.

---

#### `count` on a Multi-Column `select` Builds Invalid SQL

**What Changed:**
Rails 4.0 ignores a `select` list that contains a comma or `*` when it builds a count, so the count runs `COUNT(*)`. Rails 4.1 passes the select list straight into `COUNT`:

```
ActiveRecord::StatementInvalid: SQLite3::SQLException: wrong number of arguments to function COUNT(): SELECT COUNT(title, version) FROM "posts"
```

PostgreSQL (`function count(...) does not exist`) and MySQL (`ERROR 1064`, a syntax error) reject it too. A table-qualified star breaks the same way: `Post.joins(:author).select("posts.*").count` runs `SELECT COUNT(posts.*) FROM ...` on 4.1, which SQLite and MySQL reject as a syntax error (PostgreSQL accepts it). A bare `select("*")` is fine: it becomes `COUNT(*)`. It only breaks when something calls `count` with no argument on that relation. `size` on a relation is safe on 4.1, because it calls `count(:all)` when the relation is not loaded. `size` on a `has_many` association that is not loaded is not safe: it calls `count` with no argument, so `has_many :summaries, -> { select("id, title") }` followed by `owner.summaries.size` raises. `empty?` and `any?` run an `exists?` query and are safe.

**Detection Pattern:**
```ruby
Post.select("title, version").count
Post.select(:title, :version).count
Post.select([:title, :version]).count
Post.joins(:author).select("posts.*").count
scope :summary, -> { select("id, title") }  # counted later: Post.summary.count
```

**Fix:**
```ruby
# BEFORE
Post.select("title, version").count

# AFTER
Post.select("title, version").count(:all)
```

On an association with a multi-column `select` in its scope, `owner.summaries.size` breaks the same way, so use `owner.summaries.count(:all)` there.

The select and the `count` are often far apart: a scope or a method returns the relation and a caller, or a spec, counts it. Trace every caller of each flagged relation.

---

#### `RecordNotFound` Messages Quote the Primary Key

**What Changed:**
The message `ActiveRecord::RecordNotFound` carries now quotes the primary key column:

| Call | Rails 4.0 | Rails 4.1 |
|---|---|---|
| `Post.find(999)` | `Couldn't find Post with id=999` | `Couldn't find Post with 'id'=999` |
| `Post.find(1, 999)` | `Couldn't find all Posts with IDs (1, 999) (found 1 results, but was looking for 2)` | `Couldn't find all Posts with 'id': (1, 999) (found 1 results, but was looking for 2)` |

Specs that assert the message text fail. If the app puts `e.message` into an API response, clients see the new wording after the upgrade.

**Detection Pattern:**
```ruby
expect(json["error"]).to eq "Couldn't find Post with id=999"
assert_equal "Couldn't find all Posts with IDs (1, 2)", error.message
```

**Fix:**
```ruby
# BEFORE
expect(json["error"]).to eq "Couldn't find Post with id=999"

# AFTER: assert what the app controls
expect(response).to have_http_status(:not_found)
expect { Post.find(999) }.to raise_error(ActiveRecord::RecordNotFound)

# AFTER: if the text must stay under test, accept both forms while dual booting
expect(json["error"]).to match(/Couldn't find Post with '?id'?=999/)
```

The pattern matches `Couldn't` and `Couldn\'t`, so single-quoted strings are flagged too. The single-id check needs `=` right after the column name, so app-written messages with spaces around `=` are not flagged. An app-written message in exactly the Rails shape is flagged but does not change; skip it.

---

### 🟢 LOW PRIORITY

#### Spring Preloader (New Default)

**What Changed:**
New 4.1 apps generate a `Gemfile` with `gem 'spring'` in `:development`, and a `bin/spring` binstub. Spring keeps the Rails environment in memory between commands.

**Fix (optional):**
```ruby
# Gemfile
group :development do
  gem 'spring'
end
```
Run `bundle exec spring binstub --all` to generate Spring-aware binstubs (`bin/rails`, `bin/rake`, etc.).

---

#### `secrets.yml` (New)

**What Changed:**
Rails 4.1 introduces `config/secrets.yml` as the recommended home for `secret_key_base` and other app secrets, accessible via `Rails.application.secrets`.

**Fix (optional):**
Create `config/secrets.yml`:
```yaml
development:
  secret_key_base: <dev key>
test:
  secret_key_base: <test key>
production:
  secret_key_base: <%= ENV["SECRET_KEY_BASE"] %>
```
Migrate reads from `Rails.application.config.secret_key_base` or custom initializers into `Rails.application.secrets`.

---

#### `render :text` Soft-Deprecated

**What Changed:**
`render :text` was a security-adjacent footgun — it sent `text/html`, so any string with markup would be interpreted by the browser. 4.1 introduces `render :plain`, `render :html`, and `render :body` as precise replacements, and signals that `:text` will be deprecated in a future release.

**Detection Pattern:**
```ruby
render text: "ok"
```

**Fix:**
```ruby
# BEFORE
render text: "ok"

# AFTER — choose based on intent
render plain: "ok"           # Content-Type: text/plain
render html: "<b>ok</b>".html_safe  # Content-Type: text/html (explicit)
render body: "raw"           # no Content-Type header
```

---

#### JSON Encoder: Removed Features

**What Changed:**
The 4.1 JSON encoder rewrite drops three features from `as_json` / `to_json`:
- Circular data-structure detection (previously raised a clear error; now stack-overflows)
- `encode_json(options)` hook (customized encoders must move to `as_json`)
- Option to encode `BigDecimal` objects as numbers instead of strings

**Detection Pattern:**
```ruby
class Money
  def encode_json(options); "..."; end   # no longer called
end

# or code that relied on BigDecimal-as-number
ActiveSupport.encode_big_decimal_as_string = false  # no-op on 4.1
```

**Fix:**
Restore the old encoder as an opt-in gem:
```ruby
# Gemfile
gem 'activesupport-json_encoder'
```
Or migrate `encode_json` implementations into `as_json`, and update clients to parse BigDecimals as strings.

---

#### JSON Gem Isolated from Rails Encoder

**What Changed:**
`JSON.generate` / `JSON.dump` no longer consult Rails' `as_json`. They serialize arbitrary Ruby objects the way the stdlib `json` gem wants — which differs significantly. Use `obj.to_json` when you want Rails semantics.

**Detection Pattern:**
```ruby
JSON.generate(active_record_instance)  # now returns something unexpected
```

**Fix:**
```ruby
# BEFORE (ambiguous intent)
JSON.generate(obj)

# AFTER — Rails semantics (honors as_json)
obj.to_json

# AFTER — stdlib semantics (if you truly wanted that)
JSON.generate(obj.as_json)
```

---

#### Fixtures ERB Evaluated in a Separate Context

**What Changed:**
Each fixture's ERB template now runs in its own isolated context. Helper methods defined in one fixture (`<% def my_helper; end %>`) are no longer visible from another fixture.

**Detection Pattern:**
ERB methods defined at the top of one `.yml` fixture and called from another.

**Fix:**
Hoist helpers into a module and mix it into `ActiveRecord::FixtureSet.context_class`:
```ruby
# test/test_helper.rb
module FixtureFileHelpers
  def file_sha(path)
    Digest::SHA2.hexdigest(File.read(Rails.root.join("test/fixtures", path)))
  end
end

ActiveRecord::FixtureSet.context_class.send :include, FixtureFileHelpers
```

---

#### `ActiveSupport::Callbacks.set_callback` Around-Block Signature

**What Changed:**
The around-callback lambda signature changed from `&block` (yield-style) to a positional `block` argument.

**Detection Pattern:**
```ruby
set_callback :save, :around, ->(r, &block) { stuff; block.call; stuff }
```

**Fix:**
```ruby
# BEFORE
set_callback :save, :around, ->(r, &block) { stuff; block.call; stuff }

# AFTER
set_callback :save, :around, ->(r, block) { stuff; block.call; stuff }
```

Rare — only affects apps that build callbacks dynamically with `set_callback`.

---

#### `ActiveRecord::Migration.check_pending!` Now Redundant in Test Helper

**What Changed:**
`require 'test_help'` now runs pending-migration checks automatically. Explicit calls to `ActiveRecord::Migration.check_pending!` in `test_helper.rb` / `rails_helper.rb` are harmless but unnecessary.

**Fix (optional):**
Remove the now-redundant line:
```ruby
# test/test_helper.rb — can be removed
ActiveRecord::Migration.check_pending!
```

---

## New Features Worth Adopting

- **Action Mailer previews** — subclass `ActionMailer::Preview` in `test/mailers/previews/` and browse at `/rails/mailers`.
- **ActiveRecord enums** — `enum status: [:active, :archived]` generates scopes and predicate methods.
- **Variants** — `request.variant = :tablet` lets views render `show.html+tablet.erb`.
- **`Module#concerning`** — inline concerns inside a class.

---

## Configuration File Changes

Run `bin/rake rails:update` to walk through config changes interactively. See also [RailsDiff 4.0.13 → 4.1.16](http://railsdiff.org/4.0.13/4.1.16) for the exact diff.

Remove if present (no longer does anything):
```ruby
config.active_record.disable_implicit_join_references = true
```

Add to opt into forward-compatible defaults:
```ruby
# config/initializers/cookies_serializer.rb
Rails.application.config.action_dispatch.cookies_serializer = :hybrid

# config/application.rb
config.i18n.available_locales = [:en, ...]  # or set enforce_available_locales = false
```

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-41-upgrade
ruby -v  # 1.9.3+ (2.0+ recommended)
```

### Phase 2: Pre-requisites
1. Fix all current 4.0 deprecation warnings.
2. Audit for `MultiJSON`, dynamic finders, implicit-join `where` strings, and inline-block callbacks that `return`.
3. Audit for PG `json` / `hstore` access with symbol keys.
4. List the locales the app actually uses.

### Phase 3: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 4.1.16'  # pin to the last 4.1 patch

# Only if you rely on it directly
# gem 'multi_json'

# Only if you cannot migrate dynamic finders now
# gem 'activerecord-deprecated_finders'

# Only if you depend on removed JSON encoder features
# gem 'activesupport-json_encoder'

# Required if present: collides with core's ::CacheDigests and aborts every rake task
gem 'cache_digests' unless NextRails.next?

group :development do
  gem 'spring'
end
```

```bash
bundle update rails
```

### Phase 4: Configuration
```bash
bin/rake rails:update
```

Cross-check against [RailsDiff 4.0.13 → 4.1.16](http://railsdiff.org/4.0.13/4.1.16).

### Phase 5: Fix Breaking Changes
1. Replace dynamic finders with `where(...)` / `find_or_create_by(...)` equivalents.
2. Move `return` out of inline callback blocks (or refactor to a method).
3. Replace implicit-join `where` strings with `joins`, `eager_load`, or `references`.
4. Audit PG `json` / `hstore` access: use string keys.
5. Add the cookies serializer initializer (`:hybrid`).
6. Declare `config.i18n.available_locales` or disable enforcement.
7. Swap `post :x, format: :js` for `xhr :post, :x, format: :js` in controller tests.
8. Update `flash.to_hash` callers to use string keys.
9. Review `default_scope`-bearing models; apply `unscope`/`rewhere`.
10. Convert `Relation.compact!` / `Relation.map!` etc. to `to_a` then mutate.
11. Replace `render :text` with `:plain` / `:html` / `:body`.
12. Pin JSON time precision if clients need it (`time_precision = 0`).
13. Remove MultiJSON usage or add it back to the `Gemfile` explicitly.
14. Migrate any `CacheDigests::*` call sites to `ActionView::Digestor` (the Gemfile gate in Phase 3 stops the rake abort; call sites still need rewriting).
15. Replace `.all` on relations and associations with `.to_a` (leave `Model.all` alone).
16. Change `count` to `count(:all)` on relations that carry a multi-column `select`.
17. Port association scopes that call `parent_table_name` and any `join_to` monkeypatch to the 4.1 `JoinDependency` API.
18. Rewrite specs that assert the `RecordNotFound` message text (`with id=` became `with 'id'=`).

### Phase 6: Testing
- Run full test suite.
- Run `bin/rake -T` — it loads every rake task and catches constant collisions the suite and a boot smoke test both miss.
- Exercise controller specs that hit JS endpoints.
- Exercise models with `default_scope` and `after_*` callbacks.
- Verify flash-based UI and any cookie-backed session flows.
- Exercise JSON API endpoints for timestamp format and PG `json` / `hstore` response shape.

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `NameError: uninitialized constant MultiJSON` | "MultiJSON Removed from Rails" — add `gem 'multi_json'` or move to `to_json` / `JSON.parse` |
| `NoMethodError: undefined method 'find_all_by_email'` | "Dynamic Finders Removed" — rewrite as `where(email: email)`, or `activerecord-deprecated_finders` temporarily |
| Query returns zero rows after upgrade | "`default_scope` Chains with Other Scopes" — use `unscope(where: :col)` or `rewhere` |
| `ActionController::InvalidAuthenticityToken` in controller tests on JS endpoints | "CSRF Protection Now Covers GET with JS Responses" — use `xhr :verb, :action` |
| `flash.to_hash.except(:notice)` silently keeps `:notice` | "Flash Message Keys Are Strings" — use `"notice"` |
| `profile.preferences[:theme]` returns `nil` | "PostgreSQL `json` / `hstore` / `array` Columns Return String-Keyed Data" — index with string keys or `store_accessor` |
| `I18n::InvalidLocale` on a request that worked on 4.0 | "I18n Enforces Available Locales" — add the locale to `config.i18n.available_locales` |
| `TypeError: CacheDigests is not a class` from every `rake` task | "`cache_digests` Gem Collides with Core Cache Digests" — `gem 'cache_digests' unless NextRails.next?`, move `CacheDigests::*` calls to `ActionView::Digestor` |
| API clients fail to parse `2024-01-01T00:00:00.000Z` | "`as_json` Millisecond Precision for Time/DateTime/TWZ" — `ActiveSupport::JSON::Encoding.time_precision = 0` or update consumers |
| `NoMethodError: undefined method 'sort!' for #<Post::ActiveRecord_Relation...>` on a `.all` result | "`Relation#all` Returns a Relation, Not an Array": replace `rel.all` with `rel.to_a` |
| `ActiveRecord::StatementInvalid` with `SELECT COUNT(title, version)` or `SELECT COUNT(posts.*)` | "`count` on a Multi-Column `select` Builds Invalid SQL": call `count(:all)` |
| `NoMethodError: undefined method 'parent_table_name' for #<ActiveRecord::Associations::JoinDependency::JoinAssociation...>` | "`JoinDependency` Internals Changed (`parent_table_name`, `join_to`)": build the SQL without `parent_table_name` |
| A join condition added by a `join_to` patch is missing from the SQL | "`JoinDependency` Internals Changed (`parent_table_name`, `join_to`)": port the patch to `join_constraints` |
| Spec expects `Couldn't find Post with id=1` and gets `Couldn't find Post with 'id'=1` | "`RecordNotFound` Messages Quote the Primary Key": assert status and exception class, or match both forms |

---

## Resources

- [Rails 4.1 Release Notes](https://guides.rubyonrails.org/v4.1/4_1_release_notes.html)
- [Upgrading from Rails 4.0 to Rails 4.1 (official)](https://guides.rubyonrails.org/v4.1/upgrading_ruby_on_rails.html#upgrading-from-rails-4-0-to-rails-4-1)
- [RailsDiff 4.0.13 → 4.1.16](http://railsdiff.org/4.0.13/4.1.16)
- [`activerecord-deprecated_finders` gem](https://github.com/rails/activerecord-deprecated_finders)
- [`activesupport-json_encoder` gem](https://github.com/rails/activesupport-json_encoder)
- [Running `rails:update`](http://thomasleecopeland.com/2015/08/06/running-rails-update.html)
