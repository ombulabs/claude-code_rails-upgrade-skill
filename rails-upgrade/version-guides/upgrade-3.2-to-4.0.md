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
Rails 4.0 deprecates a scope body that is not callable (`scope :active, where(active: true)`). It is still accepted with a deprecation warning, but the stored relation is returned as-is, so conditions chained before the scope are dropped (`Model.where(x: 1).active` runs only the scope's own conditions). Rails 4.1 removes support, and calling such a scope raises `NoMethodError`. `default_scope` follows the same timeline: an argument that is not a block or lambda (`default_scope where(deleted_at: nil)`, `default_scope :order => 'name'`) warns on 4.0 and raises `ArgumentError` on 4.1 when the model loads. Additionally, association options like `:conditions`, `:order`, `:extend`, `:uniq`, and `:finder_sql` that were previously passed as hash options must now be expressed as lambda arguments. This is one of the most impactful changes in a typical Rails 3.2 → 4.0 upgrade.

##### Scopes

**Detection Pattern:**
```ruby
scope :active, where(active: true)
scope(:ordered, order(:position))
scope :visible, scoped.where(hidden: false)
default_scope where(deleted_at: nil)
default_scope :order => 'created_at ASC'
```

Any body that is not a lambda or proc counts, whatever relation method it starts with, with or without parentheses around the arguments. The pattern skips a bare constant (`scope :active, ACTIVE_SCOPE`) and a `method(:name)` object, which Rails accepts when they respond to `call`. A proc in parentheses (`scope :by_month, (proc { |m| where(month: m) })`) is already callable and needs no change.

**Fix:**
```ruby
# BEFORE
scope :active, where(active: true)
scope(:ordered, order(:position))
default_scope where(deleted_at: nil)
default_scope :order => 'created_at ASC'

# AFTER
scope :active, -> { where(active: true) }
scope(:ordered, -> { order(:position) })
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

The AFTER forms do not run on Rails 3.2: its association macros take only `(name, options)`, so a lambda
second argument fails while the model loads: an `ArgumentError` or a `NoMethodError`, depending on the
macro and on whether options follow the lambda.
During dual boot, put the lambda form behind `NextRails.next?` and keep the 3.2 form on the other branch,
or apply the rewrite after the bump. This holds for every association lambda in this section.

##### Association `:conditions` with proc → lambda with owner parameter

When conditions reference the owning object (common in multi-key associations), the proc must become a lambda that receives the owner as a parameter.

**Detection Pattern:**
```ruby
belongs_to :membership, primary_key: :user_id, foreign_key: :user_id,
  conditions: proc { { account_id: account_id } }, extend: MembershipLookup
has_many :events, primary_key: :user_id, foreign_key: :user_id,
  conditions: proc { ["created_at BETWEEN ? AND ?", start_at, end_at] }
has_one :latest_order, class_name: "Order",
  conditions: proc { ["created_at >= ?", some_date] }, order: 'created_at DESC'
```

**Fix:**
```ruby
# BEFORE
belongs_to :membership, primary_key: :user_id, foreign_key: :user_id,
  conditions: proc { { account_id: account_id } }, extend: MembershipLookup

# AFTER: rare and easy to get wrong, verify each one by hand
belongs_to :membership, ->(owner) {
  where(account_id: owner.account_id).extending(MembershipLookup)
}, primary_key: :user_id, foreign_key: :user_id

# BEFORE
has_one :latest_order, class_name: "Order",
  conditions: proc { ["created_at >= ?", some_date] }, order: 'created_at DESC'

# AFTER
has_one :latest_order, ->(owner) {
  where("created_at >= ?", owner.some_date).order('created_at DESC')
}, class_name: "Order"
```

On 3.2 the proc runs with `self` set to the owner, so bare names like `account_id` read the
owner's attributes. Inside the Rails 4 lambda `self` is the relation, so each of them has
to become `owner.account_id`.

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

##### `belongs_to` / `has_one` `:extend` → `extending` inside lambda

Rails 4.0 keeps `:extend` on `has_many` and `has_and_belongs_to_many`, where it still
works with no warning. On `belongs_to` and `has_one` it is gone, and the declaration
raises `ArgumentError: Unknown key: extend` while the model loads.
activerecord-deprecated_finders does not bring it back.

**Detection Pattern:**
```ruby
belongs_to :item, foreign_key: :content_id, extend: ContentExtension
has_one :profile, :extend => ProfileMethods
```

**Fix:**
```ruby
# BEFORE
belongs_to :item, foreign_key: :content_id, extend: ContentExtension

# AFTER
if NextRails.next?
  belongs_to :item, -> { extending(ContentExtension) }, foreign_key: :content_id
else
  belongs_to :item, foreign_key: :content_id, extend: ContentExtension
end
```

The branch is needed because Rails 3.2 does not accept a scope lambda as the second
argument of an association macro: the declaration fails while the model loads. `has_many :items, extend: SomeExtension` can stay as it is.

##### Combined `:conditions` + `:order` + `:extend` → single lambda

When multiple options need to move into the lambda, combine them:

**Fix:**
```ruby
# BEFORE
has_many :featured_posts, class_name: 'Post',
  conditions: { category_id: 4 }, order: 'published_at DESC'

# AFTER
has_many :featured_posts, -> { where(category_id: 4).order('published_at DESC') },
  class_name: 'Post'
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

#### A Symbol Passed to Route `scope` Becomes a Path Segment

**What Changed:**
Rails 3.2's `Mapper#scope` used its first positional argument as the path only when it was a
String, so a Symbol added nothing to the URL and an explicit `path:` survived. Rails 4.0 joins
every positional argument into `options[:path]` before merging the options, so a Symbol becomes a
path segment and overwrites an explicit `path:`. Nothing raises: the old URL returns 404 and
`rake routes` lists the new one. Drawing the same routes on actionpack 3.2.22.5 and 4.0.13 gives:

| Route | 3.2 | 4.0 |
|-------|-----|-----|
| `scope :reports, controller: "reports" do post "export" end` | `/export` | `/reports/export` |
| `namespace :api do scope :meta, controller: "meta", path: "/" do get "status" end end` | `/api/status` | `/api/meta/status` |
| `scope :docs, path: "docs" do ... end` | `/docs/...` | `/docs/...` |
| `scope "legacy" do ... end`, `scope path: "kw" do ... end` | unchanged | unchanged |

An Array or a second positional argument (`scope [:a, :b]`, `scope "a", "b"`) changes the same
way. One exception to "unchanged": from 4.0.4 on, a `scope` outside a resource block also copies
its `path:` into `shallow_path`, so the member routes of `shallow: true` resources inside it gain
that prefix, which 3.2 never added.

**Detection Pattern:**
```bash
grep -rnE "scope\s*\(?\s*(:[\"a-z_]|\[|%[iIwW])" config/routes.rb config/routes/
```
Skip keyword-only hits (`scope :path => ...`, `scope :module => ...`). A lone Symbol whose own
`path:` names the same segment is a no-op on both versions.

**Fix:**
```ruby
# BEFORE
scope :reports, controller: "reports" do
  post "export"
end

namespace :api do
  scope :meta, controller: "meta", path: "/" do
    get "status"
  end
end

# AFTER - same URLs on 3.2 and 4.0, no NextRails.next? branch needed
scope controller: "reports" do
  post "export"
end

namespace :api do
  scope controller: "meta", path: "/" do
    get "status"
  end
end
```

If the block holds `shallow: true` resources under a `path:` other than `"/"`, compare their
member routes in `rake routes` on both versions before relying on one fix for both. Keep the
Symbol only if the new segment is the URL you want, and treat that as a URL change for every
client. Adding `as:` in its place also renames the route helpers.

---

#### Format Validators Reject Multiline Anchors

**What Changed:**
Rails 4.0 checks every format validator's `with:` and `without:` regex when the validator
is declared. A regex that starts with `^` or ends with an unescaped `$` raises unless the
validator passes `multiline: true`:

```
ArgumentError: The provided regular expression is using multiline anchors (^ or $), which may present a security risk. Did you mean to use \A and \z, or forgot to add the :multiline => true option?
```

The check runs while the class loads, so one such validator stops boot. Rails 3.2 has no
check. Only the start and end of the regex count: a `^` inside a character class
(`/\A[^@]+\z/`) or a `$` in the middle is fine.

**Detection Pattern:**
```ruby
validates_format_of :slug, with: /^[a-z-]+$/
validates :code, format: { with: /^[A-Z]{3}$/ }
validates :code, format: /^[A-Z]{3}$/
```

A regex stored in a constant (`with: SLUG_FORMAT`) or built with `Regexp.new` raises the
same way, so look up the constant behind every `with:` that is not a literal.

**Fix:**
```ruby
# BEFORE
validates_format_of :slug, with: /^[a-z-]+$/

# AFTER
validates_format_of :slug, with: /\A[a-z-]+\z/
```

Ruby accepts `\A` and `\z` on every version, so the rewrite needs no `NextRails.next?`
branch. `\z` is stricter than `$`: `$` also matched before a trailing newline, so a value
ending in a newline that passed on 3.2 now fails validation. If the attribute holds
several lines and each line must match, keep the anchors and add `multiline: true`
instead; Rails 3.2 ignores the option.

---

#### Deprecated Association Options Raise on Ruby 2.3+

**What Changed:**
On Rails 4.0, activerecord-deprecated_finders keeps the old association options
(`:conditions`, `:order`, `:include`, `:readonly`, `:uniq`, `:select`, `:limit`,
`:offset`, `:group`, `:having`) working with a deprecation warning. On Ruby 2.3 or newer
it does not: loading, joining or eager loading any association that uses one raises

```
ArgumentError: wrong number of arguments (given 0, expected 1)
```

with a backtrace through `spawn_methods.rb` and the gem's `association_builder.rb`. Ruby
2.3 added `Hash#to_proc`, and Rails 4.0's `Relation#merge!` asks `respond_to?(:to_proc)`
before `is_a?(Hash)`, so the options hash the gem merges into the association scope is run
as a proc with no argument. Rails 4.1.15 moved the Hash check first; 4.1.0 through 4.1.14
keep the 4.0 order. The declaration itself
loads with only the warning, so the app boots and the error appears in requests and specs.

A Hash-valued `default_scope` (`default_scope :order => "created_at ASC"`) takes the same
path: Rails 4.0 merges the Hash into every query of the model, so on Ruby 2.3 each query of
that model raises the same `ArgumentError`. Rewrite it as `default_scope { order("created_at ASC") }`,
which works on 3.2 too, or rely on the `merge!` patch below.

On Ruby 2.2 or older none of this applies.

**Detection Pattern:**
```bash
# Ruby 2.3 or newer on the app
cat .ruby-version; grep -n "^ruby" Gemfile
# Hash-valued default_scope
grep -rnE "default_scope[ (]*:?[a-z_]+(:|[[:space:]]*=>)" app/models/
# associations still using a deprecated option
grep -rnE "(has_many|has_one|belongs_to|has_and_belongs_to_many).*(conditions|order|include|readonly|uniq|select|limit)(:|\s*=>)" app/models/
```

**Fix:**
The durable fix is the rewrite in "Scopes and Association Options Require Lambda": once
no association uses a deprecated option, the error cannot happen. Because the lambda
argument raises on Rails 3.2, put the rewritten declaration behind `NextRails.next?`.

To bump first and rewrite later, load an initializer on the next side only that restores
the Ruby 2.2 behavior. It needs both patches. With the `merge!` patch alone, a Hash-valued
`:conditions` stops raising and is silently dropped, because the gem also calls `to_proc`
on it and gets nil back, so the association returns every row.

```ruby
# config/initializers/deprecated_association_options_ruby23.rb
if NextRails.next?
  # The gem defines DeprecatedOptionsProc only once ActiveRecord::Base loads.
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Relation.class_eval do
      def merge!(other) # :nodoc:
        if other.is_a?(Hash)
          ActiveRecord::Relation::HashMerger.new(self, other).merge
        elsif !other.is_a?(ActiveRecord::Relation) && other.respond_to?(:to_proc)
          instance_exec(&other)
        else
          ActiveRecord::Relation::Merger.new(self, other).merge
        end
      end
    end

    ActiveRecord::Associations::Builder::DeprecatedOptionsProc.class_eval do
      def to_proc
        options = self.options
        proc do |owner|
          # Same check as the gem, minus a Hash (which responds to to_proc on Ruby 2.3).
          if options[:where].respond_to?(:to_proc) && !options[:where].is_a?(Hash)
            context = owner || self
            where(context.instance_eval(&options[:where])).merge!(options.except(:where))
          else
            merge(options)
          end
        end
      end
    end
  end
end
```

Add a spec that loads one association of each kind and checks the rows it returns, since
a silently dropped condition is the failure to guard against. Delete the initializer when
the rewrite is done, and finish the rewrite before the 4.1 hop: 4.1.0 through 4.1.14 keep
the same `merge!` order, and from 4.1.15 a Hash-valued `:conditions` kept through the gem
is dropped without an error.

---

#### Duplicate Route Names Raise, Including a Second `root`

**What Changed:**
Rails 3.2's `RouteSet#add_route` overwrote an existing entry in `named_routes`, so an app
could declare `root` once per constraints block and boot. Rails 4.0 raises instead:

```
ArgumentError: Invalid route name, already in use: 'root'
```

Every `root` without `as:` registers `:root`, so the second one in the same route set stops
boot. A `root` inside `namespace :admin` registers `admin_root` and does not collide, and an
engine's routes are a separate route set.

**Detection Pattern:**
```ruby
root to: "pages#home", constraints: WwwConstraint
root to: "accounts#show", constraints: SubdomainConstraint
```

**Fix:**
```ruby
# BEFORE
root to: "pages#home", constraints: WwwConstraint
root to: "accounts#show", constraints: SubdomainConstraint

# AFTER: keep the first as :root so root_path / root_url keep working
root to: "pages#home", constraints: WwwConstraint
root to: "accounts#show", constraints: SubdomainConstraint, as: :account_root
```

`as:` on `root` works on 3.2 too, so no `NextRails.next?` branch is needed. Requests to
`/` still go to the first root whose constraints match.

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
# remote forms whose submit path needs auditing, both hash syntaxes,
# plus an explicit "data-remote" key in the form's html options
grep -rnE "remote:\s*true|:remote\s*=>\s*true|[\"']data-remote[\"']" app/views/ app/helpers/

# confirm the app never pinned the config
grep -rn "embed_authenticity_token_in_remote_forms" config/

# true on the current boot and false on the next confirms it relies on the default
bundle exec rails runner 'puts ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms.inspect'
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner 'puts ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms.inspect'
```

Remote `link_to` / `button_to` links are safe: UJS builds their form and token itself.
The grep is a list of forms to audit, not a list of forms to change.

The flip keys on the literal `data-remote` html option. `remote: true`,
`html: { remote: true }` and `html: { "data-remote" => true }` all drop the token on 4.0,
including when a helper builds that hash on an earlier line
(`html_options[:"data-remote"] = true`). `data: { remote: true }` does not: the form
still renders `data-remote="true"`, but the hidden token stays.

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

#### terser Fails to Load on Sprockets 2.x

**What Changed:**
Rails 4.0 runs on `sprockets-rails` 2.0, which pins Sprockets to 2.x. terser's
`Terser::Compressor` requires `sprockets/digest_utils`, which only exists from Sprockets
3.0. The bundle resolves, because terser does not declare a sprockets dependency, but
terser's railtie registers the compressor in a `config.assets.configure` block that
sprockets-rails 2.0 runs at boot, and the app dies with:

```
LoadError: cannot load such file -- sprockets/digest_utils
```

On 3.2, `config.assets.configure` is only an unset option, so the block never runs and
the current side boots. `uglifier` and `closure-compiler` do not load that file.

**Detection Pattern:**
```ruby
# Gemfile
gem "terser"
```

**Fix:**
```ruby
# BEFORE
group :assets do
  gem "terser"
end

# AFTER
group :assets do
  if next?
    gem "uglifier", ">= 1.3.0"   # only so :uglifier resolves in env configs
    gem "terser", require: false
  else
    gem "terser"
  end
end
```

`require: false` alone stops the boot failure. To keep compiling with terser on the next
side, register it at compile time with a rake task: the full recipe is in
`references/js-compressor-sprockets-mismatch-reference.md`.

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
`{column => direction}` and raises `ArgumentError: Direction should be :asc or :desc`
unless every value is exactly the symbol `:asc` or `:desc`. So `order(events: :start)`,
`order(name: :DESC)`, `order(name: "desc")` and `order(:position, name: :foo)` all raise. It also only accepts columns on the model's own table, so
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
`line_item.order.summary` matches on `sum`. The hash grep is a rough first pass: its
`:asc` / `:desc` filter drops the whole line, so a line chaining a bad hash and a good one
is filtered out with it, and it cannot see a hash spread over several lines. The skill's
own pattern checks each value. Run through the whole-file scanner
(`detection-scripts/scan_patterns.rb`) it also reads a hash spread over several lines; run
as a line-based search it sees only one-line calls, so check multi-line `order(` calls by
hand in that case. Neither can see a hash held in a constant or built at runtime
(`order(SORT)`), so also scan `order(` by hand in query objects and reports. Two shapes stay invisible to both
the grep and the skill's own pattern: a receiverless `order` inside a scope
(`scope :recent, -> { order }`), and a bare call followed by an enumerable method rather
than a relation method (`.order.map { ... }`, `.order.sort_by { ... }`).

**Fix:**
```ruby
# BEFORE
Membership.where(user_id: user_id).order.last

# AFTER
Membership.where(user_id: user_id).order(:id).last
```

`:id` is not an arbitrary choice for the `.order.last` shape. On 3.2, `last` with no order
calls `reverse_order`, which falls back to `ORDER BY <table>.<primary_key> DESC LIMIT 1`,
so `order(:id).last` reproduces the old result exactly.

```ruby
# BEFORE: raises on 4.0, sorted by nothing on 3.2
.order(
  { tags: :id },
  { task_items: :month }
)

# AFTER: strings are the only form that can express a sort across joined tables
.order(
  "tags.id",
  "task_items.month"
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
method` warning; wrap it as `Arel.sql("tags.id")`. `Arel.sql` exists since Rails
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
The default `ActiveRecord::Base.cache_timestamp_format` changed from `:number` to `:nsec`,
so the key of any record with `updated_at` gains nine digits of fractional seconds:

```ruby
account.cache_key
# Rails 3.2 => "accounts/1-20140102030405"
# Rails 4.0 => "accounts/1-20140102030405678901000"
```

Nothing raises. Every cache entry keyed on a record misses once after the deploy and is
rebuilt, which can be a load spike on a large app. Code that stores a record's
`cache_key` outside the cache (a database column, an ETag a client kept, a key handed to
another service) or compares it to a saved string stops matching.

**Detection Pattern:**
```ruby
# a record key used as a value, and any existing setting
record.cache_key
update_column(:etag, cache_key)   # inside the model
cache_timestamp_format
```

`model_name.cache_key` has no timestamp and is not affected. A method of the app's own
that takes an argument (`cache_key(:totals)`) is not the Active Record method.

**Fix:**
To keep the 3.2 keys, set the format explicitly. The setting exists from Rails 3.2.13, so on
3.2.13 or newer it can ship before the bump. On 3.2.0 through 3.2.12 the setter does not exist
and boot fails with `NoMethodError`, so add `if NextRails.next?` to the line:

```ruby
# config/application.rb
config.active_record.cache_timestamp_format = :number
```

Remove it later, when a one-time cache flush is acceptable. If nothing stores the keys and
a cold cache after the deploy is fine, no change is needed.

**Skill behavior:** When this change is detected, ask the user which approach they prefer.
The right choice depends on whether anything outside the cache relies on the key format.

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

#### Page and Action Caching Extracted

**What Changed:**
Rails 4.0 removes page caching and action caching from Action Pack and ships them as two
separate gems. `caches_page`, `expire_page` and `page_cache_directory` move to
`actionpack-page_caching`; `caches_action` and `expire_action` move to
`actionpack-action_caching`. Without the matching gem, `caches_page` or `caches_action`
raises `NoMethodError` when the controller class loads, and a leftover
`config.action_controller.page_cache_directory` setting stops boot with
`RuntimeError: Invalid option key: page_cache_directory=`. A hand-called `cache_page`
moves to the page caching gem too.

**Detection Pattern:**
```ruby
caches_page :public
expire_page action: "public"
caches_action :index, :show
expire_action action: "index"
```

**Fix:**
```ruby
# BEFORE: Gemfile, nothing needed on 3.2

# AFTER: add only the gem for the methods the app calls, on the next side,
# since both gems require actionpack >= 4.0 and cannot bundle on 3.2
if next?
  gem "actionpack-page_caching"    # caches_page, expire_page
  gem "actionpack-action_caching"  # caches_action, expire_action
end
```

Call sites stay as they are. From actionpack-page_caching 1.0.1 the gem sets
`page_cache_directory` to `public/` when the app does not; 1.0.0 leaves it empty, so
pin `>= 1.0.1` or set it.

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

#### Precompile No Longer Writes Non-Digest Asset Copies

**What Changed:**
On Rails 3.2, `rake assets:precompile` ran a second `assets:precompile:nondigest` pass
whenever `config.assets.digest` was on, so `public/assets/` held both `logo-<digest>.png`
and a plain `logo.png`. On 4.0 the task comes from `sprockets-rails` 2.x, whose
`Sprockets::Manifest#compile` writes the digested file only. Any hardcoded
`/assets/logo.png` stops resolving in production once the 4.0 bundle is precompiled.

Nothing raises. The page renders, and the test suite stays green because Sprockets serves
logical paths live wherever `config.assets.compile` is on (the test default). The symptom
is a broken image, icon or font in production. A literal path that already carries a
digest breaks too: the digest mixes in the Sprockets version, so it changes at the bump.

**Detection Pattern:**
```bash
grep -rnE "[\"'(][[:space:]]*/assets/" app/ lib/ config/ vendor/assets/ public/*.html
```

**Fix:**
```scss
// BEFORE (plain .css, or .css.scss)
.banner { background: url(/assets/backgrounds/stripes.png); }

// AFTER (rename the file to .css.scss first if it is plain .css)
.banner { background: image-url("backgrounds/stripes.png"); }
```

```haml
-# BEFORE
%link{ href: '/assets/favicons/apple-touch-icon.png', rel: 'apple-touch-icon' }

-# AFTER
%link{ href: asset_path('favicons/apple-touch-icon.png'), rel: 'apple-touch-icon' }
```

The helpers exist on 3.2, so the change ships before the bump. In plain JavaScript,
render the path from the view (`data-icon="<%= asset_path('spinner.gif') %>"`) instead of
hardcoding it. A file that something outside the app links to directly (a sent email, a
static error page in `public/`) belongs in `public/`, outside the pipeline. Do not set
`config.assets.digest = false` to get the plain names back: that drops cache busting for
every asset.

---

#### Sass CSS Compressor Now Parses Minified Stylesheets

**What Changed:**
sass-rails 3.2.6 installed `Sass::Rails::CssCompressor` only when `config.assets.compress`
was set, and it returned the CSS untouched unless the bundle had more than two newlines:

```ruby
def compress(css)
  if css.count("\n") > 2
    Sass::Engine.new(css, ...).render
  else
    css
  end
end
```

sass-rails 4.0.0 replaces that with `config.assets.css_compressor ||= :sass` in every
environment except development, and `:sass` is `Sprockets::SassCompressor`, which sends
every bundle through `Sass::Engine` with no guard. A one-line vendored `.min.css` that
3.2 passed through is now parsed as SCSS, and Ruby Sass rejects some valid CSS:

```
Sass::SyntaxError: "var(--gap)" is not a number for `max'
```

That aborts `assets:precompile`. The compressor is now installed in the test environment
too, so a feature spec whose page loads the stylesheet gets the same error from the asset
request. The compressor runs per bundle: a minified file pulled into a larger manifest
with `*= require` was already parsed on 3.2, so the files that change behavior are the
ones precompiled or linked on their own. An app that sets `config.assets.css_compressor`
itself is not affected, because sass-rails only fills in an unset value.

**Detection Pattern:**
```bash
# .css files with at most two newlines (the same count as the 3.2 guard)
# and a line of 300+ characters
ruby -e 'Dir["{app,lib,vendor}/assets/stylesheets/**/*.css"].each { |f| css = File.read(f); puts f if css.count("\n") <= 2 && css.lines.any? { |l| l.chomp.length >= 300 } }'
```

**Fix:**
First precompile the 4.0 bundle in a production-like environment to see whether a flagged
file fails at all. If one does, keep the 3.2 guard by assigning a compressor object, which
stops sass-rails' `||=` from installing its own:

```ruby
# BEFORE: nothing set, sass-rails 4.0 installs the unguarded :sass compressor

# AFTER: config/application.rb, valid on 3.2 and 4.0
config.assets.css_compressor = Class.new do
  def compress(css)
    return css unless css.count("\n") > 2

    Sass::Engine.new(css, syntax: :scss, style: :compressed,
                          cache: false, read_cache: false).render
  end
end.new
```

Other options are bumping the `sass` gem (3.7.4 renders `max(var(--gap), 1px)`, 3.4
does not) or switching to a CSS-only compressor. Do not assign an object whose `compress`
returns its input unchanged: precompile goes green, production CSS silently stops being
minified, and nothing reports it. Compare the size of the precompiled `application-*.css`
with the 3.2 build.

---

#### `FormBuilder.field_helpers` Holds Symbols, Not Strings

**What Changed:**
On 3.2, `ActionView::Helpers::FormBuilder.field_helpers` is
`FormHelper.instance_method_names - %w(form_for convert_to_model)`, a list of strings.
On 4.0 it is a literal array of symbols. String operations on it silently stop matching:
`field_helpers - %w(label fields_for)` removes nothing on 4.0. A custom builder that
decorates every helper except a few ends up redefining the ones it meant to skip, and
nothing raises or warns.

**Detection Pattern:**
```ruby
class LabeledFormBuilder < ActionView::Helpers::FormBuilder
  (field_helpers - %w(label fields_for hidden_field)).each do |helper|
```

**Fix:**
```ruby
# BEFORE
(field_helpers - %w(label fields_for hidden_field)).each do |helper|

# AFTER: same list on 3.2 and 4.0
(field_helpers.map(&:to_s) - %w(label fields_for hidden_field)).each do |helper|
```

---

#### `RouteSet#install_helpers` Removed

**What Changed:**
Rails 3.2's `RouteSet#install_helpers(destinations = [ActionController::Base, ActionView::Base])`
mixed a route set's named-route helpers into other classes. Rails 4.0 removed it, so any
call raises `NoMethodError: undefined method 'install_helpers'`, often in spec setup that
builds its own `RouteSet`.

**Detection Pattern:**
```ruby
Rails.application.routes.install_helpers(self)
route_set.install_helpers
```

**Fix:**
```ruby
# BEFORE
Rails.application.routes.install_helpers(self)

# AFTER: works on 3.2 and 4.0
include Rails.application.routes.url_helpers

# BEFORE (spec with its own route set)
route_set.install_helpers

# AFTER
ActionView::Base.send(:include, route_set.url_helpers)
```

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

A pair that declares `inverse_of:` explicitly already recursed on 3.2, because the `belongs_to` side gets the in-memory record back instead of re-reading it. The 4.0 change is that the pair now recurses without any `inverse_of:`.

The loop does not simply go away on later 4.x versions. Running a reciprocal `has_one` / `belongs_to` pair on each version gives:

- **4.1**: still recurses. 4.1 also starts detecting `inverse_of` automatically for a simple pair like this one, which breaks the `after_destroy` fix below when it is written without the instance flag (see the 4.0 to 4.1 guide).
- **4.2**: activerecord 4.2.0 moves the `belongs_to` cascade back to `after_destroy` (CHANGELOG: "Move 'dependent: :destroy' handling for `belongs_to` from `before_destroy` to `after_destroy` callback chain", which closes issue rails/rails#12380). The pair terminates again only when both sides declare `inverse_of: false`; with the inverse that 4.2 detects automatically it still raises `SystemStackError`.
- **5.0**: [rails/rails#18548](https://github.com/rails/rails/pull/18548) makes `ActiveRecord::Callbacks#destroy` return early when it is called again on the same object while its callbacks run (`@_destroy_callback_already_called`). The pair terminates with or without an inverse. Not backported to 4.x.

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
Move the cascade the application does *not* drive to an explicit `after_destroy` that guards itself with an instance flag. Cut the edge only if nothing relies on that direction: dropping `dependent:` outright stops the loop but silently orphans rows.

```ruby
# BEFORE: both sides cascade, recurses on 4.0
class Attachment < ActiveRecord::Base
  belongs_to :document, dependent: :destroy   # the direction the app drives
end

class Document < ActiveRecord::Base
  has_one :attachment, dependent: :destroy    # the reciprocal that closes the cycle
end

# AFTER: same two deletions, one of them reordered and guarded
class Attachment < ActiveRecord::Base
  belongs_to :document, dependent: :destroy
end

class Document < ActiveRecord::Base
  has_one :attachment

  after_destroy :destroy_attachment

  private

  def destroy_attachment
    return if @_destroying_attachment
    begin
      @_destroying_attachment = true
      attachment.destroy if attachment
    ensure
      @_destroying_attachment = false
    end
  end
end
```

The flag is what makes this safe on every version the app will pass through, and the `ensure` clears it so a retry on the same object after a rolled-back transaction still cascades. Without it, the `after_destroy` alone stops the loop only when `attachment.document` is re-read from the database and comes back `nil`. With an inverse, `attachment.document` is the same in-memory `Document`, its callbacks run again, and the loop survives. That happens on 3.2 and 4.0 when the pair declares `inverse_of:`, and on 4.1 and 4.2 even without one, because those versions detect the inverse automatically. Run on activerecord 3.2.22.5, 4.0.13, 4.1.16, 4.2.0, 4.2.11.3, 5.0.0 and 5.0.7.2, the flag version terminated and deleted both rows with the inverse automatic, explicit or disabled; the version without the flag raised `SystemStackError` on 4.1 and 4.2 unless both sides declared `inverse_of: false`. `inverse_of: false` on its own, without moving the cascade to `after_destroy`, does not help on 4.0 or 4.1, where the `belongs_to` cascade is still a `before_destroy`.

A `destroyed?` check is no substitute for the flag. On the record itself it is already `true` inside `after_destroy`, so `return if destroyed?` skips the cleanup every time and orphans the attachment. On the target, `attachment.destroyed?` is still `false` while the attachment's own `before_destroy` callbacks run, so on 4.0 and 4.1 with an inverse the loop goes on.

Once the app is on Rails 5.0, the re-entrancy guard in `ActiveRecord::Callbacks#destroy` covers this, and both sides can go back to `dependent: :destroy`. Two more caveats:

- If the model soft-deletes, "gone" means excluded by the default scope rather than deleted. That still terminates, but confirm it for your soft-delete implementation rather than assuming.
- The cleanup can no longer veto the destroy. As a `before_destroy` a failed cascade halted the whole operation and `destroy` returned `false`; from `after_destroy` the row is already deleted, so a failure leaves an orphan and `destroy` still reports success. Raise from the callback if you need the old all-or-nothing behavior.

---

#### Dynamic Finders Deprecated

**What Changed:**
Rails 4.0 keeps only `find_by_*` and `find_by_*!` in Active Record. `find_all_by_*`,
`find_last_by_*`, `find_or_create_by_*`, `find_or_initialize_by_*` and `scoped_by_*` move
to the `activerecord-deprecated_finders` gem, which activerecord 4.0 depends on, so they
keep working and print a warning on every call:

```
DEPRECATION WARNING: This dynamic method is deprecated. Please use e.g. Post.where(...).all instead.
```

Rails 4.1 drops the gem and these calls raise `NoMethodError`. `find_by_*` is not part of
this change: it works without a warning on 4.0 and later. It only warns when it is passed
an options hash or a block.

**Detection Pattern:**
```ruby
User.find_all_by_email(email)
User.find_last_by_email(email)
User.find_or_create_by_email(email)
User.find_or_initialize_by_email(email)
```

**Fix:**
The keyword forms `find_or_create_by(email: email)` and `find_by(email: email)` do not
exist on Rails 3.2 (they raise `NoMethodError` there), so rewrite with calls that work on
both versions and the change can ship before the bump:

```ruby
# BEFORE
User.find_all_by_email(email)
User.find_last_by_email(email)
User.find_or_create_by_email(email)
User.find_or_initialize_by_email(email)

# AFTER (Rails 3.2 and 4.0)
User.where(email: email).to_a
User.where(email: email).last
User.where(email: email).first_or_create
User.where(email: email).first_or_initialize
```

Once the app is on 4.0, `find_or_create_by(email: email)` and
`find_or_initialize_by(email: email)` are the shorter spellings.

Keep `.to_a` where the result is read more than once: `find_all_by_*` returned an Array,
and a bare `where` is a lazy Relation that runs a new query for each `any?`, `size` or
`each`.

An app can define its own method whose name starts with one of these prefixes. The
detection patterns skip the `def` line but not the callers, so check for a matching `def`
before rewriting a call.

---

#### `Model.scoped` Deprecated

**What Changed:**
Rails 4.0 removed `scoped` from Active Record. The `activerecord-deprecated_finders` gem,
which activerecord 4.0 depends on, adds it back with a warning on every call, with or
without an options hash:

```
DEPRECATION WARNING: Model.scoped is deprecated. Please use Model.all instead.
```

Rails 4.1 drops the gem and `Model.scoped`, `relation.scoped` and `association.scoped`
all raise `NoMethodError`.

**Detection Pattern:**
```ruby
Post.scoped
user.posts.scoped.where(published: true)
Post.scoped(conditions: { published: true }, include: :author, order: "created_at DESC")

# receiverless, inside the model
scope :everyone, -> { scoped }
def self.for_region(region)
  region ? where(region: region) : scoped
end
```

**Fix:**
```ruby
# BEFORE
Post.scoped
user.posts.scoped.where(published: true)
Post.scoped(conditions: { published: true }, include: :author, order: "created_at DESC")
scope :everyone, -> { scoped }

# AFTER (Rails 3.2 and 4.0)
Post.where(nil)
user.posts.where(published: true)
Post.where(published: true).includes(:author).order("created_at DESC")
scope :everyone, -> { where(nil) }
```

`where(nil)` returns a Relation with no conditions on both versions. `all` is the 4.0
replacement the warning names, but on 3.2 `all` loads the records into an Array, so a
chained scope call after it breaks before the bump. Switch to `all` once the app is on 4.0.

A local variable, a `let(:scoped)`, or an app object that defines its own `scoped` method
(a query or presenter object) looks the same to a search. Check for a `def scoped` or
`let(:scoped)` before rewriting.

---

#### `update_all` With Conditions Deprecated

**What Changed:**
Rails 3.2 accepted `update_all(updates, conditions, options)`. Rails 4.0 core takes only
`update_all(updates)`; the `activerecord-deprecated_finders` gem, which activerecord 4.0
depends on, keeps the extra arguments working with a warning:

```
DEPRECATION WARNING: Relation#update_all with conditions is deprecated. Please use Item.where(color: 'red').update_all(...) rather than Item.update_all(..., color: 'red').
```

A `:limit` / `:order` options hash gets a second warning. Rails 4.1 drops the gem and the
call raises `ArgumentError: wrong number of arguments`.

**Detection Pattern:**
```ruby
User.update_all({ active: false }, { id: ids })
User.update_all("active = 0", ["created_at < ?", cutoff])
Product.update_all(attrs, { sku: sku }, limit: 1)
self.class.update_all({ synced_at: now }, id: id)
```

**Fix:**
```ruby
# BEFORE
User.update_all({ active: false }, { id: ids })
User.update_all("active = 0", ["created_at < ?", cutoff])
Product.update_all(attrs, { sku: sku }, limit: 1)

# AFTER (Rails 3.2 and 4.0)
User.where(id: ids).update_all(active: false)
User.where("created_at < ?", cutoff).update_all("active = 0")
Product.where(sku: sku).limit(1).update_all(attrs)
```

A single braceless hash, `update_all(active: false, synced_at: now)`, is one argument and
needs no change.

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
gem 'actionpack-page_caching'   # If using caches_page
gem 'actionpack-action_caching' # If using caches_action
```

```bash
bundle update rails
```

### Phase 3: Fix Breaking Changes
1. Add lambda to all scopes
2. **Migrate all association `:conditions`, `:order`, `:extend`, `:uniq` options to lambda syntax** (this is typically the highest-volume change)
3. Rewrite `:finder_sql` associations as scopes or methods; remove `:readonly` options
4. Replace `Model.scoped` with `where(nil)` and rewrite `find_all_by_*`, `find_last_by_*`, `find_or_create_by_*`, `find_or_initialize_by_*` and `scoped_by_*` with `where` (`find_by_*` can stay). No 4.0 pattern flags `scoped_by_*` (the 4.1 patterns do), so grep for it by hand, and move `update_all` conditions into `where`
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
- Precompile the 4.0 bundle and confirm every literal `/assets/` path still resolves to a file under `public/assets/`

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
| `DEPRECATION WARNING: Using #scope without passing a callable object`, or a scope ignores conditions chained before it | "Scopes", under "Scopes and Association Options Require Lambda" — add lambda |
| `Unknown key: :conditions` | "Association `:conditions` hash → lambda with `where()`", under "Scopes and Association Options Require Lambda" — move to lambda |
| `ArgumentError: Unknown key: extend` | "`belongs_to` / `has_one` `:extend` → `extending` inside lambda", under "Scopes and Association Options Require Lambda": move the module into `extending` |
| `ArgumentError: wrong number of arguments (given 0, expected 1)` from `spawn_methods.rb` when an association loads or a model with a Hash `default_scope` is queried | "Deprecated Association Options Raise on Ruby 2.3+": rewrite to a scope lambda or add the two-patch initializer |
| `No route matches` | "Routes Require HTTP Method" — add HTTP method |
| `ArgumentError: Invalid route name, already in use: 'root'` | "Duplicate Route Names Raise, Including a Second `root`": add `as:` to the later roots |
| A scoped route 404s and `rake routes` shows an extra segment | "A Symbol Passed to Route `scope` Becomes a Path Segment" — drop the Symbol, keep `path:` |
| `ArgumentError: The provided regular expression is using multiline anchors (^ or $)` | "Format Validators Reject Multiline Anchors": use `\A` and `\z` |
| Remote form POST arrives with no session or current user | "Remote Forms Stop Embedding the CSRF Token" — pin `embed_authenticity_token_in_remote_forms` |
| `LoadError: cannot load such file -- sprockets/digest_utils` at boot | "terser Fails to Load on Sprockets 2.x": `require: false` on the next side |
| `ArgumentError: The method .order() must contain arguments.` | "`order` and `reorder` Require Arguments" — name the column, `order(:id)` for `.order.last` |
| `ArgumentError: Direction should be :asc or :desc` | "`order` and `reorder` Require Arguments" — hash values must be `:asc` / `:desc`; use strings across joins |
| `DEPRECATION WARNING: This dynamic method is deprecated. Please use e.g. Post.where(...).all instead.` (the suggestion is `Post.where(...).last`, `Post.find_or_create_by(name: 'foo')` or `Post.find_or_initialize_by(name: 'foo')` for the other finders) | "Dynamic Finders Deprecated": rewrite with `where`, raises on 4.1 |
| `DEPRECATION WARNING: Model.scoped is deprecated. Please use Model.all instead.` | "`Model.scoped` Deprecated": use `where(nil)` before the bump, `all` after |
| `DEPRECATION WARNING: Relation#update_all with conditions is deprecated.` or `Relation#update_all with :limit / :order options is deprecated.` | "`update_all` With Conditions Deprecated": move the conditions into `where` |
| `NoMethodError: undefined method 'rescue_action'` | "`rescue_action` Removed — Use `rescue_from`" |
| `NoMethodError: undefined method 'install_helpers'` | "`RouteSet#install_helpers` Removed": include `url_helpers` instead |
| `NoMethodError: undefined method 'caches_page'` or `'caches_action'` | "Page and Action Caching Extracted": add the matching gem on the next side |
| `RuntimeError: Invalid option key: page_cache_directory=` at boot | "Page and Action Caching Extracted": add `actionpack-page_caching` on the next side |
| A custom form builder now wraps `label`, `hidden_field` or `fields_for` it used to skip | "`FormBuilder.field_helpers` Holds Symbols, Not Strings": compare against symbols |
| `undefined local variable or method` in partial | "Partial Magic Variables Removed" — pass `locals:` |
| Cache misses after upgrade | "`cache_key` Timestamp Format Changed" — changed to `:nsec` |
| `invalid date` in fixtures | "Fixture Dates Must Be Cast to Strings" — cast with `.to_s(:db)` |
| `eager_load is set to nil` | "`config.eager_load` Required in All Environments" — set in all environments |
| `NameError: uninitialized constant ActiveSupport::BufferedLogger` | "`ActiveSupport::BufferedLogger` Renamed" — renamed to `ActiveSupport::Logger` |
| `ActiveRecord::ImmutableRelation` | "`ActiveRecord::ImmutableRelation` Error" — use `.distinct.count` |
| `SystemStackError: stack level too deep` from `destroy`, or a delete request that hangs | "Bidirectional `dependent: :destroy` Now Recurses Forever": guarded `after_destroy` on one side |
| Controller specs don't see custom headers | "Test Request Headers API Changed" — use `request.headers.merge!` |
| Images, icons or fonts 404 in production, fine in tests | "Precompile No Longer Writes Non-Digest Asset Copies": replace literal `/assets/` paths with asset helpers |
| `Sass::SyntaxError` from `assets:precompile` in a `.min.css` file | "Sass CSS Compressor Now Parses Minified Stylesheets": restore the newline guard |

---

## Resources

- [Rails 4.0 Release Notes](https://guides.rubyonrails.org/4_0_release_notes.html)
- [Strong Parameters Guide](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)
- [RailsDiff 3.2 to 4.0](http://railsdiff.org/3.2.22.5/4.0.13)
