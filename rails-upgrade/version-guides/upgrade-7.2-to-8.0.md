# Rails 7.2 → 8.0 Upgrade Guide

**Ruby Requirement:** 3.2.0+ (required)

---

## Overview

Rails 8.0 is a major release with architectural changes:
- **Propshaft** replaces Sprockets as default asset pipeline
- **Solid Cache/Queue/Cable** as database-backed defaults
- **Kamal** for deployment
- **Thruster** for production HTTP serving
- **No more PaaS mode** - designed for containerized deployment

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### Sprockets → Propshaft

**Pattern:** `SPROCKETS`, `ASSET_CONFIG`, `JS_INCLUDE`

**What Changed:**
Propshaft is the new default asset pipeline. Sprockets is no longer included by default.

**Detection Pattern:**
```ruby
# Gemfile
gem 'sprockets-rails'
gem 'sassc-rails'

# Config
config.assets.compile = true
config.assets.digest = true
```

**Migration Options:**

**Option A: Keep Sprockets (Simplest)**
```ruby
# Gemfile - explicitly keep Sprockets
gem 'sprockets-rails'
gem 'sassc-rails'  # if using Sass
```

This is fine! Sprockets still works.

**Option B: Migrate to Propshaft (Recommended for new features)**
```ruby
# Gemfile
gem 'propshaft'

# Remove
# gem 'sprockets-rails'
# gem 'sassc-rails'
```

**Propshaft Differences:**
- No asset compilation transforms
- Direct serving from `app/assets/`
- Use `cssbundling-rails` for Sass
- Simpler configuration

```ruby
# Remove these Sprockets configs
# config.assets.compile
# config.assets.digest
# config.assets.debug
```

**Asset Helpers:**
```erb
<!-- Both work the same -->
<%= stylesheet_link_tag 'application' %>
<%= javascript_include_tag 'application' %>
```

---

#### assume_ssl Configuration

**Pattern:** `ASSUME_SSL`

**What Changed:**
Rails 8.0 introduces `config.assume_ssl` for apps behind SSL-terminating proxies.

**Detection Pattern:**
```ruby
# config/environments/production.rb
config.force_ssl = true
```

**Fix:**
```ruby
# config/environments/production.rb
config.force_ssl = true
config.assume_ssl = true  # Add this for load balancers
```

This prevents SSL redirect loops when behind a proxy.

---

#### sqlite3_deprecated_warning Removed

**Pattern:** `SQLITE3_WARNING`

**What Changed:**
The `sqlite3_deprecated_warning` configuration option is removed.

**Detection Pattern:**
```ruby
config.active_record.sqlite3_deprecated_warning = false
```

**Fix:**
Remove this line from your configuration files.

---

#### Ruby 3.2+ Strictly Required

**Pattern:** `RUBY_VERSION`

**What Changed:**
Rails 8.0 requires Ruby 3.2.0 or newer: the `rails` 8.0 gemspec sets `required_ruby_version >= 3.2.0`, while 7.2 accepts `>= 3.1.0`. Bundler refuses to install 8.0 on an older Ruby, so upgrade Ruby first, while the app is still on Rails 7.2, as its own deploy. The gemspec sets no upper bound; a Ruby released after a Rails version may need that version's latest patch release.

**Detection Pattern:**
```ruby
# Gemfile
ruby "3.1.6"

# .ruby-version
3.1.6

# .tool-versions
ruby 3.1.6
```

**Fix:**
```bash
rbenv install 3.3.0
rbenv local 3.3.0
```

---

#### `query_constraints:` association option removed (composite foreign keys)

**Pattern:** `QUERY_CONSTRAINTS_OPTION`

**What Changed:**
Rails 8.0 **removes** the `query_constraints:` option on associations (`belongs_to`/`has_many`/etc.). It was deprecated in Rails 7.2 and now raises `ActiveRecord::ConfigurationError` **at class load**, so the app fails to boot.

