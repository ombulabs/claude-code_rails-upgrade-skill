# Rails 3.2 → 4.0 Upgrade Guide

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

4. **Remove `require 'strong_parameters'`** (if backported from Rails 3.2):

The `strong_parameters` gem is built into Rails 4.0. Any `require 'strong_parameters'` calls will fail if the gem is not in the Gemfile.

```ruby
# BEFORE
require 'strong_parameters' # in engine.rb or controller

# AFTER — remove the require entirely
# (strong_parameters is built into Rails 4)
```

If you need dual-boot compatibility during the transition:
```ruby
require 'strong_parameters' unless NextRails.next?
```

---

#### 3. Scopes and Association Options Require Lambda

**What Changed:**
ActiveRecord scopes must use a lambda. Additionally, association options like `:conditions`, `:order`, `:extend`, `:uniq`, and `:finder_sql` that were previously passed as hash options must now be expressed as lambda arguments. This is one of the most impactful changes in a typical Rails 3.2 → 4.0 upgrade.

##### 3a. Scopes

**Detection Pattern:**
```ruby
scope :active, where(active: true)
default_scope where(deleted_at: nil)
default_scope :order => 'created_at ASC'
```

**Fix:**
```ruby
# BEFORE
scope :active, where(active: true)
default_scope where(deleted_at: nil)
default_scope :order => 'created_at ASC'

# AFTER
scope :active, -> { where(active: true) }
default_scope { where(deleted_at: nil) }
default_scope { order('created_at ASC') }
```

##### 3b. Association `:conditions` hash → lambda with `where()`

This is the **most common** change in large codebases. All `:conditions` on `has_many`, `has_one`, and `belongs_to` must move into a lambda.

**Detection Pattern:**
```ruby
has_many :active_items, conditions: { active: true }
has_many :admin_memberships, class_name: "Membership", conditions: { admin: true }
has_one :spouse, class_name: 'Contact', conditions: { relationship: 'Spouse' }
has_many :items, conditions: 'access_type != "public"'
```

**Fix:**
```ruby
# BEFORE
has_many :active_items, conditions: { active: true }
has_many :admin_memberships, class_name: "Membership", conditions: { admin: true }
has_one :spouse, class_name: 'Contact', conditions: { relationship: 'Spouse' }
has_many :items, conditions: 'access_type != "public"'

# AFTER
has_many :active_items, -> { where(active: true) }
has_many :admin_memberships, -> { where(admin: true) }, class_name: "Membership"
has_one :spouse, -> { where(relationship: 'Spouse') }, class_name: 'Contact'
has_many :items, -> { where('access_type != "public"') }
```

##### 3c. Association `:conditions` with proc → lambda with owner parameter

When conditions reference the owning object (common in multi-key associations), the proc must become a lambda that receives the owner as a parameter.

**Detection Pattern:**
```ruby
belongs_to :clinic_patient_link, primary_key: :person_id, foreign_key: :person_id,
  conditions: clinic_id_conditions_proc, extend: MultiKeyAssociation::BelongsTo
has_many :actions, primary_key: :patient_id, foreign_key: :patient_id,
  conditions: proc { ["created_at BETWEEN ? AND ?", start_at, end_at] }
has_one :active_visit, class_name: "Visit",
  conditions: proc { ["created_at >= ?", some_date] }, order: 'created_at DESC'
```

**Fix:**
```ruby
# BEFORE
belongs_to :clinic_patient_link, primary_key: :person_id, foreign_key: :person_id,
  conditions: clinic_id_conditions_proc, extend: MultiKeyAssociation::BelongsTo

# AFTER — this pattern is rare and complex; verify manually
belongs_to :clinic_patient_link, ->(object) {
  where(clinic_id_conditions_proc.call(object)).extending(MultiKeyAssociation::BelongsTo)
}, primary_key: :person_id, foreign_key: :person_id

# BEFORE
has_one :active_visit, class_name: "Visit",
  conditions: proc { ["created_at >= ?", some_date] }, order: 'created_at DESC'

# AFTER
has_one :active_visit, ->(owner) {
  where("created_at >= ?", owner.some_date).order('created_at DESC')
}, class_name: "Visit"
```

##### 3d. Association `:order` → lambda with `order()`

