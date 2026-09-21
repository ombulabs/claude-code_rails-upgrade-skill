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

#### Ruby 1.9.3+ Required

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

#### Strong Parameters (Replaces attr_accessible)

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

#### Scopes and Association Options Require Lambda

**What Changed:**
ActiveRecord scopes must use a lambda. Additionally, association options like `:conditions`, `:order`, `:extend`, `:uniq`, and `:finder_sql` that were previously passed as hash options must now be expressed as lambda arguments. This is one of the most impactful changes in a typical Rails 3.2 → 4.0 upgrade.

##### Scopes

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

##### Association `:conditions` hash → lambda with `where()`

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

##### Association `:conditions` with proc → lambda with owner parameter

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

##### Association `:order` → lambda with `order()`

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

##### Association `:extend` → `extending` inside lambda

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

##### Combined `:conditions` + `:order` + `:extend` → single lambda

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

##### `has_many :through` with `:uniq` → lambda

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

##### `has_many :through` with `:readonly` option removed

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

##### `:finder_sql` deprecated

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

#### Dynamic Finders Deprecated

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

#### Routes Require HTTP Method

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

#### Remote Forms Stop Embedding the CSRF Token

**What Changed:**
`config.action_view.embed_authenticity_token_in_remote_forms` defaults to `false` in
Rails 4.0 (it was `true` in 3.2), so `remote: true` forms no longer render the hidden
`authenticity_token` field. From then on the token reaches the server only as the
`X-CSRF-Token` header that rails-ujs sets from the `csrf-token` meta tag, which means
the form is protected only while UJS is the thing submitting it. Any other submit path
(a hand-rolled `fetch` posting a `FormData` built from the form, an iframe upload, a
form serialized by a plugin) posts with no CSRF token at all. With a bare
`protect_from_forgery`, Rails 4.0 does not raise: the `:null_session` strategy empties
the session, so the request arrives without its user and fails somewhere further in, or
silently does nothing.

