# Rails 7.1 → 7.2 Upgrade Guide

**Ruby Requirement:** 3.1.0+ (3.2+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Rails 7.2 introduces:
- **Transaction-aware job enqueuing** by default
- **DevContainers** support
- **Browser version restrictions**
- **Enhanced Active Record connection handling**
- **Progressive Web App (PWA) support**

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### Ruby Version Requirement

**Pattern:** `RUBY_VERSION`

**What Changed:**
Rails 7.2 requires Ruby 3.1.0 or newer: the `rails` 7.2 gemspec sets `required_ruby_version >= 3.1.0`, while 7.1 accepts `>= 2.7.0`. Bundler refuses to install 7.2 on an older Ruby, so this comes before every other change. The gemspec sets no upper bound. When a Ruby released after a Rails version needs a fix, it ships in a later Rails patch release, so on a newer Ruby use the latest 7.2 patch.

**Detection Pattern:**
```ruby
# Gemfile
ruby "3.0.6"
ruby "~> 3.0.6"   # below 3.1
ruby "~> 2.7"     # below 3.0
# not flagged: "~> 3.0" and ">= 2.7.0" still allow 3.1+

# .ruby-version
3.0.6

# .tool-versions
ruby 3.0.6
```

**Fix:**
```ruby
# BEFORE (Gemfile, .ruby-version and .tool-versions agree)
ruby "3.0.6"

# AFTER
ruby "3.3.6"
```

Upgrade Ruby while the app is still on Rails 7.1, as its own step and its own deploy. 7.1 accepts any Ruby from 2.7.0 on, so both sides of the dual boot run on the new Ruby and the Rails bump no longer mixes two changes.

---

#### Transaction-Aware Job Enqueuing

**Pattern:** `TRANSACTION_JOBS`

**What Changed:**
Jobs enqueued inside a database transaction now wait until the transaction commits before being processed.

**Impact:**
```ruby
# This behavior changed!
ActiveRecord::Base.transaction do
  user = User.create!(name: "Test")
  WelcomeEmailJob.perform_later(user)
  # Job now waits for transaction to commit
end
```

**Detection Pattern:**
```ruby
# Models with callbacks that enqueue jobs
after_create :send_welcome_email

def send_welcome_email
  WelcomeEmailJob.perform_later(self)
end
```

**Fix:**

The new behavior is usually correct (ensures data exists before job runs). If you need the old behavior:

```ruby
# Option 1: Use after_commit callback (recommended)
after_commit :send_welcome_email, on: :create

# Option 2: Disable transaction-aware enqueuing globally
# config/application.rb
config.active_job.enqueue_after_transaction_commit = :never
```

---

#### show_exceptions Requires Symbols

**Pattern:** `SHOW_EXCEPTIONS`

**What Changed:**
`config.action_dispatch.show_exceptions` now requires symbol values instead of booleans.

**Detection Pattern:**
```ruby
# config/environments/development.rb
config.action_dispatch.show_exceptions = true

# config/environments/test.rb
config.action_dispatch.show_exceptions = false
```

**Fix:**
```ruby
# BEFORE
config.action_dispatch.show_exceptions = true
config.action_dispatch.show_exceptions = false

# AFTER
config.action_dispatch.show_exceptions = :all       # Was true
config.action_dispatch.show_exceptions = :rescuable # Show only rescuable
config.action_dispatch.show_exceptions = :none      # Was false
```

**Values:**
- `:all` - Show all exceptions (like `true`)
- `:rescuable` - Show only rescuable exceptions
- `:none` - Don't show exceptions (like `false`)

---

#### params Comparison Removed

**Pattern:** `PARAMS_COMPARISON`

**What Changed:**
`ActionController::Parameters` no longer compares equal to `Hash`.

**Detection Pattern:**
```ruby
# In controllers or tests
if params == { key: 'value' }
if params[:user] == some_hash
```

**Fix:**
```ruby
# BEFORE
params == { key: 'value' }
params[:user] == some_hash

# AFTER
params.to_h == { key: 'value' }
params[:user].to_h == some_hash
```

---

#### ActiveRecord.connection Deprecated

**Pattern:** `AR_CONNECTION`

**What Changed:**
`ActiveRecord::Base.connection` is deprecated.

**Detection Pattern:**
```ruby
ActiveRecord::Base.connection.execute("SELECT 1")
ActiveRecord::Base.connection.tables
```

**Fix:**
```ruby
# BEFORE
ActiveRecord::Base.connection.execute("SELECT 1")

# AFTER - Option 1: with_connection block (recommended)
ActiveRecord::Base.with_connection do |conn|
  conn.execute("SELECT 1")
end

# AFTER - Option 2: lease_connection (for longer use)
conn = ActiveRecord::Base.lease_connection
conn.execute("SELECT 1")
# Return connection when done
```

---

#### Rails.application.secrets Removed

**Pattern:** `SECRETS_REMOVED`

**What Changed:**
`Rails.application.secrets` is completely removed.

**Detection Pattern:**
```ruby
Rails.application.secrets.api_key
Rails.application.secrets[:database_password]
```

**Fix:**
Migrate to credentials:

```bash
# Edit credentials
rails credentials:edit

# Or for environment-specific
rails credentials:edit --environment production
```

```ruby
# BEFORE
Rails.application.secrets.api_key

# AFTER
Rails.application.credentials.api_key
Rails.application.credentials.dig(:production, :api_key)
```

---

#### `ActiveRecord::Migration.check_pending!` Removed

**Pattern:** `MIGRATION_CHECK_PENDING_REMOVED`

**What Changed:**
`ActiveRecord::Migration.check_pending!` was deprecated in Rails 7.1 and is removed in Rails 7.2. Calling it raises `NoMethodError`. When invoked from `test_helper.rb` or `rails_helper.rb` it breaks test-suite startup; when configured by a healthcheck gem (e.g. [`rails-healthcheck`](https://github.com/linqueta/rails-healthcheck)) it instead raises at runtime on the `/healthcheck` route in production, even with no pending migration. Use `check_all_pending!`, which checks every configured database.

**Detection Pattern:**
```ruby
# test/test_helper.rb, spec/rails_helper.rb, or config/initializers/*.rb (e.g. healthcheck gems)
ActiveRecord::Migration.check_pending!
```

**Fix:**
```ruby
# BEFORE
ActiveRecord::Migration.check_pending!

# AFTER
ActiveRecord::Migration.check_all_pending!
```

---

### 🟡 MEDIUM PRIORITY

#### serialize Requires Type Parameter

**Pattern:** `SERIALIZE_SYNTAX`

**What Changed:**
`serialize` now requires explicit `type:` or `coder:` parameter.

**Detection Pattern:**
```ruby
class User < ApplicationRecord
  serialize :preferences
end
```

**Fix:**
```ruby
# BEFORE
serialize :preferences

# AFTER
serialize :preferences, type: Hash
serialize :preferences, coder: YAML
serialize :preferences, coder: JSON
```

---

#### fixture_path → fixture_paths

**Pattern:** `FIXTURE_PATH`

**What Changed:**
Singular `fixture_path` deprecated in favor of plural.

**Detection Pattern:**
```ruby
# test/test_helper.rb
self.fixture_path = "#{Rails.root}/test/fixtures"
```

**Fix:**
```ruby
# BEFORE
self.fixture_path = "#{Rails.root}/test/fixtures"

# AFTER
self.fixture_paths = ["#{Rails.root}/test/fixtures"]
```

---

#### query_constraints Deprecated

**Pattern:** `QUERY_CONSTRAINTS`

**What Changed:**
`query_constraints` is deprecated.

**Fix:**
```ruby
# Use foreign_key instead
has_many :posts, foreign_key: [:author_id, :author_type]
```

---

#### Mailer Test args: → params:

**Pattern:** `MAILER_TEST_ARGS`

**What Changed:**
Mailer assertion helpers change `args:` to `params:`.

**Detection Pattern:**
```ruby
# In tests
assert_enqueued_email_with UserMailer, :welcome, args: [user]
```

**Fix:**
```ruby
# BEFORE
assert_enqueued_email_with UserMailer, :welcome, args: [user]

# AFTER
assert_enqueued_email_with UserMailer, :welcome, params: { user: user }
```

---

#### Queue Adapter Must Support `at:` for Testing

**Pattern:** none (test-adapter behavior, found by running the suite)

**What Changed:**
Tests now require queue adapters to support scheduling with `at:` option.

**Detection Pattern:**
```ruby
# test_helper.rb
config.active_job.queue_adapter = :test
```

**Fix:**
If using custom queue adapter in tests, ensure it supports `at:` option for scheduled jobs. The `:test` adapter works correctly out of the box.

---

#### alias_attribute Behavior Change

**Pattern:** none (behavior change, no call shape to match)

**What Changed:**
`alias_attribute` now applies attribute methods to the aliased attribute too.

**Detection Pattern:**
```ruby
class User < ApplicationRecord
  alias_attribute :login, :username
end
```

**Impact:**
If you call `user.login_changed?` or `user.login_was`, they now work correctly. Previously only the original attribute (`username_changed?`) had these methods.

**Note:**
This is generally an improvement, but may affect code that relied on the previous behavior.

---

#### `autoload_lib` Written with `%w[]` in New Apps

**Pattern:** `AUTOLOAD_LIB_SYNTAX`

**What Changed:**
Nothing in behavior. The 7.2 app generator writes `config.autoload_lib(ignore: %w[assets tasks])` where 7.1 wrote `%w(assets tasks)`. Both are the same Ruby array, so an app generated on 7.1 keeps working unchanged. The pattern is `kind: optional` and only records the difference, so `bin/rails app:update` diffs are easier to read.

**Detection Pattern:**
```ruby
# config/application.rb
config.autoload_lib(ignore: %w(assets tasks))
```

**Fix:**
Optional. Switch to `%w[assets tasks]` to match the 7.2 template, or leave it.

---

## New Features

### Browser Version Restrictions

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
end
```

### DevContainers

Rails 7.2 apps can generate DevContainer configuration:
```bash
rails new myapp --devcontainer
```

### PWA Support

Basic PWA files generated by default:
- `app/views/pwa/manifest.json.erb`
- `app/views/pwa/service-worker.js`

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-72-upgrade

# Set up dual-boot
gem install next_rails
next_rails --init
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
if next?
  gem 'rails', '~> 7.2.0'
else
  gem 'rails', '~> 7.1.0'
end
```

### Phase 3: Fix Breaking Changes
1. Upgrade Ruby to 3.1 or newer on Rails 7.1 first, as its own deploy
2. Update `show_exceptions` to use symbols
3. Review jobs enqueued in transactions
4. Migrate secrets to credentials
5. Update `serialize` declarations
6. Fix params comparisons

### Phase 4: Configuration
```bash
rails app:update
```

### Phase 5: Testing
- Run full test suite
- Test job enqueuing behavior
- Verify credentials access
- Check serialized attributes

---

## Configuration Migration Checklist

- [ ] `show_exceptions` boolean → symbol
- [ ] `fixture_path` → `fixture_paths`
- [ ] `serialize` add type/coder
- [ ] Secrets → Credentials migration
- [ ] Review transaction job behavior

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `bundle install` fails: `requires ruby version >= 3.1.0` | "Ruby Version Requirement" — upgrade Ruby on Rails 7.1 first |
| Jobs enqueued inside a transaction never run | "Transaction-Aware Job Enqueuing" — enqueue from `after_commit`, or make sure the transaction commits |
| `ArgumentError: Invalid show_exceptions value` | "show_exceptions Requires Symbols" — `:all`, `:rescuable` or `:none`, not `true` / `false` |
| `NoMethodError: undefined method 'secrets'` | "Rails.application.secrets Removed" — `Rails.application.credentials.key_name` |

---

## Resources

- [Rails 7.2 Release Notes](https://guides.rubyonrails.org/7_2_release_notes.html)
- [RailsDiff 7.1 to 7.2](http://railsdiff.org/7.1.0/7.2.0)
- [Credentials Guide](https://guides.rubyonrails.org/security.html#custom-credentials)
