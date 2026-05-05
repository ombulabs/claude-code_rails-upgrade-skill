# Project conventions for Claude

This file captures project-specific conventions Claude should follow when working in this repo.

## Repository tooling

- `bin/validate-patterns` validates every detection pattern YAML file under `rails-upgrade/detection-scripts/patterns/`. Run it before committing any change to a pattern file. Pure-stdlib Ruby, no Bundler or Gemfile required.
  - `bin/validate-patterns` validates every file
  - `bin/validate-patterns path/to/file.yml` validates one or more specific files
  - `bin/validate-patterns --self-test` runs built-in fixture assertions covering the four positive `kind:` values and the four rejection paths (missing top-level key, missing required pattern key, broken regex, unknown `kind:` value). CI runs this alongside the file-validation step
  - Checks: YAML parses, required top-level keys present, the eight required pattern keys present on each entry, every `pattern` / `exclude` regex compiles, and the `kind:` value is one of the allowed enum values (`breaking`, `deprecation`, `migration`, `optional`)
  - Exits 0 on success, 1 on any failure with a per-file error report

## Version guides (`rails-upgrade/version-guides/*.md`)

- **Do NOT include "Difficulty" or "Estimated Time" in the header.** These are subjective, application-dependent, and drift out of date. Keep the header minimal: title, Ruby requirement, and the attribution line.
- Base content on primary sources: the official Rails upgrade guide, the FastRuby.io blog, the OmbuLabs ebook chapter, and RailsDiff for the matching versions.
- Organize breaking changes under 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW priority sections.
- Each breaking change entry should include: "What Changed", a detection pattern, and a BEFORE/AFTER fix.
- Use `NextRails.next?` (never `respond_to?` or `Gem::Version` comparisons) in dual-boot code examples.

## Detection patterns (`rails-upgrade/detection-scripts/patterns/rails-*-patterns.yml`)

- File naming: `rails-{VERSION}-patterns.yml` where `{VERSION}` is the major+minor without a dot (e.g., `rails-42-patterns.yml` for Rails 4.2).
- Organize patterns under `high_priority`, `medium_priority`, and `low_priority`.
- Each pattern needs: `name`, `kind` (one of `breaking` / `deprecation` / `migration` / `optional` — see "Assigning kind" below), `pattern` (regex), `exclude` (regex, empty string if none), `search_paths`, `explanation`, `fix`, `variable_name`. Place `kind:` immediately after `name:` for visual scannability.
- Include a `dependencies` section for any bridge/compatibility gems mentioned in the guide.
- **Required before committing any change to a detection pattern file:** run `bin/validate-patterns` (or `bin/validate-patterns path/to/file.yml` for the file you touched). Do not commit a pattern change without a clean run; broken YAML or schema drift in this directory breaks the skill at runtime. See the `## Repository tooling` section above for what the script checks.

## Assigning priority (🔴 HIGH / 🟡 MEDIUM / 🟢 LOW)

Priority applies to both version guide sections and detection pattern entries. Assign based on **blast radius** and **reversibility**, not on how much code typically needs to change.

### 🔴 HIGH

A change belongs in HIGH when at least one of these is true:
- **Prevents boot, bundle, or test-suite startup** (e.g., a gem removed from Rails core that the app still requires; a renamed config key that raises on load).
- **Causes runtime errors in typical code paths** (e.g., a removed method that most apps call — `update_attributes`, `deliver`, `find_all_by_*`).
- **Required to upgrade at all** (Ruby version bump, mandatory base-class change like `ApplicationRecord`, removed DSL options that raise).
- **Silently wrong behavior with production impact** — data loss, security regression, broken auth/CSRF, or cache key mismatches that invalidate stored data.

If the user cannot complete the upgrade without addressing it, it is HIGH.

### 🟡 MEDIUM

A change belongs in MEDIUM when:
- **Affects many apps but not all** (gem extractions like `responders`, test-helper changes like `assigns`/`assert_template`).
- **Behavioral change in a commonly-used API** that usually works fine but has known edge-case breakage (HTML sanitizer output, serialized attribute nil handling, per-request CSRF tokens).
- **Config rename or relocation** that doesn't raise but should be updated for forward compatibility.

If the upgrade completes without it but a noticeable class of apps will see problems, it is MEDIUM.

### 🟢 LOW

A change belongs in LOW when:
- **Opt-in or optional improvement** (Timecop → `travel_to`, Foreigner → native FKs, adopting new Gemfile defaults).
- **Environment-specific config tweak** (`rails server` bind host, dev-only settings).
- **Cosmetic/tooling changes** (schema.rb column ordering, .gitignore recommendations, new `bin/setup` script).

If most apps will ignore it without consequence, it is LOW.