**Detection Pattern:**
```ruby
has_many :items, order: 'position ASC'
has_many :check_ins, order: 'date desc'
has_one :user, order: 'id DESC'
```

**Fix:**
```ruby
# BEFORE
has_many :items, order: 'position ASC'
has_one :user, order: 'id DESC'

# AFTER
has_many :items, -> { order('position ASC') }
has_one :user, -> { order('id DESC') }
```

##### 3e. Association `:extend` → `extending` inside lambda

**Detection Pattern:**
```ruby
has_many :items, :extend => SomeExtension
belongs_to :item, foreign_key: :content_id, extend: ContentExtension
```

**Fix:**
```ruby
# BEFORE
has_many :items, :extend => SomeExtension
belongs_to :item, foreign_key: :content_id, extend: ContentExtension

# AFTER
has_many :items, -> { extending SomeExtension }
belongs_to :item, -> { extending ContentExtension }, foreign_key: :content_id
```

##### 3f. Combined `:conditions` + `:order` + `:extend` → single lambda

When multiple options need to move into the lambda, combine them:

**Fix:**
```ruby
# BEFORE
has_many :flu_shots, class_name: 'Immunization',
  conditions: { immunization_type_id: 4 }, order: 'estimated_date DESC'

# AFTER
has_many :flu_shots, -> { where(immunization_type_id: 4).order('estimated_date DESC') },
  class_name: 'Immunization'
```

##### 3g. `has_many :through` with `:uniq` → lambda

**Detection Pattern:**
```ruby
has_many :items, through: :joins, :uniq => true
has_and_belongs_to_many :groups, uniq: true
```

**Fix:**
```ruby
# BEFORE
has_many :items, through: :joins, :uniq => true
has_and_belongs_to_many :groups, uniq: true

# AFTER (Rails 4.0)
has_many :items, -> { uniq }, through: :joins
has_and_belongs_to_many :groups, -> { distinct }
# Note: uniq was later deprecated in favor of distinct
```

##### 3h. `has_many :through` with `:readonly` option removed

**Detection Pattern:**
```ruby
has_many :items, through: :joins, readonly: false
```

**Fix:**
```ruby
# BEFORE
has_many :items, through: :joins, readonly: false

# AFTER — simply remove the option
has_many :items, through: :joins
```

##### 3i. `:finder_sql` deprecated

**Detection Pattern:**
```ruby
has_many :invitations, :finder_sql => 'SELECT id from items where id is NULL'
```

**Fix:**
`:finder_sql` is deprecated in Rails 4 with no direct replacement. Rewrite using standard associations with scopes or custom query methods:

```ruby
# BEFORE
has_many :invitations, :finder_sql => 'SELECT * FROM invitations WHERE invited_by_id = #{id}'

# AFTER — rewrite as a standard association with a lambda
# Note: the owner must be passed as a parameter, since `id` inside a
# bare lambda refers to the relation scope, not the owning record.
has_many :invitations, ->(owner) { where(invited_by_id: owner.id) }

# OR — if the SQL is too complex for a lambda, use a method
def invitations
  Invitation.find_by_sql(["SELECT * FROM invitations WHERE invited_by_id = ?", id])
end
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

#### 6. `order` and `reorder` Require Arguments

**What Changed:**
Rails 3.2 defined `order` as:

```ruby
def order(*args)
  return self if args.blank?
  # ...
end
```

so a bare `order` or `order()` silently returned the relation unchanged. Rails 4.0 calls
`check_if_method_has_arguments!("order", args)` at the top of both `order` and `reorder`,
so both forms now raise:

```
ArgumentError: The method .order() must contain arguments.
```

This raises at runtime on the call site, not at boot. A report, a background worker or an
admin screen that no spec exercises will pass CI and raise in production.

Only those two forms raise. The guard tests the splat array, so `order(nil)` passes
`[nil]` and `order([])` passes `[[]]`, and neither is `blank?`. Both keep working on 4.0,
and `reorder(nil)` is the documented way to clear a default order, so leave them alone.

The hash form has the same shape of problem. Rails 3.2 had no hash support in `order` at
all: the hash was serialized into the `ORDER BY` string, the database sorted by nothing
usable, and rows came back in whatever order it chose. Rails 4.0 reads a hash strictly as
`{column => direction}` and validates the value against `:asc` / `:desc`, so
`order(events: :start)` raises. It also only accepts columns on the model's own table, so
a sort spanning joined tables cannot be written as a hash on 4.0 at all.

**Detection Pattern:**
```bash
# bare calls: empty parens, or a relation method right after
grep -rnE "\.(order|reorder)(\(\s*\)|\.(first|last|all|to_a|each|find_each|find_in_batches|count|size|length|pluck|ids|limit|offset|where|includes|joins|select|distinct|exists\?|any\?|none\?|empty\?|sum|maximum|minimum|average|take)([^A-Za-z0-9_]|$))" app/ lib/

