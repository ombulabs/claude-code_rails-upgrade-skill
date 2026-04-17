---
name: rails-upgrade
description: Analyzes Rails applications and generates comprehensive upgrade reports with breaking changes, deprecations, and step-by-step migration guides for Rails 2.3 through 8.1. Use when upgrading Rails applications, planning multi-hop upgrades, or querying version-specific changes. Based on FastRuby.io methodology and "The Complete Guide to Upgrade Rails" ebook.
---

# Rails Upgrade Assistant

Orchestrates Rails upgrades following the FastRuby.io methodology. Owns the end-to-end 7-step workflow. Delegates dual-boot and `load_defaults` work to dedicated skills.

- **Strategy:** Sequential only, no version skipping
- **Scope:** Rails 2.3 through 8.1
- **Attribution:** "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)

---

## Dependencies

Both must be installed:

- **dual-boot** ([repo](https://github.com/ombulabs/claude-code_dual-boot-skill)) — Owns Step 2 (dual-boot setup) and all `NextRails.next?` code patterns.
- **rails-load-defaults** ([repo](https://github.com/ombulabs/claude-code_rails-load-defaults-skill)) — Owns Step 6 (final `load_defaults` alignment).

Read `references/delegation-contracts.md` when unsure which skill owns a given sub-task. Do not reimplement logic owned by a dependent skill.

---

## Core Workflow (7 Steps)

### Step 0: Verify Latest Patch — MANDATORY PRE-STEP

- Read `Gemfile.lock` → exact current Rails version
- Compare against latest patch for the series:
  - EOL series (≤ 6.1): use static table in `references/multi-hop-strategy.md`
  - Active series (≥ 7.0): query RubyGems API (commands in `references/multi-hop-strategy.md`)
- If behind latest patch: guide user through patch upgrade + test run + deploy BEFORE any minor/major hop
- **Why:** patch releases add deprecation warnings and bug fixes that make the next hop safer

### Step 1: Baseline Test Suite — MANDATORY

- Run `bundle exec rspec` or `bundle exec rails test`
- Record baseline: total, pass/fail, coverage if SimpleCov configured
- If any test fails → STOP. Help fix before proceeding.
- Details: `workflows/test-suite-verification-workflow.md`

### Step 2: Dual-Boot Setup — DELEGATE

- Delegate to `dual-boot` skill. It owns `Gemfile.next`, `next_rails`, and CI config.
- Contract and boundaries: `references/delegation-contracts.md`

### Step 3: Breaking-Change Detection

- Claude runs detection directly with Grep/Glob/Read. No script generation.
- Patterns: `detection-scripts/patterns/rails-{VERSION}-patterns.yml`
- Workflow: `workflows/direct-detection-workflow.md`
- Context: `version-guides/upgrade-{FROM}-to-{TO}.md`

### Step 4: Generate Reports

Two deliverables:

1. **Comprehensive Upgrade Report** — breaking changes with OLD/NEW code from user's files, custom-code ⚠️ flags, migration plan
2. **`app:update` Preview** — exact config diffs, new files, HIGH/MED/LOW impact

Workflows: `workflows/upgrade-report-workflow.md`, `workflows/app-update-preview-workflow.md`. Templates: `templates/*.md`.

### Step 5: Implement + Bump Rails

- Fix breaking changes. Use `NextRails.next?` for dual-boot code (delegate patterns to dual-boot skill).
- Update `Gemfile` to target version.
- Run suite against both Rails versions during transition.
- Deploy and verify.

### Step 6: Align `load_defaults` — FINAL, DELEGATE

- Delegate to `rails-load-defaults`. It owns tiered incremental config migration.
- Runs AFTER the Rails version bump is complete and deployed (or fully green in staging).
- **Ordering rule:** never before Step 5.

---

## Core Methodology (FastRuby.io)

1. Incremental upgrades, one minor/major at a time
2. Assessment before changes
3. Dual-boot during transition
4. Adequate test coverage (aim 80%+) before starting
5. Gem compatibility checked per hop (see `references/gem-compatibility.md`)
6. Deprecation warnings addressed before hop (see `references/deprecation-warnings.md`)
7. Small backwards-compatible changes shipped to prod before version bump

---

## Conditional Loads

Load on demand, not upfront:

- `references/delegation-contracts.md` — when unsure which skill owns a step
- `references/trigger-patterns.md` — when classifying the user's request type
- `references/sequential-strategy.md` — when planning hops or validating the requested jump
- `references/multi-hop-strategy.md` — when upgrade spans 2+ versions, or checking latest patch for a series
- `references/gem-compatibility.md` — when assessing a specific gem against the target version
- `references/deprecation-warnings.md` — when addressing deprecations raised in Step 1
- `references/breaking-changes-by-version.md` — quick lookup of breaking changes by version
- `references/testing-checklist.md` — when validating coverage before Step 1
- `references/staying-current.md` — when user asks about keeping up post-upgrade
- `version-guides/upgrade-X.Y-to-A.B.md` — at the start of each specific hop
- `workflows/*.md` — when executing the corresponding step
- `examples/*.md` — when user needs a worked example

---

## Key Principles

1. Step 0 and Step 1 are mandatory gates. No exceptions.
2. Dual-boot is Step 2, stays active through all hops in a multi-hop session.
3. Detection runs directly with tools. No generated scripts.
4. Reports use actual findings from user's code. No generic examples.
5. `load_defaults` is LAST. Never mid-upgrade.
6. Use `NextRails.next?` for dual-boot code, never `respond_to?`.
7. Respect delegation contracts. Do not reimplement dual-boot or load_defaults logic here.

---

See [CHANGELOG.md](CHANGELOG.md) for version history.