**Detection Pattern:**
```ruby
# app/models/*.rb
belongs_to :activity, query_constraints: [:activity_id, :school_id]
```

**Error (Rails 8.0):**
```
ActiveRecord::ConfigurationError:
  Setting `query_constraints:` option on `ActivityParticipant.belongs_to :activity`
  is not allowed. To get the same behavior, use the `foreign_key` option instead.
```

**Fix — pass the composite key as an `Array` to `foreign_key:`:**
```ruby
# BEFORE (7.2 deprecation → 8.0 raises)
belongs_to :activity, query_constraints: [:activity_id, :school_id]

# AFTER (works on Rails 7.2 AND 8.0)
belongs_to :activity, foreign_key: [:activity_id, :school_id]
```

This is **behavior-preserving and version-agnostic**: when `foreign_key:` is given an `Array`, ActiveRecord internally maps it back to `query_constraints` (in both 7.2 and 8.0), so no dual-boot (`NextRails.next?`) branch is needed. On 7.2 it also silences the deprecation warning.
  
> ⚠️ Not in the official Rails Upgrade Guide or the 7.2/8.0 release notes — documented only in `activerecord` `CHANGELOG.md` (7.2) and the source. A **boot smoke test** (`bin/rails runner`) is the reliable way to catch it.

---

#### `enum` Keyword-Arguments Form Removed

**Pattern:** `ENUM_KWARGS`

**What Changed:**
Rails 7.2 accepted `enum status: { ... }, _prefix: true` with a deprecation warning. Rails 8.0 makes the enum name a required positional argument (`def enum(name, values = nil, **options)`), so the keyword form raises `ArgumentError: wrong number of arguments (given 0, expected 1..2)` when the model loads.

**Detection Pattern:**
```ruby
# app/models/*.rb
enum status: { active: 0, archived: 1 }, _prefix: true
```

**Fix:**
```ruby
# BEFORE
enum status: { active: 0, archived: 1 }, _prefix: true

# AFTER
enum :status, { active: 0, archived: 1 }, prefix: true
```
The AFTER works on 7.2 too. Drop the leading underscore from the options (`_prefix`, `_suffix`, `_scopes`, `_default`): the positional form raises `ArgumentError: invalid option(s)` on both versions if it is kept.

---

### 🟡 MEDIUM PRIORITY

#### Multi-Database Configuration for Solid Gems

**Pattern:** `DB_POOL`

**What Changed:**
Rails 8.0 changes nothing in how `database.yml` is read: a single `production:` block and the `pool:` key work as they did on 7.2. What changed is the 8.0 app generator, which splits `production:` into `primary`, `cache`, `queue` and `cable` databases, each with its own `migrations_paths`, for Solid Cache, Solid Queue and Solid Cable. Change the file only when adopting those gems.

**Detection Pattern:**
```yaml
# config/database.yml
production:
  adapter: postgresql
  database: myapp_production
  pool: 5
```

**Fix (only if adopting Solid gems):**
```yaml
# BEFORE
production:
  <<: *default
  database: myapp_production

# AFTER (same shape as the 8.0 generator)
production:
  primary: &primary_production
    <<: *default
    database: myapp_production
  cache:
    <<: *primary_production
    database: myapp_production_cache
    migrations_paths: db/cache_migrate
  queue:
    <<: *primary_production
    database: myapp_production_queue
    migrations_paths: db/queue_migrate
  cable:
    <<: *primary_production
    database: myapp_production_cable
    migrations_paths: db/cable_migrate
```
The AFTER works on 7.2 too. If the app keeps Redis, Sidekiq or its current cache store, leave `database.yml` as it is.

---

#### Solid Cache (Optional)

**Pattern:** `REDIS_CACHE`

**What Changed:**
Rails 8.0 defaults to Solid Cache for caching (database-backed).