Rails made the change for fragment caching. The token is per-session, so the hidden
field makes the form's HTML unique per user: cache that fragment and you either serve
one user's token to everybody or you cannot cache it at all. Remote forms were assumed
to always be submitted by UJS as an XHR, which in a real application they are not. The
[Rails CHANGELOG entry for the flip](https://github.com/rails/rails/commit/128cfbdf4d316a544a76e5c58dbeac153f3d4e36)
names the escape hatch: set the config to `true`, or pass `:authenticity_token => true`
per form. Later Rails
[softened the default to `nil`](https://github.com/rails/rails/commit/6309b85100dd2b55c716ee4a4e9cbd3da2dc0617),
meaning "let the form helper decide", so pinning it back is not fighting the
framework's direction.

Nothing warns, and no test catches it. The Rails-side change is the *absence* of a
config line, so no grep can see it; the failure is browser-only, so `rack_test` never
runs the JavaScript that does the submitting; and `allow_forgery_protection` is off in
the test environment, so no token is rendered in tests either way.

**Detection Pattern:**
```bash
# remote forms whose submit path needs auditing, both hash syntaxes
grep -rnE "remote:\s*true|:remote\s*=>\s*true" app/views/ app/helpers/

# confirm the app never pinned the config
grep -rn "embed_authenticity_token_in_remote_forms" config/

# true on the current boot and false on the next confirms it relies on the default
bundle exec rails runner 'puts ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms.inspect'
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner 'puts ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms.inspect'
```

Remote `link_to` / `button_to` links are safe: UJS builds their form and token itself.
The grep is a list of forms to audit, not a list of forms to change.

**Fix:**
```ruby
# config/application.rb
# Pinned to the Rails 3.2 default: Rails 4.0 stops embedding the token in
# remote forms, leaving custom JS submit paths with no CSRF token at all.
config.action_view.embed_authenticity_token_in_remote_forms = true
```

Valid on both 3.2 and 4.x, so no `NextRails.next?` branch. The pin is a backstop, not
the whole fix. Any `fetch` / `XMLHttpRequest` that posts form data itself still needs
the token set explicitly:

```javascript
fetch(url, {
  method: "POST",
  body: new FormData(form),
  headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content }
})
```

Check that the layout renders `csrf_meta_tags`. Without it there is no token to read,
and UJS has nothing to send either.

**Catch it in the suite:** one example with forgery protection switched on. It goes red
on the next boot and green after the pin, and flipping the flag is the whole trick,
since the test environment disables it:

```ruby
around do |example|
  was_protecting = ActionController::Base.allow_forgery_protection
  ActionController::Base.allow_forgery_protection = true
  example.run
  ActionController::Base.allow_forgery_protection = was_protecting
end

it "embeds an authenticity token in the remote form" do
  visit edit_settings_path

  expect(page).to have_css("form.opt-in-form input[name='authenticity_token']", visible: :all)
end
```

Related: **4.2** masks the token per request (`CSRF_TOKEN_MASKING`), so any client that
caches a token across requests breaks there. **7.0** replaces UJS with Turbo and the
submit path changes again.

---

#### `order` and `reorder` Require Arguments

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

#### `rescue_action` Removed — Use `rescue_from`

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

#### Partial Magic Variables Removed

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

#### `cache_key` Timestamp Format Changed

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

#### Observers Extracted

**What Changed:**
ActiveRecord Observers are no longer included by default.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

---

#### ActionController Sweeper Extracted

**What Changed:**
Sweepers are no longer included.

**Fix:**
```ruby
# Gemfile
gem 'rails-observers'
```

Note: This is the same gem as "Observers Extracted" — `rails-observers` bundles both Observers and Sweepers.

---

#### Action Caching Extracted

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

#### ActiveResource Extracted

**What Changed:**
ActiveResource is no longer included.

**Fix:**
```ruby
# Gemfile
gem 'activeresource'
```

---

#### Plugins No Longer Supported

**What Changed:**
Rails 4.0 dropped support for `vendor/plugins`.

**Fix:**
- Move plugin code to `lib/` and require it
- Convert to a gem
- Find a gem replacement

---

#### Bidirectional `dependent: :destroy` Now Recurses Forever

**What Changed:**
Rails 3.2 registered `belongs_to ..., dependent: :destroy` as an **after_destroy**, in a `belongs_to`-specific `configure_dependency` (`activerecord-3.2.x/lib/active_record/associations/builder/belongs_to.rb`):

```ruby
model.after_destroy method_name
```

Rails 4.0 dropped that special case and registers all three macros from the shared association builder, as a **before_destroy** (`activerecord-4.0.x/lib/active_record/associations/builder/association.rb`):

```ruby
model.before_destroy "#{macro}_dependent_for_#{name}"
```

`has_many` and `has_one` were `before_destroy` on both versions; only `belongs_to` moved.

The consequence is that any **two models that each declare `dependent: :destroy` pointing at the other** terminate on 3.2 and recurse forever on 4.0. On 3.2 the `belongs_to` side fired after its own row was deleted, so the reciprocal cascade looked for a row that was already gone and stopped after one bounce. On 4.0 both fire while both rows still exist, so `a.destroy → b.destroy → a.destroy → ...` never ends. Each lap reloads from the database, so nothing detects the repetition: a `SystemStackError` in tests, and in a request a hang that times out into a 5xx.

This is silent on upgrade. There is no deprecation warning, the app boots normally, and it only fires on the delete path — which is exactly the path a lot of suites cover thinly, so it tends to survive to production.

Fixed in Rails 5.0 by [rails/rails#18548](https://github.com/rails/rails/pull/18548), which guards `ActiveRecord::Callbacks#destroy` against re-entrant callbacks. Not backported to 4.x.

**Detection Pattern:**
```ruby
# Flag every belongs_to carrying dependent: :destroy, then check the target
# model for a has_one/has_many pointing back with dependent: :destroy.
# belongs_to accepts only :destroy and :delete, and :delete skips callbacks,
# so it cannot close a cycle — :destroy is the whole search.
belongs_to :document, dependent: :destroy      # and Document has_one :link, dependent: :destroy
belongs_to :content, polymorphic: true, dependent: :destroy
belongs_to :document, :dependent => :destroy   # 3.2-era hash-rocket form, same bug
```

**A single hit is not a bug.** The cycle needs both edges cascading into each other: the `belongs_to` side destroying its parent *and* that parent destroying this record back. A lone `belongs_to ..., dependent: :destroy` whose target does not point back, or a pair where the return edge is `dependent: :delete` / `:nullify` (neither runs callbacks on the way back), terminates fine on 4.0. Every hit is a "go read the other model", not a fix.

A regex cannot see the pair, only one side, and a line-based match also misses a declaration wrapped across lines. To enumerate cycles across a whole app, walk the reflections instead — for each model, each association carrying a cascading `dependent:`, resolve the target (for a polymorphic `belongs_to`, through the models declaring the matching `as:`), then look for an edge pointing back:

```ruby
model.reflect_on_all_associations.select { |r| r.options[:dependent] == :destroy }
```

**Fix:**
Move the cascade the application does *not* drive to an explicit `after_destroy`, which restores the 3.2 ordering. Cut the edge only if nothing relies on that direction — dropping `dependent:` outright stops the loop but silently orphans rows.

```ruby
# BEFORE — both sides cascade, recurses on 4.0
class Attachment < ActiveRecord::Base
  belongs_to :document, dependent: :destroy   # the direction the app drives
end

class Document < ActiveRecord::Base
  has_one :attachment, dependent: :destroy    # the reciprocal that closes the cycle
end

# AFTER — same two deletions, one of them reordered
class Attachment < ActiveRecord::Base
  belongs_to :document, dependent: :destroy
end

class Document < ActiveRecord::Base
  has_one :attachment

  after_destroy :destroy_attachment

  private

  def destroy_attachment
    attachment.destroy if attachment
  end
end
```

By the time `after_destroy` runs, this row is gone, so the reciprocal cascade re-reads and resolves to `nil`, stopping after one bounce. Three caveats worth knowing:

- That termination depends on the reciprocal association being re-read from the database. If the pair declares `inverse_of:` (available in 4.0; only the automatic detection arrived in 4.1), or the target is already loaded in memory, `attachment.document` returns the in-memory destroyed `Document` instead of `nil`, its `before_destroy` fires again, and the loop survives the fix — 4.0 has no re-entrancy guard (Rails 5.0 added `@_destroy_callback_already_called`). Verify the pair does not declare `inverse_of:` on the reciprocal edge, or make the callback itself re-entrant:
  ```ruby
  def destroy_attachment
    return if @_destroying_attachment
    @_destroying_attachment = true
    attachment.destroy if attachment
  end
  ```
  A `destroyed?` / `frozen?` check is not enough here: neither flag is set until the destroy completes, so the second pass through the callback still sees a live-looking record.

- If the model soft-deletes, "gone" means excluded by the default scope rather than deleted. That still terminates, but confirm it for your soft-delete implementation rather than assuming.
- The cleanup can no longer veto the destroy. As a `before_destroy` a failed cascade halted the whole operation and `destroy` returned `false`; from `after_destroy` the row is already deleted, so a failure leaves an orphan and `destroy` still reports success. Raise from the callback if you need the old all-or-nothing behavior.

---

### 🟢 LOW PRIORITY (but commonly encountered)

#### Fixture Dates Must Be Cast to Strings

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

#### `config.eager_load` Required in All Environments

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

#### `config.assets.compress` Removed

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

#### `ActiveSupport::BufferedLogger` Renamed

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

#### `config.paths["config/routes"]` Key Changed

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

#### `select('distinct ...').pluck` → `.distinct.pluck`

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

#### `assign_attributes` Method Signature Changed

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

#### Validation Callback API Changed

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

#### Test Request Headers API Changed

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

#### `ActiveRecord::ImmutableRelation` Error

**What Changed:**
In Rails 4, calling methods like `count` on a relation that has already been loaded or modified can raise `ActiveRecord::ImmutableRelation`.

**Detection Pattern:**
```ruby
scope.count('distinct column_name').as_json
```

**Fix:**
Rewrite the query to avoid modifying a frozen relation, e.g., use `.distinct.count` or `.to_a.count`.

---

#### PaperTrail Version Models Require `VersionConcern`

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
| `ActiveModel::ForbiddenAttributesError` | "Strong Parameters (Replaces attr_accessible)" — use `user_params` not `params[:user]` |
| Scope returns wrong results or errors | "Scopes", under "Scopes and Association Options Require Lambda" — add lambda |
| `Unknown key: :conditions` | "Association `:conditions` hash → lambda with `where()`", under "Scopes and Association Options Require Lambda" — move to lambda |
| `No route matches` | "Routes Require HTTP Method" — add HTTP method |
| Remote form POST arrives with no session or current user | "Remote Forms Stop Embedding the CSRF Token" — pin `embed_authenticity_token_in_remote_forms` |
| `ArgumentError: The method .order() must contain arguments.` | "`order` and `reorder` Require Arguments" — name the column, `order(:id)` for `.order.last` |
| `ArgumentError: Direction should be :asc or :desc` | "`order` and `reorder` Require Arguments" — hash values must be `:asc` / `:desc`; use strings across joins |
| `NoMethodError: undefined method 'rescue_action'` | "`rescue_action` Removed — Use `rescue_from`" |
| `undefined local variable or method` in partial | "Partial Magic Variables Removed" — pass `locals:` |
| Cache misses after upgrade | "`cache_key` Timestamp Format Changed" — changed to `:nsec` |
| `invalid date` in fixtures | "Fixture Dates Must Be Cast to Strings" — cast with `.to_s(:db)` |
| `eager_load is set to nil` | "`config.eager_load` Required in All Environments" — set in all environments |
| `NameError: uninitialized constant ActiveSupport::BufferedLogger` | "`ActiveSupport::BufferedLogger` Renamed" — renamed to `ActiveSupport::Logger` |
| `ActiveRecord::ImmutableRelation` | "`ActiveRecord::ImmutableRelation` Error" — use `.distinct.count` |
| Controller specs don't see custom headers | "Test Request Headers API Changed" — use `request.headers.merge!` |

---

## Resources

- [Rails 4.0 Release Notes](https://guides.rubyonrails.org/4_0_release_notes.html)
- [Strong Parameters Guide](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)
- [RailsDiff 3.2 to 4.0](http://railsdiff.org/3.2.22.5/4.0.13)
