# Boot Smoke Test Workflow

**When to run:** Step 4.6 of the upgrade workflow, after gem-compat (Step 4.5) and before report generation (Step 5).

**Why this step exists:** Step 4 (codebase grep) only sees the user's own code. Step 4.5 (`next_rails bundle_report compatibility` / railsbump) only sees declared dependency constraints. Neither can detect a gem that resolves cleanly under the target Rails version but then crashes at boot because it calls a removed method or requires a removed file.

A booted Rails process is the only signal that catches that class of failure.

## Real examples this catches

| Hop | Gem | Failure mode | What the resolver / static patterns see |
|---|---|---|---|
| 7.1 → 7.2 | `database_cleaner-active_record 2.1.x` | `NoMethodError: undefined method 'schema_migration' for #<...PostgreSQLAdapter>` at first cleaner call | Resolver: ✓ compatible (no upper bound on activerecord). Patterns: ✗ no app-code reference. |
| 7.2 → 8.0 | `jbuilder 2.11.x` | `LoadError: cannot load such file -- active_support/proxy_object` at `Bundler.require` | Resolver: ✓ compatible (no upper bound on activesupport). Patterns: ✗ no app-code reference. |
| 7.0 → 7.1 | `rails` (core, not a dependency) | `SyntaxError: unexpected (..., ...` parsing `activerecord/lib/active_record/attribute_methods.rb` (`def method_missing(name, ...)`, a Ruby 3.0+ only form) | Resolver: ✓ "compatible" — the rails gemspec for 7.1.6 still declares `ruby_version >= 2.7.0`. Patterns: ✗ nothing in app code references this. `bundle install` succeeds; only booting fails. |

The first two are third-party gems that ship in default Rails-generated apps and needed a newer minor with target-Rails support. The third is different in kind: **the target Rails version itself** can silently raise its own real Ruby floor in a later patch release without updating the gemspec's declared `ruby_version`. Confirmed by diffing `activerecord/lib/active_record/attribute_methods.rb` across tags: the `...`-forwarding `method_missing` is absent through `v7.1.3`, present from `v7.1.4` on — so `gem "rails", "~> 7.1.0"` plus a plain `bundle update rails` silently floats to 7.1.6 and breaks on Ruby 2.7, even though nothing about the *hop* (7.0 → 7.1) is Ruby-incompatible. The fix is not "you must upgrade Ruby for this hop" — it's capping the Gemfile constraint below the offending patch (e.g. `gem "rails", ">= 7.1.0", "< 7.1.4"`) so bundler resolves to the newest patch that's actually compatible with the current Ruby, and deferring the newer patches to whenever Ruby is separately upgraded. Don't assume "latest patch of the target minor" and "compatible with declared minimum Ruby" are the same claim — the boot smoke test is what actually verifies the second one.

## Procedure

### 1. Pick a boot trigger

Anything that loads `config/application.rb` is sufficient. Cheapest options first:

```bash
# Cheapest: just boot the framework
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner "puts Rails.version"

# Slightly heavier: load the test environment without running specs
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec --dry-run

# Heaviest but most thorough: full suite under target Rails
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec
# or
BUNDLE_GEMFILE=Gemfile.next bundle exec rails test
```

Use `rails runner` first. If it boots cleanly, escalate to the full test suite — that catches gems whose problematic code only loads under a specific environment (e.g. test-only gems, eager-load-only paths).

### 2. Diagnose a failure

Boot failures usually show up as one of:

- `LoadError: cannot load such file -- <path>` — a gem `require`s a file Rails removed.
- `NoMethodError: undefined method '<x>' for <Rails internal>` — a gem calls a Rails API that was removed or renamed.
- `ArgumentError` / `TypeError` from a Rails class load — a gem passes args in a now-unsupported shape.

To find the offending gem:

```bash
# Search all bundled gem paths for the missing file / constant
find $(bundle show --paths | tr '\n' ' ') -name "*.rb" 2>/dev/null \
  | xargs grep -l '<missing-file-or-method>' 2>/dev/null
```

The output points at the gem version that needs to bump.