**Detection Pattern:**
```ruby
config.cache_store = :redis_cache_store
config.cache_store = :mem_cache_store
```

**Options:**

**Keep Redis/Memcached:**
```ruby
# No change needed - your existing setup still works
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

**Switch to Solid Cache:**
```ruby
# Gemfile
gem 'solid_cache'

# Install
rails solid_cache:install

# Config
config.cache_store = :solid_cache_store
```

---

#### Solid Queue (Optional)

**Pattern:** `SIDEKIQ_QUEUE`

**What Changed:**
Rails 8.0 defaults to Solid Queue for background jobs (database-backed).

**Detection Pattern:**
```ruby
config.active_job.queue_adapter = :sidekiq
config.active_job.queue_adapter = :async
```

**Options:**

**Keep Sidekiq:**
```ruby
# No change needed
config.active_job.queue_adapter = :sidekiq
```

**Switch to Solid Queue:**
```ruby
# Gemfile
gem 'solid_queue'

# Install
rails solid_queue:install

# Config
config.active_job.queue_adapter = :solid_queue

# Start the supervisor; without it jobs stay pending
bin/jobs
```

---

#### Solid Cable (Optional)

**Pattern:** `CABLE_REDIS`

**What Changed:**
Rails 8.0 defaults to Solid Cable for WebSockets (database-backed).

**Detection Pattern:**
```yaml
# config/cable.yml
production:
  adapter: redis
```

**Options:**

**Keep Redis:**
```yaml
# No change needed
production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") %>
```

**Switch to Solid Cable:**
```yaml
production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
```

---

#### Docker/Thruster for Production

**Pattern:** `THRUSTER`

**What Changed:**
Rails 8.0 apps include Dockerfile and Thruster gem.

**Fix:**
If using Docker, add:
```ruby
# Gemfile
gem 'thruster'
```

Thruster provides:
- HTTP/2 support
- Asset compression
- Static file serving

---

#### Kamal Deployment

**Pattern:** `KAMAL_DEPLOY`

**What Changed:**
Rails 8.0 includes Kamal configuration for deployment.

**New Files:**
- `config/deploy.yml`
- `.kamal/` directory

**If not using Kamal**, you can ignore or delete these files.

---

#### to_time Preserves the Full Timezone

**Pattern:** `TO_TIME_PRESERVES_TIMEZONE`, `TO_TIME_PRESERVES_TIMEZONE_ASSIGNMENT`

**What Changed:**
Rails 8.0 warns whenever `to_time_preserves_timezone` is set to anything other than `:zone`, because 8.1 makes `:zone` the only behavior. `load_defaults 8.0` sets `:zone`. `load_defaults` 5.0 to 7.2 leave it at `:offset` on 8.0 (7.2 stores the same setting as `true`), so an app still on an older `load_defaults` warns at boot:

```
DEPRECATION WARNING: `to_time` will always preserve the full timezone rather than offset of the receiver in Rails 8.1.
To opt in to the new behavior, set `config.active_support.to_time_preserves_timezone = :zone`.
```

An app with no `load_defaults` line gets `false` and a different message (`... preserve the receiver timezone rather than system local time in Rails 8.1`).

An explicit assignment keeps warning even after `load_defaults 8.0`, because the setter itself warns. The usual source is the forward-compat initializer the Rails 4.2 generator added, `config/initializers/to_time_preserves_timezone.rb`.

**Detection Pattern:**
```ruby
# config/application.rb
config.load_defaults 7.2

# config/initializers/to_time_preserves_timezone.rb (or any file under config/)
ActiveSupport.to_time_preserves_timezone = true
config.active_support.to_time_preserves_timezone = :offset
```

**Fix:**
```ruby
# BEFORE
# config/initializers/to_time_preserves_timezone.rb
ActiveSupport.to_time_preserves_timezone = true

