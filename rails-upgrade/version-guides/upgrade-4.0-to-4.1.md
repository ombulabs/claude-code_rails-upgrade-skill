# Rails 4.0 → 4.1 Upgrade Guide

**Ruby Requirement:** 1.9.3+ (2.0+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs), the official Rails 4.1 upgrade guide, and the Rails 4.1 release notes.**

---

## Overview

Rails 4.1 is a minor release that polishes 4.0 and introduces several new features:
- **Spring** application preloader (new default)
- **`secrets.yml`** for centralized secret/credential management
- **Action Mailer previews** (browser-viewable emails in development)
- **ActiveRecord enums** (`enum status: [...]`)
- **Variants** (`request.variant = :tablet`)
- **`Module#concerning`** API

The breaking changes are smaller than 3.2 → 4.0 but several silently change behavior. MultiJSON removal, dynamic-finder removal, and implicit-join removal are the most common sources of boot/runtime failures.

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### 1. Dynamic Finders Removed

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

#### 2. `return` Inside Inline Callback Blocks

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

#### 3. Implicit Join References Removed

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

### 🟡 MEDIUM PRIORITY

#### 4. MultiJSON Removed from Rails

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

#### 5. `default_scope` Chains with Other Scopes

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

#### 6. `ActiveRecord::Relation` Mutator Methods Removed

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

#### 7. CSRF Protection Now Covers GET with JS Responses

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

See [rails/rails#13345](https://github.com/rails/rails/pull/13345).

---

#### 8. Flash Message Keys Are Strings

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

---

### 🟢 LOW PRIORITY

#### 9. Spring Preloader (New Default)

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

#### 10. `secrets.yml` (New)

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

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-41-upgrade
ruby -v  # 1.9.3+ (2.0+ recommended)
```

### Phase 2: Pre-requisites
1. Fix all current 4.0 deprecation warnings.
2. Audit for `MultiJSON`, dynamic finders, implicit-join `where` strings, and `return false` callbacks.

### Phase 3: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 4.1.0'

# Only if you rely on it directly
# gem 'multi_json'

# Only if you cannot migrate dynamic finders now
# gem 'activerecord-deprecated_finders'

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
2. Replace `return false` in callbacks with a bare `false` expression.
3. Replace implicit-join `where` strings with `joins`, `eager_load`, or `references`.
4. Swap `post :x, format: :js` for `xhr :post, :x, format: :js` in controller tests.
5. Update `flash.to_hash` callers to use string keys.
6. Review `default_scope`-bearing models for broken combinations; apply `unscope`/`rewhere`.
7. Convert `Relation.compact!` / `Relation.map!` etc. to `to_a` then mutate.
8. Remove any `MultiJSON` usage or add it back to the `Gemfile` explicitly.

### Phase 6: Testing
- Run full test suite.
- Exercise controller specs that hit JS endpoints.
- Exercise models with `default_scope` and `after_*` callbacks.
- Verify flash-based UI.

---

## Common Issues

### Issue: App fails to boot with `NameError: uninitialized constant MultiJSON`

**Cause:** MultiJSON no longer pulled in by Rails.

**Fix:** Add `gem 'multi_json'` to the Gemfile, or migrate to `to_json` / `JSON.parse`.

### Issue: `NoMethodError: undefined method 'find_all_by_email'`

**Cause:** Dynamic finders removed.

**Fix:** Rewrite as `where(email: email)` (see §2) or add `gem 'activerecord-deprecated_finders'` temporarily.

### Issue: Query returns zero rows after upgrade

**Cause:** A scope intended to override `default_scope` is now ANDed with it.

**Fix:** Use `unscope(where: :col)` or `rewhere(col: ...)`.

### Issue: Controller tests raise `ActionController::InvalidAuthenticityToken` on JS endpoints

**Cause:** CSRF now applies to GET + JS.

**Fix:** Use `xhr :verb, :action, ...` instead of `verb :action, format: :js`.

### Issue: `flash.to_hash.except(:notice)` silently keeps `:notice`

**Cause:** Flash keys are strings now.

**Fix:** Use `"notice"` instead of `:notice`.

---

## Resources

- [Rails 4.1 Release Notes](https://guides.rubyonrails.org/v4.1/4_1_release_notes.html)
- [Upgrading from Rails 4.0 to Rails 4.1 (official)](https://guides.rubyonrails.org/v4.1/upgrading_ruby_on_rails.html#upgrading-from-rails-4-0-to-rails-4-1)
- [RailsDiff 4.0.13 → 4.1.16](http://railsdiff.org/4.0.13/4.1.16)
- [`activerecord-deprecated_finders` gem](https://github.com/rails/activerecord-deprecated_finders)
- [Running `rails:update`](http://thomasleecopeland.com/2015/08/06/running-rails-update.html)