### How to decide when unsure

1. **Would a typical Rails app's test suite fail to run after the version bump without this fix?** → HIGH.
2. **Would the app boot and tests run, but produce a future blocker for a noticeable class of apps?** → MEDIUM.
3. **Would the app be unaffected unless the user opts into a new feature or runs in a specific environment?** → LOW.

Priority is about **urgency during an upgrade**, not editorial weight.

## Assigning `kind:` (`breaking` / `deprecation` / `migration` / `optional`)

`kind:` describes **what the change is**; `priority` describes **how urgent it is**. The two are orthogonal. A HIGH `deprecation` (silently wrong, like `DIRTY_TRACKING_AFTER_SAVE`) and a HIGH `breaking` (won't boot) are both "fix first" but for different reasons.

**Judge `kind` at the target hop, not the API's historical timeline.** Each `rails-XY-patterns.yml` file is a statement *about that hop* — what changes when the user upgrades INTO that version. A removal that was first deprecated in an earlier Rails minor is `breaking` in the file for the version where it actually raises, not `deprecation` because of its history. The same API can legitimately be `deprecation` in `rails-31-patterns.yml` and `breaking` in `rails-40-patterns.yml`. Apply the rule to all four kinds: `kind` reflects what the change *is at this hop*, not what it *was* earlier or *will become* later. (Concrete example: `SCOPE_WITHOUT_LAMBDA` was deprecated in Rails 3.1 and raises in 4.0 — it is `breaking` in `rails-40-patterns.yml`.)

The four values:

- **`breaking`** — Raises, removed, or prevents the app from booting / bundling / running its test suite. The user cannot complete the upgrade without addressing it. Example: `update_attributes` removed in 6.1, `redirect_to :back` removed in 5.1.
- **`deprecation`** — Works at this hop but emits a deprecation warning. Removal is scheduled for a later Rails version. Example: dynamic `:controller` route segments in 5.2, string `if:` conditions on callbacks.
- **`migration`** — Works today, no warning, but a recommended migration target. Adopting it now avoids rework on the next hop or an entirely new approach. Example: `Rails.application.secrets` → `credentials.yml.enc` in 5.2.
- **`optional`** — Opt-in feature or improvement. The user can ignore it without consequence. Example: `bootsnap`, `webpacker` in 5.1, `propshaft` adoption ahead of 8.0.

How to decide:

1. **Will the upgrade fail (boot, bundle, tests) without this fix?** → `breaking`.
2. **Does Rails emit a deprecation warning when this code runs at the target version?** → `deprecation`.
3. **Is this a recommended path forward (e.g. `secrets.yml` → `credentials.yml.enc`) that does not yet warn?** → `migration`.
4. **Is this purely opt-in / cosmetic / a new feature?** → `optional`.

If `kind` and `priority` seem to conflict, trust both. They answer different questions.

## How the `dependencies:` section relates to `kind`

The top-level `dependencies:` block in each `rails-*-patterns.yml` file is not bound to a single `kind` value. It serves two distinct purposes:

1. **Bridge / compatibility gems for `breaking` patterns** — gems that rescue functionality removed from Rails core, so the user can keep shipping while migrating call sites. A `breaking` pattern with a corresponding bridge entry is a *softenable* break: install the gem to keep the upgrade landing while migration happens separately. Examples:
   - `protected_attributes` rescues `attr_accessible` / `attr_protected` (4.0)
   - `activerecord-deprecated_finders` rescues removed dynamic finders (4.0)
   - `rails-observers` rescues `ActiveRecord::Observer` and `ActionController::Caching::Sweeper` (4.0)
   - `responders` rescues `respond_with` and class-level `respond_to` (4.2)
   - `rails-controller-testing` rescues `assigns` / `assert_template` (5.0)

2. **New gems Rails introduces or recommends at this version** — gems that are not in the previous version's Gemfile. These pair with `optional` patterns (the user can ignore them) or with no pattern at all. Examples:
   - `bootsnap` (5.2), `web-console` (4.2), `webpacker` (5.1)
   - `propshaft` (8.0), `solid_cache` / `solid_queue` / `solid_cable` (8.0)
   - `kamal` (8.0), `bundler-audit` (8.1)

The `check: true` / `check: false` flag on each `dependencies:` entry distinguishes "you should add this" from "you may add this". `check: true` is typically a bridge gem that's required to rescue a `breaking` pattern the app actually triggers; `check: false` is typically opt-in (either a bridge for a `breaking` the app may not trigger, or a new-default gem the user can adopt at their own pace).

`kind: deprecation`, `migration`, and `optional` patterns are resolved in code via the per-pattern `fix:` field, not via `dependencies:`.