# hash forms, minus the legitimate direction hashes
grep -rnE "(^|[^A-Za-z0-9_])(re)?order\(\s*\{?\s*:?\w+\s*(:|=>)\s*:\w+" app/ lib/ | grep -vE ":asc|:desc"
```

Reading an `order` association or column (`line_item.order`, `payment.order.total`) is far
more common than the bug, which is why the bare-call grep requires a relation method after
it, and why that method name must end there: without the trailing boundary,
`line_item.order.summary` matches on `sum`. The `:asc` / `:desc` filter is applied to the
whole line, so a line chaining a bad hash and a good one is filtered out with it; split
such chains before trusting a clean run. Multi-line hashes cannot be grepped at all, so
also scan `order(` by hand in query objects and reports. Two shapes stay invisible to both
the grep and the skill's own pattern: a receiverless `order` inside a scope
(`scope :recent, -> { order }`), and a bare call followed by an enumerable method rather
than a relation method (`.order.map { ... }`, `.order.sort_by { ... }`).

**Fix:**
```ruby
# BEFORE
PersonConsentLink.where(person_id: person_id).order.last

# AFTER
PersonConsentLink.where(person_id: person_id).order(:id).last
```

`:id` is not an arbitrary choice for the `.order.last` shape. On 3.2, `last` with no order
calls `reverse_order`, which falls back to `ORDER BY <table>.<primary_key> DESC LIMIT 1`,
so `order(:id).last` reproduces the old result exactly.

```ruby
# BEFORE: raises on 4.0, sorted by nothing on 3.2
.order(
  { patient_groups: :id },
  { checklist_task_items: :month }
)

# AFTER: strings are the only form that can express a sort across joined tables
.order(
  "patient_groups.id",
  "checklist_task_items.month"
)
```

Both fixes are version-agnostic and behave identically on 3.2 and 4.0, so no
`NextRails.next?` branch is needed.

**Expect output to change.** Every one of these call sites except `.order.last` was
sorting by nothing before, so the query has never returned rows in the order the code
claims. Fixing it sorts the result for the first time, which is a behavior change to
review, not just a syntax fix. Check whether any test asserts on the old row order, and
whether downstream code (a CSV export, a paginated screen) depends on it.

For Rails 5.2 and later, a bare string passed to `order` triggers a `Dangerous query
method` warning; wrap it as `Arel.sql("patient_groups.id")`. `Arel.sql` exists since Rails
3.0, so the wrap is safe to add now.

---

### 🟡 MEDIUM PRIORITY

#### 7. `rescue_action` Removed — Use `rescue_from`

**What Changed:**
The `rescue_action` method was removed in Rails 4.0 with no deprecation warning. Use `rescue_from` instead.

**Detection Pattern:**
```ruby
def rescue_action(exception)
```

**Fix:**
```ruby
# BEFORE
def rescue_action(exception)
  case exception
  when *Exceptions::NOT_FOUND
    render_api_error 404, "Not Found"
  else
    super(exception)
  end
end

# AFTER
rescue_from *Exceptions::NOT_FOUND do |exception|
  render_api_error 404, "Not Found"
end
```

Note: `rescue_from` does not support `super`, so re-raise the exception if needed. Avoid `rescue_from Exception` — it catches all exceptions including `SystemExit` and `SignalException`. Use specific exception classes instead.

---

#### 8. Partial Magic Variables Removed

**What Changed:**
In Rails 3.2, rendering a partial automatically defined a local variable named after the partial (set to `nil` if no object/collection was passed). Rails 4.0 only defines this variable when rendering with `collection:` or `object:` options. Partials that rely on the implicit variable will raise `undefined local variable or method` errors.

**Detection Pattern:**
Look for partials that reference their own name as a variable and are rendered without `collection:`, `object:`, or `locals:`:

```ruby
# _something.html.erb references `something` internally
<%= render partial: "something" %>  # No object/collection/locals passed
```

**Fix:**
Pass the variable explicitly via `locals:`:
```ruby
# BEFORE
<%= render partial: "something" %>

# AFTER
<%= render partial: "something", locals: { something: nil } %>
```

No fix is needed when rendering with `collection:` or `object:` — the variable is still defined in those cases.

**Detection Script:**
```ruby
require 'find'

SEARCH_DIR = ARGV[0] || 'app/views'
EXTENSIONS = %w[.html.erb .html.haml .html.slim]

def partial_file?(file)
  base = File.basename(file)
  EXTENSIONS.any? { |ext| base.start_with?('_') && base.end_with?(ext) }
end

def extract_partial_name(file)
  File.basename(file).match(/^_(.*?)\./)[1]
end

Find.find(SEARCH_DIR) do |path|
  next unless File.file?(path) && partial_file?(path)

  partial_name = extract_partial_name(path)
  content = File.read(path)

  if content.match?(/\s#{Regexp.escape(partial_name)}\s/)
    puts "[!] '#{path}' references variable '#{partial_name}' -- verify render calls"
  end
end
```

Results need manual review — only partials rendered without `collection:`, `object:`, or `locals:` require changes.

---

#### 9. `cache_key` Timestamp Format Changed

**What Changed:**
The `cache_timestamp_format` changed from `:number` to `:nsec`, producing longer, more precise cache keys. This can break code that compares or stores cache keys as strings.

```yaml
Rails 3.2: self.cache_timestamp_format = :number
  "orders/33-2024030519440"

Rails 4.0: self.cache_timestamp_format = :nsec
  "orders/34-20240305194606468282921"
```

**Detection Pattern:**
```ruby
# Code that stores or compares cache_key strings
cache_key
cache_timestamp_format
```

**Fix:**
If your code stores cache keys externally (e.g., in Redis, a database, or a background job), those stored keys will no longer match after the upgrade. Either:
1. Invalidate/regenerate stored cache keys after upgrading
2. Or set `self.cache_timestamp_format = :number` on affected models to preserve the old format

**Skill behavior:** When this change is detected, ask the user which approach they prefer — the right choice depends on whether external systems rely on the cache key format.

---

#### 10. Observers Extracted

**What Changed:**
ActiveRecord Observers are no longer included by default.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

---

#### 11. ActionController Sweeper Extracted

**What Changed:**
Sweepers are no longer included.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

Note: This is the same gem as #10 (Observers) — `rails-observers` bundles both Observers and Sweepers.

---

#### 12. Action Caching Extracted

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

#### 13. ActiveResource Extracted

**What Changed:**
ActiveResource is no longer included.

**Fix:**
```ruby
# Gemfile
gem 'activeresource'
```

---

#### 14. Plugins No Longer Supported

**What Changed:**
Rails 4.0 dropped support for `vendor/plugins`.

**Fix:**
- Move plugin code to `lib/` and require it
- Convert to a gem
- Find a gem replacement

---

### 🟢 LOW PRIORITY (but commonly encountered)

#### 15. Fixture Dates Must Be Cast to Strings

**What Changed:**
Rails 4 is stricter about date parsing in YAML fixtures. Dynamic date expressions like `<%= 3.days.ago %>` can produce `invalid date` errors in tests.

**Detection Pattern:**
```yaml
# Fixtures with dynamic dates not cast to strings
accepted_at: <%= 3.days.ago %>
created_at: <%= 1.week.ago %>
```

**Fix:**
```yaml
# BEFORE
accepted_at: <%= 3.days.ago %>

# AFTER
accepted_at: "<%= 3.days.ago.to_s(:db) %>"
```

---

#### 16. `config.eager_load` Required in All Environments

**What Changed:**
Rails 4.0 requires `config.eager_load` to be set in every environment file. Without it, Rails raises an error on boot.

**Fix:**
```ruby
# config/environments/production.rb, preprod.rb
config.eager_load = true

# config/environments/development.rb, test.rb
config.eager_load = false
```

---

#### 17. `config.assets.compress` Removed

**What Changed:**
The `config.assets.compress` directive no longer works in Rails 4. It has been replaced by specific compressor settings.

**Detection Pattern:**
```ruby
config.assets.compress = true
```

**Fix:**
```ruby
# BEFORE
config.assets.compress = true

# AFTER
config.assets.js_compressor = :uglifier
config.assets.css_compressor = :sass
```

---

#### 18. `ActiveSupport::BufferedLogger` Renamed

**What Changed:**
`ActiveSupport::BufferedLogger` was renamed to `ActiveSupport::Logger`.

**Detection Pattern:**
```ruby
ActiveSupport::BufferedLogger.new("path/to/log")
ActiveSupport::BufferedLogger.const_get(level)
```

**Fix:**
```ruby
# BEFORE
ActiveSupport::BufferedLogger.new("path/to/log")
ActiveSupport::BufferedLogger.const_get(Rails.configuration.log_level.to_s.upcase)

# AFTER
ActiveSupport::Logger.new("path/to/log")
Logger.const_get(Rails.configuration.log_level.to_s.upcase)
```

---

#### 19. `config.paths["config/routes"]` Key Changed

**What Changed:**
The config path key for routes changed from `"config/routes"` to `"config/routes.rb"`.

**Detection Pattern:**
```ruby
config.paths["config/routes"]
```

**Fix:**
```ruby
# BEFORE
config.paths["config/routes"].concat(...)

# AFTER
config.paths["config/routes.rb"].concat(...)
```

---

#### 20. `select('distinct ...').pluck` → `.distinct.pluck`

**What Changed:**
Rails 4 introduced the `.distinct` query method as the preferred way to get distinct results.

**Detection Pattern:**
```ruby
relation.select('distinct column_name').pluck(:column_name)
```

**Fix:**
```ruby
# BEFORE
relation.select('distinct assigned_to_id').pluck(:assigned_to_id)

# AFTER
relation.distinct.pluck(:assigned_to_id)
```

---

#### 21. `assign_attributes` Method Signature Changed

**What Changed:**
In Rails 3.2, `assign_attributes` accepted an options hash as a second argument. In Rails 4.0, the options argument was removed and the method was aliased to `attributes=`.

**Detection Pattern:**
```ruby
assign_attributes(new_attributes, options)
```

**Fix:**
```ruby
# BEFORE
assign_attributes(new_attributes, without_protection: true)

# AFTER
assign_attributes(new_attributes)
# If you aliased attributes= to assign_attributes, this is now done by Rails:
# alias attributes= assign_attributes  (built-in in Rails 4)
```

---

#### 22. Validation Callback API Changed

**What Changed:**
The internal method `_run_validation_callbacks` was replaced with `run_callbacks(:validation)`.

**Detection Pattern:**
```ruby
_run_validation_callbacks
```

**Fix:**
```ruby
# BEFORE
_run_validation_callbacks

# AFTER
run_callbacks(:validation)
```

---

#### 23. Test Request Headers API Changed

**What Changed:**
In controller specs, setting request headers changed from `request.env` to `request.headers`.

**Detection Pattern:**
```ruby
request.env.merge!(headers)
```

**Fix:**
```ruby
# BEFORE
request.env.merge!(headers)

# AFTER
request.headers.merge!(headers)
```

---

#### 24. `ActiveRecord::ImmutableRelation` Error

**What Changed:**
In Rails 4, calling methods like `count` on a relation that has already been loaded or modified can raise `ActiveRecord::ImmutableRelation`.

**Detection Pattern:**
```ruby
scope.count('distinct column_name').as_json
```

**Fix:**
Rewrite the query to avoid modifying a frozen relation, e.g., use `.distinct.count` or `.to_a.count`.

---

#### 25. PaperTrail Version Models Require `VersionConcern`

**What Changed:**
If using PaperTrail with custom version models (subclassing `Version`), Rails 4 requires explicitly including `PaperTrail::VersionConcern`.

**Detection Pattern:**
```ruby
class MyVersion < Version
  # Works in Rails 3 without include
end
```

**Fix:**
```ruby
# AFTER
class MyVersion < Version
  include PaperTrail::VersionConcern
end
```

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
gem 'rails-observers'       # If using observers or sweepers
```

```bash
bundle update rails
```

### Phase 3: Fix Breaking Changes
1. Add lambda to all scopes
2. **Migrate all association `:conditions`, `:order`, `:extend`, `:uniq` options to lambda syntax** (this is typically the highest-volume change)
3. Rewrite `:finder_sql` associations as scopes or methods; remove `:readonly` options
4. Update dynamic finders to where/find_by
5. Add HTTP methods to routes
6. Migrate to Strong Parameters and remove `require 'strong_parameters'` calls
7. Replace `rescue_action` with `rescue_from`
8. Fix partials that rely on implicit magic variables (pass `locals:` explicitly)
9. Replace `ActiveSupport::BufferedLogger` with `ActiveSupport::Logger`
10. Cast dates to strings in YAML fixtures (`<%= 3.days.ago.to_s(:db) %>`)

### Phase 4: Configuration
```bash
rails app:update
```

Review changes to:
- `config/application.rb`
- `config/environments/*.rb` — ensure `config.eager_load` is set in every environment
- `config/environments/*.rb` — replace `config.assets.compress` with `config.assets.js_compressor` / `config.assets.css_compressor`
- `config/initializers/*.rb`
- `config/routes.rb` — check for `config.paths["config/routes"]` → `config.paths["config/routes.rb"]`

### Phase 5: Testing
- Run full test suite
- Test forms (Strong Parameters)
- Test all routes
- Test model callbacks (if using observers)
- Update test specs: `request.env.merge!` → `request.headers.merge!`
- Check fixture date errors — cast dynamic dates to strings with `.to_s(:db)`
- Check cache key mismatches if storing keys externally (format changed to `:nsec`)
- Check partials for `undefined local variable` errors from removed magic variables
- Check JSON serialization — Rails 4 may add `id: nil` to serialized objects
- Check error message assertions — SQL quoting changed (parentheses → backticks)

---

## Strong Parameters Migration Checklist

For each model with `attr_accessible`:

- [ ] Create `*_params` method in controller
- [ ] Update `create` action to use params method
- [ ] Update `update` action to use params method
- [ ] Remove `attr_accessible` from model
- [ ] Test create and update flows

---

## Common Issues — Quick Reference

Error → section lookup for the most common errors encountered during this upgrade:

| Error | See |
|-------|-----|
| `ActiveModel::ForbiddenAttributesError` | Section 2 (Strong Parameters) — use `user_params` not `params[:user]` |
| Scope returns wrong results or errors | Section 3a (Scopes) — add lambda |
| `Unknown key: :conditions` | Section 3b (Association conditions) — move to lambda |
| `No route matches` | Section 5 (Routes) — add HTTP method |
| `ArgumentError: The method .order() must contain arguments.` | Section 6 (order/reorder) — name the column, `order(:id)` for `.order.last` |
| `ArgumentError: Direction should be :asc or :desc` | Section 6 (order/reorder) — hash values must be `:asc` / `:desc`; use strings across joins |
| `NoMethodError: undefined method 'rescue_action'` | Section 7 (rescue_action) — use `rescue_from` |
| `undefined local variable or method` in partial | Section 8 (Partial magic variables) — pass `locals:` |
| Cache misses after upgrade | Section 9 (cache_key format) — changed to `:nsec` |
| `invalid date` in fixtures | Section 15 (Fixture dates) — cast with `.to_s(:db)` |
| `eager_load is set to nil` | Section 16 (config.eager_load) — set in all environments |
| `NameError: uninitialized constant ActiveSupport::BufferedLogger` | Section 18 (BufferedLogger) — renamed to `ActiveSupport::Logger` |
| `ActiveRecord::ImmutableRelation` | Section 24 (ImmutableRelation) — use `.distinct.count` |
| Controller specs don't see custom headers | Section 23 (Test headers) — use `request.headers.merge!` |

---

## Resources

- [Rails 4.0 Release Notes](https://guides.rubyonrails.org/4_0_release_notes.html)
- [Strong Parameters Guide](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)
- [RailsDiff 3.2 to 4.0](http://railsdiff.org/3.2.22.5/4.0.13)