### 3. Resolve

For each offending gem:

1. Check rubygems for a newer minor or patch with target-Rails support:
   ```bash
   curl -s https://rubygems.org/api/v1/versions/<gem>.json \
     | ruby -rjson -e 'puts JSON.parse(STDIN.read).first(8).map{|x|x["number"]}'
   ```
2. Read the gem's CHANGELOG for the target-Rails-compat release.
3. Add a fix-before-bump entry to the upgrade report's gem-update list, citing:
   - The exact failure (`LoadError` / `NoMethodError` / etc.)
   - The minimum compatible version
   - Why a static check missed it (no upper bound declared)
4. Bump the floor in the Gemfile (`gem "<gem>", "~> <new-floor>"`) and re-run `bundle install` for both lockfiles.

### 4. Re-run boot

Repeat steps 1–3 until boot succeeds under `Gemfile.next`. Then proceed to Step 5.

## Output

A short report block to merge into Step 5's Comprehensive Upgrade Report:

```
Boot smoke test (Step 4.6):

  - Triggered: BUNDLE_GEMFILE=Gemfile.next bundle exec rspec --dry-run
  - Result: PASS / FAIL with N gem bumps required

If FAIL → bumps required (added to fix-before-bump):
  - <gem> <old> → <new>: <one-line failure reason>
  - ...
```

If the smoke test passes on the first run, record that explicitly — it is a positive signal that the resolver-level compat check covered everything for this hop.

## Notes

- The smoke test does not replace the post-bump test suite run in Step 6. It is a *boot* check, not a feature check. Step 6 still runs the full suite against both versions.
- Skip this step only if there is no Gemfile.next yet (very early in dual-boot setup). In all other cases, run it.
- **This step (and the test suite in Step 6) cannot catch a format-specific render regression that only manifests when a specific action + non-html format is actually invoked.** Real example (fastruby/audit, 6.1 -> 7.0): a `format.pdf do render pdf: ..., template: "gemfiles/show.html.erb" end` block raised `ActionView::MissingTemplate` on 7.0, but the app booted fine, `rails runner` passed, and the full test suite was green — there was no PDF-format test, and the html-format request to the same action succeeded. The detection pattern "Explicit format/handler extension in template:/layout:" in this file's pattern set catches the extension-in-string half of this; it cannot catch the sibling bug where a render call omits `formats:` inside a non-html `respond_to` block and picks up the block's format instead of :html. Mitigation: before considering a hop complete, grep the app for `respond_to do |format|` blocks and manually exercise (or add a spec for) every non-html branch that calls `render` with custom options — not just the default `format.html`.
- **This step also cannot catch a production-only `assets:precompile` failure**, because `bundle exec rails runner` and the test suite both boot the app without ever running the Sprockets/Uglifier asset pipeline. Real example (fastruby/audit): `ActiveStorage::Engine`, `ActionCable::Engine`, and `ActionText::Engine` each unconditionally add their own JS to `config.assets.precompile` on boot — even when the app uses none of the three (this app used Paperclip for uploads, no rich text, no websockets). Their JS uses ES6 syntax (`const`, `class`, spread), which crashes an ES5-only minifier like Uglifier 4.x with `Uglifier::Error: Unexpected token` — but only when `rake assets:precompile` actually runs, which typically first happens at deploy time (e.g. a Heroku buildpack), not in CI if CI doesn't run a precompile step. A generator-scaffolded but unused `app/assets/javascripts/cable.js` (`//= require action_cable`, pulled in by `application.js`'s `require_tree .`) can drag the same JS into the compile graph even after setting the official per-framework `precompile_assets = false` opt-out flags, since that file's `require` is independent of those flags. Mitigation: if `rake assets:precompile` is part of the app's real deploy path, run it explicitly (with a fake `SECRET_KEY_BASE` and `RAILS_ENV=production`, no live DB required) as part of this hop's verification, and delete any default-generated-but-unused scaffold (`app/channels/application_cable/*`, `app/assets/javascripts/cable.js`) for frameworks the app doesn't actually use, rather than leaving them as latent precompile hazards.
