# Rails 5.1 → 5.2 Upgrade Guide

**Ruby Requirement:** 2.2.2+ (2.5+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Rails 5.2 introduces:
- **Active Storage** for file uploads
- **Credentials** (replaces encrypted secrets)
- **Bootsnap** for faster boot times
- **Content Security Policy** DSL
- **Redis Cache Store** improvements
- **Early Hints** support (HTTP 103)

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### Bootsnap Required for Performance

**Pattern:** `BOOTSNAP_PRESENCE`

**What Changed:**
Rails 5.2 recommends bootsnap for faster boot times.

**Fix:**
```ruby
# Gemfile
gem 'bootsnap', require: false
```

```ruby
# config/boot.rb (add at top)
require 'bootsnap/setup'
```

---

#### Cookie Expiry Format Changed

**What Changed:**
Signed/encrypted cookie expiry timestamps are now embedded in the cookie value.

**Impact:**
Cookies set before upgrading may be reset after upgrading.

**Fix:**
This is handled automatically. Users may need to re-login after upgrade.

For explicit control:
```ruby
# config/initializers/cookies_serializer.rb
Rails.application.config.action_dispatch.use_authenticated_cookie_encryption = true
```

---

#### Active Record attribute_changed? Behavior

**Pattern:** `DIRTY_TRACKING_AFTER_SAVE`

**What Changed:**
`attribute_changed?` and related methods now return `false` after saving, even if the record was changed.

**Detection Pattern:**
```ruby
user.name = 'New Name'
user.save
user.name_changed?  # Was true, now false
```

**Fix:**
Use `saved_changes` or `previous_changes` after save:
```ruby
# BEFORE (checking after save)
user.save
user.name_changed?

# AFTER
user.save
user.saved_change_to_name?
user.saved_changes[:name]
```

---

#### ActiveStorage Attachment Changes

**What Changed:**
Active Storage is new and becomes the recommended approach for file uploads.

**Impact:**
If upgrading from CarrierWave or Paperclip, consider migration (optional).

**Fix:**
If adding Active Storage:
```bash
rails active_storage:install
rails db:migrate
```

---

#### Association class_name Must Be a String

**Pattern:** `CLASS_NAME_CONSTANT`

**What Changed:**
Rails 5.1 warned when an association got a class instead of a string for `class_name:` ("Passing a class to the `class_name` is deprecated"). Rails 5.2 raises `ArgumentError` ("A class was passed to `:class_name` but we are expecting a string.") while building the reflection, so the model fails to load.

**Detection Pattern:**
```ruby
belongs_to :owner, class_name: User
has_many :items, :class_name => Billing::Item
```

**Fix:**
```ruby
# BEFORE
belongs_to :owner, class_name: User

# AFTER
belongs_to :owner, class_name: "User"
```
The string form works on 5.1 too.

---

#### error_on_ignored_order_or_limit Removed

**Pattern:** `ERROR_ON_IGNORED_ORDER_OR_LIMIT`

**What Changed:**
Rails 5.1 renamed the setting to `error_on_ignored_order` and kept the old name as a deprecated alias. Rails 5.2 removes the alias, so `config.active_record.error_on_ignored_order_or_limit = ...` raises `NoMethodError` when Active Record loads.

**Fix:**
```ruby
# BEFORE
config.active_record.error_on_ignored_order_or_limit = true

# AFTER
config.active_record.error_on_ignored_order = true
```
The new name works on 5.1 too.

---

#### ActiveSupport.halt_callback_chains_on_return_false Removed

**Pattern:** `HALT_CALLBACK_CHAINS_ON_RETURN_FALSE`

**What Changed:**
In 5.1 the getter and setter only emitted a deprecation warning and changed nothing. Rails 5.2 removes both, so the line the 5.0 generator wrote into `config/initializers/new_framework_defaults.rb` raises `NoMethodError` at boot. The `config.active_support.` form is skipped silently, but is dead code.

**Fix:**
```ruby
# BEFORE
ActiveSupport.halt_callback_chains_on_return_false = false

# AFTER
# (line removed; halt callbacks with throw :abort)
```
Removing the line works on 5.1 too.

---

#### String if: / unless: Conditions Raise

**Pattern:** `CALLBACK_STRING_CONDITIONS`

**What Changed:**
Rails 5.1 warned when `:if` or `:unless` got a string to evaluate. Rails 5.2 raises `ArgumentError` ("Passing string to be evaluated in :if and :unless conditional options is not supported.") when the callback is defined, so the class fails to load. This covers model callbacks, controller filters, validations and `set_callback`.

**Detection Pattern:**
```ruby
before_save :normalize, if: 'name_changed?'
before_action :authenticate, :if => 'api_request?'
validates :email, presence: true, unless: 'guest?'
```

**Fix:**
```ruby
# BEFORE
before_save :normalize, if: 'name_changed?'
validates :email, presence: true, unless: 'guest? || admin?'

# AFTER
before_save :normalize, if: :name_changed?
validates :email, presence: true, unless: -> { guest? || admin? }
```
Symbols and lambdas work on 5.1 too.

---

#### evented_redis Action Cable Adapter Removed

**Pattern:** `EVENTED_REDIS_ADAPTER`

**What Changed:**
Rails 5.1 deprecated the `evented_redis` adapter. Rails 5.2 deletes it, so `adapter: evented_redis` raises `LoadError` ("Could not load the 'evented_redis' Action Cable pubsub adapter") on the first connection or broadcast. Boot and a test suite on the `async` or `test` adapter still pass, so the error shows up first in the environment that uses it.

**Fix:**
```yaml
# BEFORE (config/cable.yml)
production:
  adapter: evented_redis
  url: <%= ENV["REDIS_URL"] %>

# AFTER
production:
  adapter: redis
  url: <%= ENV["REDIS_URL"] %>
```
The `redis` adapter works on 5.1 too. It needs only the `redis` gem, so `em-hiredis` can go.

---

#### connection.verify! No Longer Takes Arguments

**Pattern:** `CONNECTION_VERIFY_ARGUMENTS`

**What Changed:**
Rails 5.1 ignored any arguments to the connection's `verify!` and warned about them. Rails 5.2 defines `verify!` with no parameters, so `verify!(0)` raises `ArgumentError`. A call in a forking server hook (`config/unicorn.rb`, `config/puma.rb`) is not run by the test suite, so it can first fail in production.

**Fix:**
```ruby
# BEFORE
ActiveRecord::Base.connection.verify!(0)

# AFTER
ActiveRecord::Base.connection.verify!
```
The no-argument call works on 5.1 too.

---

### 🟡 MEDIUM PRIORITY

#### Encrypted Secrets → Credentials

**Pattern:** `SECRETS_USAGE`

**What Changed:**
`secrets.yml.enc` is replaced by `credentials.yml.enc`.

**Detection Pattern:**
```ruby
Rails.application.secrets.secret_key
```

**Fix:**
Migrate to credentials:
```bash
rails credentials:edit
```

```ruby
# BEFORE
Rails.application.secrets.api_key

# AFTER
Rails.application.credentials.api_key
```

---

#### DSL for Content Security Policy

**What Changed:**
New DSL for configuring Content Security Policy.

**Fix:**
Create initializer:
```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.script_src  :self, :https
    policy.style_src   :self, :https, :unsafe_inline
  end
end
```

---

#### force_ssl Now 301 Redirect

**What Changed:**
`force_ssl` now uses 301 (permanent) redirects instead of 302.

**Impact:**
Browsers will cache the redirect. Be careful with staging/development URLs.

**Fix:**
If you need 302:
```ruby
config.ssl_options = { redirect: { status: 302 } }
```

---

#### per_form_csrf_tokens Default Changed

**What Changed:**
`per_form_csrf_tokens` is now enabled by default.

**Detection Pattern:**
```ruby
config.action_controller.per_form_csrf_tokens = false
```

**Impact:**
Forms need fresh CSRF tokens. May affect caching of forms.

**Fix:**
Keep it enabled (more secure) or explicitly disable:
```ruby
config.action_controller.per_form_csrf_tokens = false
```

---

#### Dynamic :controller and :action Route Segments

**Pattern:** `DYNAMIC_ROUTE_SEGMENTS`

**What Changed:**
Nothing new at this hop. A route whose path has a `:controller` or `:action` segment has emitted a deprecation warning since 5.0 ("Using a dynamic :controller segment in a route is deprecated and will be removed in Rails 6.0."), and 5.2 still warns the same way when routes load. Fix it now so the 6.0 hop does not carry it.

**Detection Pattern:**
```ruby
get ':controller(/:action(/:id))'
get 'reports/:action', controller: 'reports'
```

**Fix:**
```ruby
# BEFORE
get 'reports/:action', controller: 'reports'

# AFTER
get 'reports/daily',  to: 'reports#daily'
get 'reports/weekly', to: 'reports#weekly'
```
The explicit routes work on 5.1 too.

---

### 🟢 LOW PRIORITY

#### Ruby Version Requirement

**Pattern:** none (the minimum Ruby does not change at this hop)

**What Changed:**
Nothing. The `rails` 5.2 gemspec requires Ruby `>= 2.2.2`, the same as 5.1, so the Ruby that bundles 5.1 also bundles 5.2. The gemspec sets no upper bound; a Ruby released after 5.2 may need its latest patch release.

**Fix:**
None needed for this hop. Upgrade Ruby as a separate step, not in the same deploy as the Rails bump.

---

#### Erubis Template Handler Removed

**Pattern:** `ERUBIS_HANDLER`

**What Changed:**
Rails 5.1 defaults to Erubi but still ships `ActionView::Template::Handlers::ERB::Erubis` and a deprecated `ActionView::Template::Handlers::Erubis`. Rails 5.2 removes both, so a reference raises `NameError` when the code loads. Direct use of the `erubis` gem is not affected.

**Fix:**
```ruby
# BEFORE
class MyHandler < ActionView::Template::Handlers::Erubis

# AFTER
class MyHandler < ActionView::Template::Handlers::ERB::Erubi
```
`ERB::Erubi` exists on 5.1 too. A subclass that calls Erubis-only methods needs porting to Erubi.

---

#### quoted_id Is Ignored and Removed

**Pattern:** `QUOTED_ID_METHOD`

**What Changed:**
Rails 5.1 quoted any object that defined `quoted_id` by calling it, with a warning ("Defining #quoted_id is deprecated and will be ignored in Rails 5.2."). Rails 5.2 never calls it: a model is quoted by its primary key, so an override is skipped silently, and any other object raises `TypeError` ("can't quote Foo") when used as a bind. `ActiveRecord::Base#quoted_id` itself is removed, so calling it raises `NoMethodError`.

**Detection Pattern:**
```ruby
def quoted_id
"owner_id = #{owner.quoted_id}"
```

**Fix:**
```ruby
# BEFORE
Invoice.where("owner_id = ?", owner)            # owner defines quoted_id
"owner_id = #{owner.quoted_id}"

# AFTER
Invoice.where("owner_id = ?", owner.id)
"owner_id = #{Invoice.connection.quote(owner.id)}"
```
The AFTER works on 5.1 too; then delete `quoted_id`.

---

#### lock! Raises on a Record with Unsaved Changes

**Pattern:** `LOCK_BANG_UNPERSISTED`

**What Changed:**
`lock!` reloads the record, so unsaved changes were always thrown away. Rails 5.1 warned about it; Rails 5.2 raises `RuntimeError` ("Locking a record with unpersisted changes is not supported."). `with_lock` calls `lock!` first, so it raises too.

**Detection Pattern:**
```ruby
account.balance += 10
account.lock!
```

**Fix:**
```ruby
# BEFORE
account.balance += 10
account.with_lock { account.save! }

# AFTER
account.with_lock do
  account.balance += 10
  account.save!
end
```
The AFTER works on 5.1 too.

---

#### secret_token Deprecated

**Pattern:** `LEGACY_SECRET_TOKEN`

**What Changed:**
Rails 5.1 used a `secret_token` from `config/secrets.yml` or `config.secret_token` without comment. Rails 5.2 warns at boot whenever one is set ("`secrets.secret_token` is deprecated in favor of `secret_key_base` and will be removed in Rails 6.0."). `config.secret_key_base` does not warn.

**Fix:**
```ruby
# BEFORE (config/initializers/secret_token.rb)
Rails.application.config.secret_token = ENV["SECRET_TOKEN"]

# AFTER
# (file deleted; secret_key_base set in config/secrets.yml)
```
`config/secrets.yml` works on both versions; credentials and a direct `ENV["SECRET_KEY_BASE"]` read are 5.2 only. While both secrets are set, Rails upgrades cookies signed with the old token; once the token is gone, users whose cookie was never upgraded are logged out once.

---

## New Features

### Active Storage

```ruby
class User < ApplicationRecord
  has_one_attached :avatar
  has_many_attached :documents
end
```

```erb
<%= form.file_field :avatar %>
<%= image_tag @user.avatar %>
```

### Credentials

```bash
# Edit credentials
rails credentials:edit

# Access in code
Rails.application.credentials.aws[:access_key_id]
```

### Content Security Policy

```ruby
# Per-action CSP
class PostsController < ApplicationController
  content_security_policy do |policy|
    policy.script_src :self, :https
  end
end
```

### Redis Cache Store

```ruby
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  expires_in: 1.hour
}
```

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-52-upgrade
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 5.2.0'
gem 'bootsnap', require: false
```

```bash
bundle update rails
```

### Phase 3: Add Bootsnap
```ruby
# config/boot.rb (add after bundler setup)
require 'bootsnap/setup'
```

### Phase 4: Fix Breaking Changes
1. Update attribute dirty tracking usage
2. Migrate secrets to credentials (optional)
3. Review CSRF token settings

### Phase 5: Configuration
```bash
rails app:update
```

Update `config/application.rb`:
```ruby
config.load_defaults 5.2
```

### Phase 6: Testing
- Run full test suite
- Test file uploads (if using Active Storage)
- Test authentication (cookies may reset)
- Verify CSRF protection works

---

## Active Record Dirty Tracking Migration

| Rails 5.1 Method | Rails 5.2 Method |
|-----------------|------------------|
| `attribute_changed?` (after save) | `saved_change_to_attribute?` |
| `attribute_was` (after save) | `attribute_before_last_save` |
| `attribute_change` (after save) | `saved_change_to_attribute` |
| `changed?` (after save) | `saved_changes?` |
| `changes` (after save) | `saved_changes` |

---

## Configuration Migration Checklist

- [ ] Add bootsnap gem and setup
- [ ] Review attribute dirty tracking usage
- [ ] Consider migrating to credentials
- [ ] Review CSRF token settings
- [ ] Set up Content Security Policy (optional)
- [ ] Update `load_defaults` to 5.2

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `attribute_changed?` returns `false` after save | "Active Record attribute_changed? Behavior" — `saved_change_to_attribute?` |
| `ActionController::InvalidAuthenticityToken` on forms that worked on 5.1 | "per_form_csrf_tokens Default Changed" — fresh token per form, or disable the feature |
| Users logged out once after deploy | "Cookie Expiry Format Changed" — expected, one re-authentication |
| `Using a dynamic :controller segment in a route is deprecated` (or `:action`) | "Dynamic :controller and :action Route Segments" — declare each route explicitly |
| `` ArgumentError: A class was passed to `:class_name` but we are expecting a string. `` | "Association class_name Must Be a String" — quote the class name |
| ``NoMethodError: undefined method `error_on_ignored_order_or_limit='`` at boot | "error_on_ignored_order_or_limit Removed" — rename to `error_on_ignored_order` |
| ``NoMethodError: undefined method `halt_callback_chains_on_return_false='`` at boot | "ActiveSupport.halt_callback_chains_on_return_false Removed" — delete the line |

---

## Resources

- [Rails 5.2 Release Notes](https://guides.rubyonrails.org/5_2_release_notes.html)
- [RailsDiff 5.1 to 5.2](http://railsdiff.org/5.1.7/5.2.8)
- [Active Storage Guide](https://guides.rubyonrails.org/active_storage_overview.html)
- [Credentials Guide](https://guides.rubyonrails.org/security.html#custom-credentials)
