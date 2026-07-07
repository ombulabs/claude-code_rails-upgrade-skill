# Ruby 3.4 → 4.0

**Difficulty:** Medium. It's a *major* version bump, but there is no 3.5–3.9 line — Ruby goes straight from 3.4 to 4.0, so this is still the immediate next sequential hop, not a multi-hop skip. Treat it with major-version scrutiny (lean hard on the deprecation sweep, boot smoke, and full suite), but the practical surface for a typical app is smaller than "major version" suggests — most of the churn is the continued stdlib-to-bundled-gem migration finally reaching some widely-used libraries.

## `ostruct` Leaves the Default Gems (the headline change)

`ostruct` (OpenStruct) stops being a *default* gem in Ruby 4.0 and becomes a *bundled* gem. The practical consequence under Bundler: `require "ostruct"` is no longer implicitly satisfied — the gem must be in the Gemfile or the require fails.

The trap is *who* requires it. It's frequently not your own code — it's a dependency, and in a Rails app it's **Rails' own boot path**: `zeitwerk` requires `ostruct`, so the app fails to **boot** on 4.0, not at some obscure app call site you might have refactored away.

- **Detection:** the Step 2 deprecation sweep run on 3.4 catches it ahead of time as `ostruct ... will no longer be part of the default gems starting from Ruby 4.0.0`, emitted from inside zeitwerk. This is exactly why the sweep runs on the *current* minor — the removal is announced a version early.
- **Fix:** add `gem "ostruct"` to the Gemfile. It's harmless on 3.4 and required on 4.0, so add it unconditionally (no `NextRails.next?` branch). See `references/known-gotchas.md`, "Default/bundled gems that stop being implicitly available" — the general rule is: when the consumer of a now-bundled gem is a *gem* (not your code), the fix is a Gemfile entry, not an app-level `require`.

Other stdlib libraries may make the same move in 4.0 — check the specific release notes; `ostruct` is the one confirmed here, not necessarily the only one for every app.

## Bundler That Ships With 4.0

Ruby 4.0 ships a Bundler in the 4.0.x line as its default. If your lock had a *higher* Bundler patch pinned than what 4.0 ships, a plain relock will quietly write the lower version into `BUNDLED WITH` — a downgrade hiding in the Ruby-hop diff. Check the direction and restore the higher pin with `bundle update --bundler=<version>` if needed (see `workflows/landing-workflow.md`, Step 4).

## What to Check Before Bumping

1. Run the deprecation sweep on 3.4 — the `ostruct` warning (and any sibling default-gem removals) shows up here.
2. Add `gem "ostruct"` (and any other flagged now-bundled gems) to the Gemfile before the boot smoke test, or boot will fail.
3. Boot smoke test is non-negotiable for a major bump — a green *unit* suite won't prove the app boots if a framework `require` breaks. Boot both the current and next boots if dual-booting.
4. Re-check `BUNDLED WITH` direction after relocking (above).
5. Confirm your analyzers know the new target — a `TargetRubyVersion 4.0` unknown-version abort is possible on older RuboCop/standard/RBS tooling (see `references/known-gotchas.md`). A sufficiently recent analyzer handles it fine; an old one aborts.
