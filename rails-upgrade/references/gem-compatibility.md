# Gem Compatibility Reference

**When to read this:** Step 4.5's compatibility check returned at least one blocker (a gem with no released version that supports the target Rails). This file is the playbook for resolving those.

For the compatibility check itself, see `SKILL.md` Step 4.5 (primary: `next_rails` `bundle_report compatibility`; secondary: `workflows/gem-compatibility-workflow.md`). Don't load this file unless you're already past the check and have blockers to work through.

This file used to carry static `gem × Rails-version` lookup tables. They drifted out of date and ignored the user's actual lockfile, so they were removed in favor of the live checks.

---

## Update order

When applying the bumps the compatibility check produced:

1. **Ruby** — meet the target Rails version's minimum.
2. **Rails** — update to the target version.
3. **Auth / authorization gems** — `devise`, `pundit`, `cancancan`, `doorkeeper`. Boot-blocking when wrong.
4. **Testing gems** — `rspec-rails`, `factory_bot_rails`, `capybara`, `shoulda-matchers`. Required to validate the upgrade.
5. **Everything else** — incrementally, one gem at a time (`bundle update <gem> --conservative`).

The compatibility check tells you the minimum target for each gem. Use it to decide which gems can stay on their current version and which need an explicit bump.

---

## Playbook: gem has no compatible version

When `bundle_report` lists a gem under "with no new compatible versions" or "with no new versions", or railsbump returns `incompatible` with no `earliest_compatible_version`, you have a blocker. Options, in order of preference:

1. **Look for a maintained fork** that adds Rails support — search GitHub for "fork of <gem>" with the target Rails in recent commits.
2. **Check the gem's open PRs / issues** for in-flight Rails support. If a PR is close to merging, ask the user whether to vendor the branch as a temporary `git:` source.
3. **Wait for an upstream release** if the gem is actively maintained and the next release is imminent.
4. **Switch to an alternative** when the gem is abandoned, OR when a Rails-removed API has a back-compat gem and you'd rather use it than refactor. Examples:
   - `paperclip` → `shrine` / Active Storage (paperclip is abandoned).
   - When moving Rails 3 → 4, `attr_accessible` was removed from core. Two paths: refactor controllers to strong parameters, OR add `protected_attributes` to keep `attr_accessible` working. The shim is a valid choice when the controller surface is large and the upgrade timeline is tight; refactoring later is still possible.
5. **Fork and patch** as a last resort. Document the fork in the Gemfile and open an upstream PR.

Surface the choice to the user — do not silently swap gems. Each option has a different long-term cost.

A common false-blocker pattern: gems that became unnecessary in a specific Rails release. They show up under "with no new versions" in `bundle_report`, but the fix is to remove them, not to find a compatible version.

- **Merged into Rails core**: `strong_parameters` was extracted from Rails 3.x as a backport, and is built into Rails ≥ 4.0 (`ActionController::Parameters`). Just remove the gem when targeting Rails 4 or newer.
- **Replaced by core / a successor gem**: `turbo-sprockets-rails3` is replaced by `sprockets-rails` in Rails 4. `paperclip` is unmaintained and replaced by Active Storage / Shrine.
- **Extracted as a back-compat shim**: `protected_attributes` is the *opposite* shape — it was extracted from Rails 4.0 specifically as a transitional shim for the old mass-assignment API and was never re-merged. It still exists as a separate gem, but if your code is moving to `strong_parameters` you can remove it once the controllers are converted.

If `bundle_report` flags one of these, check the target version guide before assuming you need a fork.

---

## Known Gotchas

Real issues hit during actual upgrades, not generic advice. Add to this list as new ones surface.

### `concurrent-ruby` >= 1.3.5 breaks Rails' logger require order on Ruby < 3.5

**Symptom:** `NameError: uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger`, raised from `active_support/logger_thread_safe_level.rb` on boot. `bundle install` / `bundle_report` show nothing wrong — this is a pure require-order bug, not a version constraint conflict.

**Cause:** `activesupport/lib/active_support/logger.rb` requires `active_support/logger_thread_safe_level` *before* it requires the stdlib `logger` gem. Versions of `logger_thread_safe_level.rb` prior to the fix reference the bare `Logger` constant without requiring it themselves, relying on something else in the load path having already pulled in `logger` — which `concurrent-ruby` < 1.3.5 happened to do as a side effect, and 1.3.5+ no longer does.

**Confirmed via source diff:** `activesupport/lib/active_support/logger_thread_safe_level.rb` at tag `v7.0.10` has no `require "logger"` at the top (only `require "concurrent"` and `require "fiber"`) — vulnerable. The same file at `v7.1.6` (in practice, the fix landed by Rails' 7.0.x branch reaching this patch level) adds an explicit `require "logger"`. **The fix is per-Rails-patch-release, not per-Rails-minor** — check the specific patch you're on, not just the major.minor. Rails 6.1.7.10 was confirmed vulnerable; Rails 7.0.10 was confirmed fixed, both checked directly against GitHub source for that tag.

**Fix:** Pin `gem "concurrent-ruby", "< 1.3.5"` in the Gemfile. Safe to apply unconditionally across a dual-boot Gemfile (both sides) even if only the older side actually needs it — confirmed empirically that Rails 7.0.10 boots fine with either the pin or `concurrent-ruby` 1.3.7.