# AFTER
# Delete the file. load_defaults 5.0+ already sets this on 7.2, and on 8.0
# the after_initialize hook overwrites a direct assignment with the config value.
```

```ruby
# BEFORE (warns on 8.0)
# config/application.rb
config.load_defaults 7.2

# AFTER (opts in to this one setting; 7.2 accepts :zone, so no NextRails.next? branch)
config.load_defaults 7.2
config.active_support.to_time_preserves_timezone = :zone
```

This flag is the default fix because it targets this one deprecation. Aligning `load_defaults` to 8.0 also removes the warning, but it flips every other 8.0 default at the same time, so treat it as the follow-up in Workflow 12, which moves `load_defaults` one setting at a time after the upgrade ships. Once `load_defaults 8.0` is in place, the explicit line is redundant: delete it then, because 8.1 deprecates the setting itself.

On 8.0 `:zone` is a behavior change: `to_time` returns a Time that carries the receiver's full zone (DST-aware) instead of a fixed UTC offset. Run the suite after adding the line.

---

### 🟢 LOW PRIORITY

#### read_encrypted_secrets Removed

**Pattern:** `READ_ENCRYPTED_SECRETS`

**What Changed:**
Rails 8.0 removes `config.read_encrypted_secrets`. The setting drove the legacy `config/secrets.yml.enc` feature, already dead since 7.2 removed `Rails.application.secrets`. The assignment does not raise on 8.0: it is stored with no effect and no warning. Only the 7.2 side of a dual boot warns, which clutters boot and `assets:precompile` logs:

```
DEPRECATION WARNING: 'config.read_encrypted_secrets=' is deprecated and will be removed in Rails 8.0.
```

Reading `config.read_encrypted_secrets` without assigning it first raises `NoMethodError` on 8.0.

**Detection Pattern:**
```ruby
# config/environments/production.rb
config.read_encrypted_secrets = true
```

**Fix:**
```ruby
# BEFORE
# Attempt to read encrypted secrets from `config/secrets.yml.enc`.
config.read_encrypted_secrets = true

# AFTER
# (line and comment deleted; safe on both 7.2 and 8.0)
```

If the app still keeps secrets in `config/secrets.yml.enc`, move them to credentials (`bin/rails credentials:edit`) first.

---

#### `SCHEMA_CACHE` Environment Variable No Longer Read

**Pattern:** `ENV_SCHEMA_CACHE`

**What Changed:**
Rails 7.1 used `ENV["SCHEMA_CACHE"]` as the path for `db:schema:cache:dump` and the schema cache load. Rails 7.2 already ignores it and only warns; 8.0 removes the warning too, so the variable is ignored silently and the default `db/schema_cache.yml` (or `db/<name>_schema_cache.yml`) is used. Nothing raises: a script or CI step that sets it has been using the default path since 7.2.

```
DEPRECATION WARNING: Setting `ENV["SCHEMA_CACHE"]` is deprecated and will be removed in Rails 8.0. Configure the `:schema_cache_path` in the database configuration instead.
```

**Detection Pattern:**
```ruby
ENV["SCHEMA_CACHE"] = "tmp/schema_cache.yml"
# CI step or script
SCHEMA_CACHE=tmp/schema_cache.yml bin/rails db:schema:cache:dump
```

**Fix:**
```yaml
# BEFORE
SCHEMA_CACHE=tmp/schema_cache.yml bin/rails db:schema:cache:dump

# AFTER
# config/database.yml
production:
  <<: *default
  schema_cache_path: tmp/schema_cache.yml
