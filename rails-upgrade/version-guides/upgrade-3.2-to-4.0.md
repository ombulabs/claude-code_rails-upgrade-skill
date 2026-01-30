# Rails 3.2 → 4.0 Upgrade Guide

**Difficulty:** ⭐⭐⭐ Hard
**Estimated Time:** 1-2 weeks
**Ruby Requirement:** 1.9.3+ (2.0+ recommended)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

---

## Overview

Rails 4.0 is a major release with significant changes:
- **Strong Parameters** replaces attr_accessible
- **Turbolinks** for faster page loads
- **Russian Doll Caching** with cache digests
- **Live Streaming** support
- **Threadsafe by default**

---

## Breaking Changes

### 🔴 HIGH PRIORITY

#### 1. Ruby 1.9.3+ Required

**What Changed:**
Rails 3.2.x is the last version to support Ruby 1.8.7.

**Fix:**
Upgrade Ruby before Rails:
```bash
# Minimum
rbenv install 1.9.3-p551
# Recommended
rbenv install 2.1.10
```

---

#### 2. Strong Parameters (Replaces attr_accessible)

**What Changed:**
Mass assignment protection moved from models to controllers.

**Detection Pattern:**
```ruby
# Models with attr_accessible
attr_accessible :name, :email
attr_protected :admin
```

**Migration Steps:**

1. **Create the params method in your controller:**
```ruby
# app/controllers/users_controller.rb

class UsersController < ApplicationController
  private

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
```

2. **Update controller actions:**
```ruby
# BEFORE
def create
  @user = User.new(params[:user])
end

# AFTER
def create
  @user = User.new(user_params)
end
```

3. **Remove attr_accessible from models:**
```ruby
# BEFORE
class User < ActiveRecord::Base
  attr_accessible :name, :email
end

# AFTER
class User < ActiveRecord::Base
  # No attr_accessible needed
end
```

**Temporary workaround (not recommended):**
```ruby
# Gemfile
gem 'protected_attributes'
```

---

#### 3. Scopes Require Lambda

**What Changed:**
ActiveRecord scopes must use a lambda.

**Detection Pattern:**
```ruby
# Old syntax (broken in Rails 4)
scope :active, where(active: true)
default_scope where(deleted_at: nil)
has_many :posts, order: 'position'
```

**Fix:**
```ruby
# BEFORE
scope :active, where(active: true)
default_scope where(deleted_at: nil)
has_many :posts, order: 'position'

# AFTER
scope :active, -> { where(active: true) }
default_scope { where(deleted_at: nil) }
has_many :posts, -> { order('position') }
```

---

#### 4. Dynamic Finders Deprecated

**What Changed:**
Dynamic finders like `find_all_by_*` are deprecated.

**Detection Pattern:**
```ruby
User.find_all_by_email(email)
User.find_by_name_and_email(name, email)
User.find_or_create_by_email(email)
```

**Fix:**
```ruby
# BEFORE
User.find_all_by_email(email)
User.find_by_name_and_email(name, email)
User.find_or_create_by_email(email)

# AFTER
User.where(email: email)
User.find_by(name: name, email: email)
User.find_or_create_by(email: email)
```

**Temporary workaround:**
```ruby
# Gemfile
gem 'activerecord-deprecated_finders'
```

---

#### 5. Routes Require HTTP Method

**What Changed:**
The `match` method no longer defaults to all HTTP methods.

**Detection Pattern:**
```ruby
# Old syntax
match '/home' => 'home#index'
```

**Fix:**
```ruby
# BEFORE
match '/home' => 'home#index'

# AFTER - Option 1: Specify method
match '/home' => 'home#index', via: :get

# AFTER - Option 2: Use specific method helper
get '/home' => 'home#index'
```

---

### 🟡 MEDIUM PRIORITY

#### 6. Observers Extracted

**What Changed:**
ActiveRecord Observers are no longer included by default.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

---

#### 7. ActionController Sweeper Extracted

**What Changed:**
Sweepers are no longer included.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

---

#### 8. Action Caching Extracted

**What Changed:**
`caches_page` and `caches_action` are no longer included.

**Detection Pattern:**
```ruby
caches_page :public
caches_action :index, :show
```

**Fix:**
```ruby
# Gemfile
gem 'actionpack-action_caching'
```

---

#### 9. ActiveResource Extracted

**What Changed:**
ActiveResource is no longer included.

**Fix:**
```ruby
# Gemfile
gem 'activeresource'
```

---

#### 10. Plugins No Longer Supported

**What Changed:**
Rails 4.0 dropped support for `vendor/plugins`.

**Fix:**
- Move plugin code to `lib/` and require it
- Convert to a gem
- Find a gem replacement

---

## Gem Compatibility Check

Use the rails4_upgrade gem to check compatibility:

```bash
# Add to Gemfile (development group)
gem 'rails4_upgrade'

# Run the check
bundle exec rake rails4:check
```

This outputs a table of gems that need updating.

---

## Migration Steps

### Phase 1: Preparation
```bash
git checkout -b rails-40-upgrade

# Check Ruby version
ruby -v  # Must be 1.9.3+

# Run compatibility check
bundle exec rake rails4:check
```

### Phase 2: Gemfile Updates
```ruby
# Gemfile
gem 'rails', '~> 4.0.0'

# Add if needed
gem 'protected_attributes'  # Temporary for attr_accessible
gem 'rails-observers'       # If using observers
gem 'activerecord-deprecated_finders'  # For old finders
```

```bash
bundle update rails
```

### Phase 3: Fix Breaking Changes
1. Add lambda to all scopes
2. Update dynamic finders to where/find_by
3. Add HTTP methods to routes
4. Migrate to Strong Parameters (can be done incrementally)

### Phase 4: Configuration
```bash
rails app:update
```

Review changes to:
- `config/application.rb`
- `config/environments/*.rb`
- `config/initializers/*.rb`

### Phase 5: Testing
- Run full test suite
- Test forms (Strong Parameters)
- Test all routes
- Test model callbacks (if using observers)

---

## Strong Parameters Migration Checklist

For each model with `attr_accessible`:

- [ ] Create `*_params` method in controller
- [ ] Update `create` action to use params method
- [ ] Update `update` action to use params method
- [ ] Remove `attr_accessible` from model
- [ ] Test create and update flows

---

## Common Issues

### Issue: Mass Assignment Error

**Error:** `ActiveModel::ForbiddenAttributesError`

**Cause:** Using `params[:model]` directly instead of permitted params

**Fix:**
```ruby
# Use the params method
User.new(user_params)  # Not params[:user]
```

### Issue: Scope Not Working

**Error:** Scope returns wrong results or errors

**Cause:** Missing lambda

**Fix:**
```ruby
scope :active, -> { where(active: true) }
```

### Issue: Route Not Found

**Error:** `No route matches`

**Cause:** Missing HTTP method on `match`

**Fix:**
```ruby
get '/path' => 'controller#action'
```

---

## Resources

- [Rails 4.0 Release Notes](https://guides.rubyonrails.org/4_0_release_notes.html)
- [Strong Parameters Guide](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)
- [RailsDiff 3.2 to 4.0](http://railsdiff.org/3.2.22.5/4.0.13)
