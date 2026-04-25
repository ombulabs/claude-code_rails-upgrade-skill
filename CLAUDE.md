# Project conventions for Claude

This file captures project-specific conventions Claude should follow when working in this repo.

## Repository tooling

- `bin/validate-patterns` validates every detection pattern YAML file under `rails-upgrade/detection-scripts/patterns/`. Run it before committing any change to a pattern file. Pure-stdlib Ruby, no Bundler or Gemfile required.
  - `bin/validate-patterns` validates every file
  - `bin/validate-patterns path/to/file.yml` validates one or more specific files
  - Checks: YAML parses, required top-level keys present, the seven required pattern keys present on each entry, and every `pattern` / `exclude` regex compiles
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
- Each pattern needs: `name`, `pattern` (regex), `exclude` (regex, empty string if none), `search_paths`, `explanation`, `fix`, `variable_name`.
- Include a `dependencies` section for any bridge/compatibility gems mentioned in the guide.
- Verify the file before committing with `bin/validate-patterns` (validates every pattern file) or `bin/validate-patterns path/to/file.yml` (single file). The script checks YAML parses, the seven required pattern keys are present, and each `pattern` / `exclude` regex compiles.

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