```
The AFTER works on 7.2 too.

---

## Solid Gems Decision Guide

| Current Setup | Recommendation |
|--------------|----------------|
| Redis for cache/jobs/cable | Keep Redis - simpler to maintain |
| Sidekiq with complex workflows | Keep Sidekiq |
| Simple background jobs | Consider Solid Queue |
| Need real-time WebSockets | Keep Redis for Cable |
| Want simpler infrastructure | Use Solid gems |
| Heroku/PaaS deployment | Solid gems or Redis add-on |
| Self-hosted/Docker | Either works well |

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-80-upgrade

# Verify Ruby version
ruby -v  # Should be 3.1+
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 8.0.0'

# Choose asset pipeline:
gem 'propshaft'  # New default
# OR
gem 'sprockets-rails'  # Keep existing

# Optional Solid gems (only if migrating):
# gem 'solid_cache'
# gem 'solid_queue'
# gem 'solid_cable'
```

```bash
bundle update rails
```

### Phase 3: Asset Pipeline Decision

**If keeping Sprockets:**
```ruby
# Gemfile
gem 'sprockets-rails'
```
No other changes needed!

**If migrating to Propshaft:**
1. Remove Sprockets-specific configs
2. Update asset structure if needed
3. Use cssbundling-rails for Sass

### Phase 4: Configuration
```bash
rails app:update
```

Update `config/application.rb`:
```ruby
config.load_defaults 8.0
```

Add to production.rb:
```ruby
config.assume_ssl = true
```

### Phase 5: Testing
- Verify assets load correctly
- Test caching if using Solid Cache
- Test background jobs
- Test WebSockets if applicable

---

## Propshaft Migration Checklist

- [ ] Remove `sprockets-rails` from Gemfile
- [ ] Add `propshaft` to Gemfile
- [ ] Remove `config.assets.*` from environment files
- [ ] Verify assets serve correctly
- [ ] If using Sass, add `cssbundling-rails`
- [ ] Update asset precompilation in deployment

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| 404 for CSS / JS files | "Sprockets → Propshaft" — Propshaft needs no config, files go in `app/assets/`; Sprockets needs `gem 'sprockets-rails'` |
| `ERR_TOO_MANY_REDIRECTS` | "assume_ssl Configuration" — `config.assume_ssl = true` behind a proxy |
| Solid Queue jobs stuck in pending | "Solid Queue (Optional)" — start the supervisor, `bin/jobs` |
| `` DEPRECATION WARNING: `to_time` will always preserve the full timezone `` (or `receiver timezone`) at boot | "to_time Preserves the Full Timezone": set `to_time_preserves_timezone = :zone`; `load_defaults 8.0` later |
| `DEPRECATION WARNING: 'config.read_encrypted_secrets=' is deprecated` on the 7.2 side | "read_encrypted_secrets Removed": delete the line |
| `ArgumentError: wrong number of arguments (given 0, expected 1..2)` from an `enum` line | "`enum` Keyword-Arguments Form Removed": `enum :status, { ... }, prefix: true` |
| `` DEPRECATION WARNING: Setting `ENV["SCHEMA_CACHE"]` is deprecated `` on the 7.2 side | "`SCHEMA_CACHE` Environment Variable No Longer Read": set `schema_cache_path:` in `database.yml` |

---

## Gem Compatibility

| Gem | Minimum Version | Notes |
|-----|-----------------|-------|
| devise | 4.9.0 | Works well |
| sidekiq | 7.0.0 | Keep if using |
| rspec-rails | 6.0.0 | Update recommended |
| capybara | 3.39.0 | Works well |
| webmock | 3.19.0 | Works well |

---

## Files Changed by app:update

| File | Change |
|------|--------|
| Gemfile | Rails version, Propshaft |
| config/application.rb | load_defaults 8.0 |
| config/environments/production.rb | assume_ssl, cache config |
| config/database.yml | Multi-database structure |
| Dockerfile | New file |
| config/deploy.yml | New file (Kamal) |
| bin/jobs | New file (Solid Queue) |

---

## Resources

- [Rails 8.0 Release Notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [Propshaft Documentation](https://github.com/rails/propshaft)
- [Solid Cache](https://github.com/rails/solid_cache)
- [Solid Queue](https://github.com/rails/solid_queue)
- [Kamal Documentation](https://kamal-deploy.org)
