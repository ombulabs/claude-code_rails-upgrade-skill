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

**Pattern:** none (a new opt-in DSL; 5.1 code has nothing to find)

**What Changed:**
New DSL for configuring Content Security Policy. No policy is set by default (`config.content_security_policy` is `nil`), so no header is sent until you define one. The generated `config/initializers/content_security_policy.rb` is fully commented out.

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
`config.content_security_policy` does not exist on 5.1 and raises `NoMethodError`, so while dual booting wrap the block in `if NextRails.next?`.

---

#### default_protect_from_forgery Turned On

**Pattern:** none (a default turned on by `load_defaults 5.2`, not a code shape)

**What Changed:**
`load_defaults 5.2` sets `config.action_controller.default_protect_from_forgery = true`, which runs `protect_from_forgery with: :exception` on `ActionController::Base` itself. `per_form_csrf_tokens` does not change at this hop: `load_defaults 5.0` already turns it on.

**Impact:**
Apps whose `ApplicationController` already calls `protect_from_forgery` see no change. A controller that inherits from `ActionController::Base` directly and never called it (a webhook or callback endpoint, for example) now raises `ActionController::InvalidAuthenticityToken` on POST.

**Fix:**
```ruby
# BEFORE
class WebhooksController < ActionController::Base
end

# AFTER
class WebhooksController < ActionController::Base
  skip_forgery_protection
end
```
`skip_forgery_protection` is new in 5.2; while dual booting use `skip_before_action :verify_authenticity_token, raise: false`, which works on both.

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

#### Cookie Expiry Format Changed

**Pattern:** none (a default turned on by `load_defaults 5.2`, not a code shape)

**What Changed:**
With `config.action_dispatch.use_authenticated_cookie_encryption = true` (set by `load_defaults 5.2`; the framework default is still `false`), encrypted cookies switch from AES-256-CBC to AES-256-GCM, and signed and encrypted cookies carry their expiry inside the value.

**Impact:**
Rails 5.2 still reads the old CBC cookies and rewrites them, so the upgrade itself does not log users out. A server without the flag (5.1, or 5.2 before the flag) cannot read the new cookies, so a rollback or a mixed 5.1/5.2 deploy logs out users whose cookie was rewritten.

**Fix:**
Keep the flag off until no 5.1 server is left, then turn it on:
```ruby
# config/initializers/new_framework_defaults_5_2.rb
Rails.application.config.action_dispatch.use_authenticated_cookie_encryption = false
```

---

### 🟢 LOW PRIORITY

#### Ruby Version Requirement

**Pattern:** none (the minimum Ruby does not change at this hop)

**What Changed:**
The floor does not change: the `rails` 5.2 gemspec requires Ruby `>= 2.2.2`, the same as 5.1, so the Ruby that bundles 5.1 also bundles 5.2. The ceiling rises: the [FastRuby.io compatibility table](https://www.fastruby.io/blog/ruby/rails/versions/compatibility-table.html) lists 5.1 as needing Ruby below 2.6 and 5.2 below 2.7, so 5.2 is the first release that runs on Ruby 2.6. The gemspec sets no upper bound; a Ruby released after 5.2 may need its latest patch release.

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

#### Bootsnap Added to New Apps

**Pattern:** `BOOTSNAP_PRESENCE`

**What Changed:**
The Rails 5.2 app generator adds `gem "bootsnap", require: false` and `require "bootsnap/setup"` in `config/boot.rb` to new apps (`--skip-bootsnap` leaves them out). It is not a dependency of the `rails` gem, so an upgraded app boots and runs its tests without it. Adding it is optional and only speeds up boot.

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

#### ActiveStorage Attachment Changes

**Pattern:** none (a new opt-in framework; 5.1 code has nothing to find)

**What Changed:**
Active Storage is new and becomes the recommended approach for file uploads. The `rails` 5.2 gem depends on `activestorage`, and `require "rails/all"` loads its engine.

**Impact:**
None for an app that does not use it: activestorage 5.2.8.1 only reads `config/storage.yml` when `config.active_storage.service` is set, and only once `ActiveStorage::Blob` loads. If `rails app:update` adds a `config.active_storage.service` line to the environment files, keep the `config/storage.yml` it writes alongside (railties 5.2 `config_when_updating` creates it when missing), or loading a Blob raises "Couldn't find Active Storage configuration". Moving from CarrierWave or Paperclip is optional.

**Fix:**
If adding Active Storage:
```bash
rails active_storage:install
rails db:migrate
```

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
| `ActionController::InvalidAuthenticityToken` on a controller that inherits `ActionController::Base` directly | "default_protect_from_forgery Turned On" — skip forgery protection on that controller |
| Users logged out after a rollback or during a mixed 5.1/5.2 deploy | "Cookie Expiry Format Changed" — keep `use_authenticated_cookie_encryption` off until 5.1 is gone |
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
