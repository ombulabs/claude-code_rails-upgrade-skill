# Rails 7.0 → 7.1 Upgrade Guide

**Ruby Requirement:** 2.7.0+ (3.0+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Rails 7.1 introduces:
- **Composite Primary Keys** support
- **Async Queries** for background database operations
- **Dockerfile** generation by default
- **Bun** JavaScript runtime support
- **Enhanced encryption** for Active Record

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### cache_classes → enable_reloading

**What Changed:**
`config.cache_classes` is replaced by `config.enable_reloading` with **inverted** boolean logic.

**Detection Pattern:**
```ruby
# config/environments/development.rb
config.cache_classes = false

# config/environments/production.rb
config.cache_classes = true
```

**Fix:**
```ruby
# BEFORE
config.cache_classes = false  # Don't cache (development)
config.cache_classes = true   # Cache (production)

# AFTER
config.enable_reloading = true   # Enable reloading (development)
config.enable_reloading = false  # Disable reloading (production)
```

**Note:** The boolean is INVERTED:
- `cache_classes = false` → `enable_reloading = true`
- `cache_classes = true` → `enable_reloading = false`

---

#### Force SSL Default in Production

**What Changed:**
`config.force_ssl` is now `true` by default in production.

**Detection Pattern:**
```ruby
# config/environments/production.rb
# If this line is missing or false, you need to check
config.force_ssl = false
```

**Fix:**

If you're NOT using SSL:
```ruby
# config/environments/production.rb
config.force_ssl = false  # Explicitly disable
```

If you ARE using SSL (recommended):
```ruby
# config/environments/production.rb
config.force_ssl = true  # Now the default
```

---

#### preview_path → preview_paths (Mailer)

**What Changed:**
Mailer preview path configuration changed from singular to plural.

**Detection Pattern:**
```ruby
config.action_mailer.preview_path = "#{Rails.root}/spec/mailers/previews"
```

**Fix:**
```ruby
# BEFORE
config.action_mailer.preview_path = "#{Rails.root}/spec/mailers/previews"

# AFTER
config.action_mailer.preview_paths = ["#{Rails.root}/spec/mailers/previews"]
```

---

#### SQLite Database Location Changed

**What Changed:**
SQLite databases now default to `storage/` instead of `db/`.

**Detection Pattern:**
```yaml
# config/database.yml
development:
  database: db/development.sqlite3
```

**Fix:**

Option 1: Keep existing location:
```yaml
# config/database.yml
development:
  database: db/development.sqlite3  # Keep as-is
```

Option 2: Move to new location:
```bash
mkdir -p storage
mv db/*.sqlite3 storage/
```

```yaml
# config/database.yml
development:
  database: storage/development.sqlite3
```

---

#### lib/ Autoloaded by Default

**What Changed:**
Files in `lib/` are now autoloaded by Zeitwerk.

**Detection Pattern:**
Check for naming conflicts in `lib/` folder.

**Fix:**

Configure in `config/application.rb`:
```ruby
# config/application.rb

# Option 1: Configure autoloading (default)
config.autoload_lib(ignore: %w[assets tasks])

# Option 2: Disable lib autoloading
# Remove or comment out the autoload_lib line
```

Ensure files in `lib/` follow Zeitwerk naming:
- `lib/my_module.rb` → `MyModule`
- `lib/my_module/helper.rb` → `MyModule::Helper`

---

#### legacy_connection_handling Removed

**What Changed:**
`config.active_record.legacy_connection_handling` was deprecated in Rails 7.0 and is **completely removed in Rails 7.1**. Setting it will raise an error on boot.

**Detection Pattern:**
```ruby
# config/application.rb or config/environments/*.rb
config.active_record.legacy_connection_handling = false
config.active_record.legacy_connection_handling = true
```

**Fix:**
```ruby
# BEFORE (Rails 7.0) — causes error in 7.1
config.active_record.legacy_connection_handling = false

# AFTER (Rails 7.1) — remove the line entirely
# (delete this configuration — it no longer exists)
```

**Dual-boot compatible:**
```ruby
if NextRails.next?
  # Do nothing — legacy_connection_handling is removed in 7.1
else
  config.active_record.legacy_connection_handling = false
end
```

**Note:** If you still have code relying on the legacy connection handling behavior (per-class connection switching), you must migrate to the new connection handling model using `connects_to` and `connected_to` before upgrading.

---

### 🟡 MEDIUM PRIORITY

#### Query Log Tags Format

**What Changed:**
New query log format options available.

**Detection Pattern:**
```ruby
config.active_record.query_log_tags_enabled = true
```

**Fix:**
```ruby
# config/application.rb
config.active_record.query_log_tags_enabled = true
config.active_record.query_log_tags_format = :sqlcommenter  # or :legacy
```

---

#### Cache Format Version 7.1

**What Changed:**
New cache serialization format available. 7.1 also **deprecates** the 6.1 format and removes it in 7.2.

**This usually warns with no line in the codebase to find.** `cache_format_version` is rarely set explicitly — `config.load_defaults 5.1` / `6.0` / `6.1` implies the 6.1 format. An app that has not yet moved `load_defaults` past 6.1 warns on every boot under 7.1 with nothing to grep for, so a clean detection scan is inconclusive here. Check the app's `load_defaults` value instead.

**Fix:**
```ruby
# Enable after all servers are on 7.1
config.active_support.cache_format_version = 7.1
```

Or resolve it as part of the `load_defaults` bump in Step 7.

**Warning:** Don't enable until ALL servers are upgraded to 7.1. During a rolling deploy, servers still on the old format read new-format entries as misses and vice versa, which can stampede the cache. Deploy the version bump first, then flip the format.

---

#### Content Security Policy Updates

**What Changed:**
CSP configuration syntax updated.

**Detection Pattern:**
Check `config/initializers/content_security_policy.rb`

**Fix:**
Review and update CSP directives as needed.

---

#### Secret Key File Location Changed

**What Changed:**
The location of `secrets.yml.enc` has changed.

**Detection Pattern:**
```
config/secrets.yml.enc
```

**Fix:**
If using encrypted secrets (not credentials), move the file:
```bash
mv config/secrets.yml.enc config/secrets.yml.enc.bak
```

Note: Most applications use `credentials.yml.enc` instead, which is unaffected.

---

#### Active Record inspect Output Changed

**What Changed:**
`ActiveRecord::Core#inspect` now respects `attributes_for_inspect` configuration.

**Detection Pattern:**
```ruby
# Logging or tests that depend on inspect output
puts user.inspect
expect(user.inspect).to include("email")
```

**Fix:**
Configure which attributes appear in inspect:
```ruby
# config/application.rb
config.active_record.attributes_for_inspect = [:id, :name, :email]
# Or show all:
config.active_record.attributes_for_inspect = :all
```

#### `ActiveRecord::Migration.check_pending!` Deprecated

**What Changed:**
`ActiveRecord::Migration.check_pending!` is deprecated in favor of `check_all_pending!`, which loops through all configured databases. It still works in 7.1 but emits a deprecation warning, and is removed entirely in Rails 7.2. Commonly found in `test_helper.rb` or `rails_helper.rb`, but also set up by healthcheck gems (e.g. [`rails-healthcheck`](https://github.com/linqueta/rails-healthcheck)) to run on every `/healthcheck` request.

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

## New Features

### Composite Primary Keys

```ruby
class TravelRoute < ApplicationRecord
  self.primary_key = [:origin, :destination]
end
```

### Async Queries

```ruby
# Load asynchronously
posts = Post.where(published: true).load_async

# Access results (waits if needed)
posts.each { |post| ... }
```

### Dockerfile

New Rails apps include a production-ready Dockerfile:
```bash
rails new myapp  # Includes Dockerfile
```

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-71-upgrade

# Set up dual-boot (optional but recommended)
gem install next_rails
next_rails --init
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
if next?
  gem 'rails', '~> 7.1.0'
else
  gem 'rails', '~> 7.0.0'
end
```

### Phase 3: Fix Breaking Changes
1. Replace `cache_classes` with `enable_reloading`
2. Update `preview_path` to `preview_paths`
3. Review SSL configuration
4. Configure `autoload_lib` if using lib/
5. Remove `config.active_record.legacy_connection_handling` (causes error in 7.1)

### Phase 4: Configuration
```bash
rails app:update
```

Update `config.load_defaults` to 7.1

### Phase 5: Testing
- Run test suite
- Test in development (reloading)
- Test in production mode (caching)
- Verify mailer previews work

---

## Configuration Migration Checklist

- [ ] `cache_classes` → `enable_reloading` (inverted!)
- [ ] `preview_path` → `preview_paths` (array)
- [ ] Review `force_ssl` setting
- [ ] Configure `autoload_lib`
- [ ] Remove `config.active_record.legacy_connection_handling` (raises error in 7.1)
- [ ] Update `load_defaults` to 7.1

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| Code not reloading in development | "cache_classes → enable_reloading" — `enable_reloading = true` in development |
| SSL redirect loop behind a proxy | "Force SSL Default in Production" — let the proxy handle SSL or set `force_ssl = false` |
| Constant not found in `lib/` | "lib/ Autoloaded by Default" — `lib/my_file.rb` must define `MyFile` |
| Boot crashes on `legacy_connection_handling` | "legacy_connection_handling Removed" — delete every occurrence; guard with `NextRails.next?` while dual-booting |

---

## Resources

- [Rails 7.1 Release Notes](https://guides.rubyonrails.org/7_1_release_notes.html)
- [RailsDiff 7.0 to 7.1](http://railsdiff.org/7.0.8/7.1.0)
- [Zeitwerk Documentation](https://github.com/fxn/zeitwerk)
