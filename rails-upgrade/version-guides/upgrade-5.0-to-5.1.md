# Rails 5.0 → 5.1 Upgrade Guide

**Ruby Requirement:** 2.2.2+ (2.4+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Rails 5.1 introduces:
- **Encrypted secrets** (`secrets.yml.enc`)
- **Yarn** as default for JavaScript packages
- **Webpack** support via webpacker gem
- **System tests** with Capybara
- **Parameterized mailers**
- **form_with** helper (unifies form_for and form_tag)

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### HashWithIndifferentAccess Indexing Change

**What Changed:**
Non-symbol access in `HashWithIndifferentAccess` returns `nil` for non-existent keys instead of raising errors.

**Detection Pattern:**
```ruby
hash = HashWithIndifferentAccess.new
hash[:missing_key]  # Returns nil
hash[Object.new]    # Behavior changed
```

**Fix:**
Generally transparent. If you relied on specific behavior with non-string/symbol keys, test thoroughly.

---

#### render :text Removed

**Pattern:** `RENDER_TEXT`

**What Changed:**
`render text: 'content'` has been removed.

**Detection Pattern:**
```ruby
render text: 'Hello World'
render text: 'OK', status: 200
```

**Fix:**
```ruby
# BEFORE
render text: 'Hello World'

# AFTER
render plain: 'Hello World'
```

---

#### render :nothing Removed

**Pattern:** `RENDER_NOTHING`

**What Changed:**
`render nothing: true` has been removed.

**Detection Pattern:**
```ruby
render nothing: true
render nothing: true, status: 204
```

**Fix:**
```ruby
# BEFORE
render nothing: true

# AFTER
head :ok
# Or
head :no_content
```

---

#### render :body Default Layout Removed

**What Changed:**
`render body:` no longer renders with a layout by default.

**Detection Pattern:**
```ruby
render body: 'raw content'
```

**Fix:**
If you need a layout:
```ruby
render body: 'raw content', layout: true
```

---

#### redirect_to :back Removed

**Pattern:** `REDIRECT_TO_BACK`

**What Changed:**
`redirect_to :back` was deprecated in Rails 5.0 and **removed** in Rails 5.1. Callers raise at runtime.

**Detection Pattern:**
```ruby
redirect_to :back
redirect_to :back, notice: 'Done!'
```

**Fix:**
```ruby
# BEFORE
redirect_to :back

# AFTER
redirect_back(fallback_location: root_path)
redirect_back(fallback_location: root_path, notice: 'Done!')
```

`redirect_back` requires the `fallback_location:` keyword: it is used when `HTTP_REFERER` is missing, and omitting it raises `ArgumentError: missing keyword: :fallback_location` on every request. `ActionController::RedirectBackError` is the Rails 5.0 `redirect_to :back` symptom, not a `redirect_back` one.

---

### 🟡 MEDIUM PRIORITY

#### Positional Arguments in Process Methods

**Pattern:** `CONTROLLER_TEST_POSITIONAL`

**What Changed:**
Controller test methods now prefer keyword arguments.

**Detection Pattern:**
```ruby
# In controller tests
get :show, { id: 1 }, { user_id: 1 }, { notice: 'Hi' }
post :create, { user: { name: 'Test' } }
```

**Fix:**
```ruby
# BEFORE (positional)
get :show, { id: 1 }, { user_id: 1 }, { notice: 'Hi' }
post :create, { user: { name: 'Test' } }

# AFTER (keyword)
get :show, params: { id: 1 }, session: { user_id: 1 }, flash: { notice: 'Hi' }
post :create, params: { user: { name: 'Test' } }
```

---

#### ActiveRecord.raise_in_transactional_callbacks Removed

**Pattern:** `RAISE_IN_TRANSACTIONAL_CALLBACKS`

**What Changed:**
The configuration option has been removed (was deprecated in 5.0).

**Detection Pattern:**
```ruby
config.active_record.raise_in_transactional_callbacks = true
```

**Fix:**
Remove the configuration line. This is now the default behavior.

---

#### config.serve_static_files and config.static_cache_control Removed

**Pattern:** `SERVE_STATIC_FILES_RENAME`, `STATIC_CACHE_CONTROL_RENAME`

**What Changed:**
Rails 5.0 kept both settings as deprecated aliases that wrote to `config.public_file_server`. Rails 5.1 removes them. Assigning either one no longer raises: the value is stored as an unknown config option and ignored. So `config.serve_static_files = false` stops turning off Rails' static file server (it defaults to on), and `config.static_cache_control` stops adding the `Cache-Control` header to files under `public/`. Reading `config.serve_static_files` without assigning it first raises `NoMethodError`.

**Detection Pattern:**
```ruby
config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?
config.static_cache_control = 'public, max-age=3600'
```

**Fix:**
```ruby
# BEFORE
config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?
config.static_cache_control = 'public, max-age=3600'

# AFTER
config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }
```
The AFTER works on Rails 5.0 too, so make the change before the bump.

---

### 🟢 LOW PRIORITY

#### Ruby Version Requirement

**Pattern:** none (the minimum Ruby does not change at this hop)

**What Changed:**
Nothing. The `rails` 5.1 gemspec requires Ruby `>= 2.2.2`, the same as 5.0, so the Ruby that bundles 5.0 also bundles 5.1. The gemspec sets no upper bound; a Ruby released after 5.1 may need its latest patch release.

**Fix:**
None needed for this hop. Upgrade Ruby as a separate step, not in the same deploy as the Rails bump.

---

## New Features

### Encrypted Secrets

```bash
rails secrets:setup
rails secrets:edit
```

### System Tests

```ruby
# test/system/users_test.rb
class UsersTest < ApplicationSystemTestCase
  test "visiting the index" do
    visit users_url
    assert_selector "h1", text: "Users"
  end
end
```

### form_with Helper

```erb
<%= form_with model: @user do |f| %>
  <%= f.text_field :name %>
  <%= f.submit %>
<% end %>
```

### Parameterized Mailers

```ruby
class InvitationsMailer < ApplicationMailer
  before_action { @inviter, @invitee = params[:inviter], params[:invitee] }

  def invite
    mail(to: @invitee.email)
  end
end

# Usage
InvitationsMailer.with(inviter: @user, invitee: @friend).invite.deliver_later
```

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-51-upgrade
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 5.1.0'
```

```bash
bundle update rails
```

### Phase 3: Fix Breaking Changes
1. Replace `render text:` with `render plain:`
2. Replace `render nothing:` with `head :ok`
3. Replace `redirect_to :back` with `redirect_back`
4. Update controller test syntax to keyword arguments

### Phase 4: Configuration
```bash
rails app:update
```

Update `config/application.rb`:
```ruby
config.load_defaults 5.1
```

### Phase 5: Testing
- Run full test suite
- Test all render calls
- Test redirects
- Verify controller tests pass

---

## Configuration Migration Checklist

- [ ] Remove `render text:` calls
- [ ] Remove `render nothing:` calls
- [ ] Update `redirect_to :back` calls
- [ ] Update controller test syntax
- [ ] Remove deprecated config options
- [ ] Update `load_defaults` to 5.1

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `ActionView::Template::Error: Unknown keyword: text` | "render :text Removed" — `render plain:` |
| `redirect_to :back` raises | "redirect_to :back Removed" — `redirect_back(fallback_location: ...)` |
| `ArgumentError: missing keyword: :fallback_location` | "redirect_to :back Removed" — `redirect_back` requires `fallback_location:` |
| Files under `public/` lose their `Cache-Control` header, or Rails serves them although `serve_static_files = false` | "config.serve_static_files and config.static_cache_control Removed" — move to `config.public_file_server` |

---

## Resources

- [Rails 5.1 Release Notes](https://guides.rubyonrails.org/5_1_release_notes.html)
- [RailsDiff 5.0 to 5.1](http://railsdiff.org/5.0.7/5.1.7)
- [Encrypted Secrets Guide](https://guides.rubyonrails.org/security.html#custom-credentials)
