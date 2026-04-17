---
name: rails-upgrade
description: Analyzes Rails applications and generates comprehensive upgrade reports with breaking changes, deprecations, and step-by-step migration guides for Rails 2.3 through 8.1. Use when upgrading Rails applications, planning multi-hop upgrades, or querying version-specific changes. Based on FastRuby.io methodology and "The Complete Guide to Upgrade Rails" ebook.
---

# Rails Upgrade Assistant Skill

## Skill Identity
- **Name:** Rails Upgrade Assistant
- **Purpose:** Intelligent Rails application upgrades from 2.3 through 8.1
- **Skill Type:** Modular with external workflows and examples
- **Upgrade Strategy:** Sequential only (no version skipping)
- **Methodology:** Based on FastRuby.io upgrade best practices and "The Complete Guide to Upgrade Rails" ebook
- **Attribution:** Content based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)

---

## Dependencies

- **dual-boot skill** ([github.com/ombulabs/claude-code_dual-boot-skill](https://github.com/ombulabs/claude-code_dual-boot-skill)) — Sets up and manages dual-boot environments using the `next_rails` gem. Covers setup, `NextRails.next?` code patterns, CI configuration, and post-upgrade cleanup. Must be installed for Step 2 of the upgrade workflow.
- **rails-load-defaults skill** ([github.com/ombulabs/claude-code_rails-load-defaults-skill](https://github.com/ombulabs/claude-code_rails-load-defaults-skill)) — Handles incremental `load_defaults` updates with tiered risk assessment (Tier 1: low-risk, Tier 2: needs codebase grep, Tier 3: requires human review). Used as the final step after the Rails version upgrade is complete.

---

## Core Methodology (FastRuby.io Approach)

This skill follows the proven FastRuby.io upgrade methodology:

1. **Incremental Upgrades** - Always upgrade one minor/major version at a time
2. **Assessment First** - Understand scope before making changes
3. **Dual-Boot Testing** - Test both versions during transition using `next_rails` gem
4. **Test Coverage** - Ensure adequate test coverage before upgrading (aim for 80%+)
5. **Gem Compatibility** - Check gem compatibility at each step using RailsBump
6. **Deprecation Warnings** - Address deprecations before upgrading
7. **Backwards Compatible Changes** - Deploy small changes to production before version bump

**Key Resources:**
- **DELEGATE** to the `dual-boot` skill for dual-boot setup with `next_rails` (see Dependencies)
- See `references/deprecation-warnings.md` for managing deprecations
- See `references/staying-current.md` for maintaining upgrades over time

---

## CRITICAL: Dual-Boot Code Pattern with `NextRails.next?`

When proposing code fixes that must work with both the current and target Rails versions (dual-boot), **always use `NextRails.next?` from the `next_rails` gem** — never use `respond_to?` or other feature-detection patterns.

**DELEGATE** to the `dual-boot` skill for:
- Setup and initialization (`next_rails --init`, `Gemfile.next`)
- `NextRails.next?` code patterns and examples
- CI configuration for dual-boot testing
- Post-upgrade cleanup (removing dual-boot branches)

**DEPENDENCY:** Requires the [dual-boot skill](https://github.com/ombulabs/claude-code_dual-boot-skill)

---

## Core Workflow

Follows the FastRuby.io methodology: current-version deprecations are the primary signal for what breaks next version, fix the build in dependency order, and treat `load_defaults` alignment as optional post-upgrade work.

### Step 1: Run Test Suite
- Run the existing test suite on the current Rails. All tests must pass before proceeding.
- Ensure deprecation warnings are NOT silenced in the test environment before running. Reconfigure to `:stderr` or `:log` if needed so Step 3 has the full list.
- Run `bundle exec rspec` or `bundle exec rails test`.
- If tests fail, stop and help fix them first.
- Record test count, coverage, and the deprecation-warning list as baseline.
- See `workflows/test-suite-verification-workflow.md`.

### Step 2: Verify Latest Patch Version
- Before hopping minor/major, verify the app is on the latest patch of its current Rails series.
- Read `Gemfile.lock` for the exact current Rails version.
- Compare against the latest patch for that series:
  - **EOL series (≤ 7.1):** static table in `references/multi-hop-strategy.md`.
  - **Active series (≥ 7.2):** query RubyGems at runtime (commands in the same reference).
- If not on latest patch: update the Gemfile, run `bundle update rails`, run tests, deploy the patch, then proceed.
- **Why:** patch releases contain security fixes, bug fixes, and additional deprecation warnings that make the next hop safer.

### Step 3: Resolve Deprecation Warnings
- **DELEGATE** to `workflows/deprecation-resolution-workflow.md`.
- Methodology: regex search, `next_rails` deprecation tooling, `synvert-ruby`, prefer backward-compatible fixes over `NextRails.next?` conditionals when possible.
- Goal: the deprecation list from Step 1 is empty (or down to known, justified exceptions) before introducing the next Rails version.

### Step 4: Review Ruby Compatibility
- Verify the current Ruby meets the target Rails' minimum Ruby version.
- Check `Gemfile`, `.ruby-version`, `.tool-versions`, and `ruby --version`.
- If Ruby needs bumping, handle it as a separate upgrade before continuing.

### Step 5: Set Up Dual-Boot
- **DELEGATE** to the `dual-boot` skill.
- Contract: working `Gemfile.next`, boot confirmed on both Gemfiles (`rails runner 'puts Rails.version'` on each), model suite passes on `Gemfile.next`.
- **DEPENDENCY:** [dual-boot skill](https://github.com/ombulabs/claude-code_dual-boot-skill).

### Step 6: Run Breaking Changes Detection
- Claude runs detection directly using Grep/Glob/Read — no script generation.
- Load `detection-scripts/patterns/rails-{VERSION}-patterns.yml` and `version-guides/upgrade-{FROM}-to-{TO}.md` for context.
- Collect findings with file:line references. See `workflows/direct-detection-workflow.md`.
- Generate the Comprehensive Upgrade Report and `app:update` Preview from actual findings (templates in `templates/`).

### Step 7: Fix Broken Build
Fix-order discipline:
- **Errors before failures** — errors can mask failures.
- **Unit → integration → system** — a broken unit suite produces noise everywhere else.
- **RSpec:** Models → Services → Mailers → Helpers → Controllers → Integration → System.
- **Minitest:** Models → Mailers → Helpers → Controllers → Integration → System.

Use `NextRails.next?` for code that must work on both versions (DELEGATE to dual-boot for patterns). Do not fix deprecations printed by the next version here — those belong in the next upgrade's Step 3.

### Step 8: Smoke Test
Broader than `rails runner`. On `Gemfile.next`:
- Open a Rails console.
- Start the Rails server.
- Start background workers (sidekiq, sucker_punch, delayed_job) — check `Procfile` for what's expected.
- Run `assets:precompile` in production mode.

### Step 9: Remove Dual-Boot
- **DELEGATE** to the `dual-boot` cleanup contract.
- Removes `Gemfile.next`, drops `next_rails`, collapses remaining `NextRails.next?` call sites, consolidates CI to a single bundle.

### Step 10: Align `load_defaults` (OPTIONAL, post-upgrade)
- **Optional and separate from the upgrade.** The upgrade is complete at Step 9. Users may run this later once the target version is stable in production.
- **Do NOT** invoke `bin/rails app:update`'s defaults hunk as part of the upgrade.
- **DELEGATE** to the `rails-load-defaults` skill when the user chooses to run it.
- **DEPENDENCY:** [rails-load-defaults skill](https://github.com/ombulabs/claude-code_rails-load-defaults-skill).

---

## Trigger Patterns

Claude should activate this skill when user says:

**Upgrade Requests:**
- "Upgrade my Rails app to [version]"
- "Help me upgrade from Rails [x] to [y]"
- "What breaking changes are in Rails [version]?"
- "Plan my upgrade from [x] to [y]"
- "What Rails version am I using?"
- "Analyze my Rails app for upgrade"
- "Find breaking changes in my code"
- "Check my app for Rails [version] compatibility"

**Specific Report Requests:**
- "Show me the app:update changes"
- "Preview configuration changes for Rails [version]"
- "Generate the upgrade report"
- "What will change if I upgrade?"

---

## CRITICAL: Sequential Upgrade Strategy

### ⚠️ Version Skipping is NOT Allowed

Rails upgrades MUST follow a sequential path. Examples:

**For Rails 5.x to 8.x:**
```
5.0.x → 5.1.x → 5.2.x → 6.0.x → 6.1.x → 7.0.x → 7.1.x → 7.2.x → 8.0.x → 8.1.x
```

**You CANNOT skip versions.** Examples:
- ❌ 5.2 → 6.1 (skips 6.0)
- ❌ 6.0 → 7.0 (skips 6.1)
- ❌ 7.0 → 8.0 (skips 7.1 and 7.2)
- ✅ 5.2 → 6.0 (correct)
- ✅ 7.0 → 7.1 (correct)
- ✅ 7.2 → 8.0 (correct)

If user requests a multi-hop upgrade (e.g., 5.2 → 8.1):
1. Explain the sequential requirement
2. Break it into individual hops
3. Generate separate reports for each hop
4. Recommend completing each hop fully before moving to next

---

## Supported Upgrade Paths

### Legacy Rails (2.3 - 4.2)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 2.3.x | 3.0.x | Very Hard | XSS protection, routes syntax | 1.8.7 - 1.9.3 |
| 3.0.x | 3.1.x | Medium | Asset pipeline, jQuery | 1.8.7 - 1.9.3 |
| 3.1.x | 3.2.x | Easy | Ruby 1.9.3 support | 1.8.7 - 2.0 |
| 3.2.x | 4.0.x | Hard | Strong Parameters, Turbolinks | 1.9.3+ |
| 4.0.x | 4.1.x | Medium | Spring, secrets.yml | 1.9.3+ |
| 4.1.x | 4.2.x | Medium | ActiveJob, Web Console | 1.9.3+ |
| 4.2.x | 5.0.x | Hard | ActionCable, API mode, ApplicationRecord | 2.2.2+ |

### Modern Rails (5.0 - 8.1)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 5.0.x | 5.1.x | Easy | Encrypted secrets, yarn default | 2.2.2+ |
| 5.1.x | 5.2.x | Medium | Active Storage, credentials | 2.2.2+ |
| 5.2.x | 6.0.x | Hard | Zeitwerk, Action Mailbox/Text | 2.5.0+ |
| 6.0.x | 6.1.x | Medium | Horizontal sharding, strict loading | 2.5.0+ |
| 6.1.x | 7.0.x | Hard | Hotwire/Turbo, Import Maps | 2.7.0+ |
| 7.0.x | 7.1.x | Medium | Composite keys, async queries | 2.7.0+ |
| 7.1.x | 7.2.x | Medium | Transaction-aware jobs, DevContainers | 3.1.0+ |
| 7.2.x | 8.0.x | Very Hard | Propshaft, Solid gems, Kamal | 3.2.0+ |
| 8.0.x | 8.1.x | Easy | Bundler-audit, max_connections | 3.2.0+ |

---

## Available Resources

### Core Documentation
- `SKILL.md` - This file (entry point)

### Version-Specific Guides (Load as needed)

**Legacy Rails:**
- `version-guides/upgrade-3.2-to-4.0.md` - Rails 3.2 → 4.0 (Strong Parameters)
- `version-guides/upgrade-4.2-to-5.0.md` - Rails 4.2 → 5.0 (ApplicationRecord)

**Modern Rails:**
- `version-guides/upgrade-5.0-to-5.1.md` - Rails 5.0 → 5.1 (Encrypted secrets)
- `version-guides/upgrade-5.1-to-5.2.md` - Rails 5.1 → 5.2 (Active Storage, Credentials)
- `version-guides/upgrade-5.2-to-6.0.md` - Rails 5.2 → 6.0 (Zeitwerk)
- `version-guides/upgrade-6.0-to-6.1.md` - Rails 6.0 → 6.1 (Horizontal sharding)
- `version-guides/upgrade-6.1-to-7.0.md` - Rails 6.1 → 7.0 (Hotwire/Turbo)
- `version-guides/upgrade-7.0-to-7.1.md` - Rails 7.0 → 7.1 (Composite keys)
- `version-guides/upgrade-7.1-to-7.2.md` - Rails 7.1 → 7.2 (Transaction jobs)
- `version-guides/upgrade-7.2-to-8.0.md` - Rails 7.2 → 8.0 (Propshaft)
- `version-guides/upgrade-8.0-to-8.1.md` - Rails 8.0 → 8.1 (bundler-audit)

### Workflow Guides (Load when generating deliverables)
- `workflows/test-suite-verification-workflow.md` - **MANDATORY FIRST STEP** - How to run and verify test suite
- `workflows/direct-detection-workflow.md` - How to run breaking change detection directly
- `workflows/upgrade-report-workflow.md` - How to generate upgrade reports
- `workflows/app-update-preview-workflow.md` - How to generate app:update previews

### Examples (Load when user needs clarification)
- `examples/simple-upgrade.md` - Single-hop upgrade example
- `examples/multi-hop-upgrade.md` - Multi-hop upgrade example

### External Dependencies
- **dual-boot skill** - Dual-boot setup (Step 5) and removal (Step 9) (https://github.com/ombulabs/claude-code_dual-boot-skill)
- **rails-load-defaults skill** - Optional `load_defaults` alignment, post-upgrade (Step 10) (https://github.com/ombulabs/claude-code_rails-load-defaults-skill)

### Reference Materials
- `references/deprecation-warnings.md` - Finding and fixing deprecations
- `references/staying-current.md` - Keeping up with Rails releases
- `references/breaking-changes-by-version.md` - Quick lookup
- `references/multi-hop-strategy.md` - Multi-version planning
- `references/testing-checklist.md` - Comprehensive testing
- `references/gem-compatibility.md` - Common gem version requirements

### Detection Pattern Resources
- `detection-scripts/patterns/rails-*.yml` - Version-specific patterns for direct detection

### Report Templates
- `templates/upgrade-report-template.md` - Main upgrade report structure
- `templates/app-update-preview-template.md` - Configuration preview

---

## Pre-Upgrade Checklist (FastRuby.io Best Practices)

Before starting ANY upgrade:

### 1. Test Coverage Assessment (AUTOMATED - Step 1 of Workflow)
- [x] Run test suite - all tests passing? **← Claude runs this automatically**
- [x] Check test coverage (aim for >70%) **← Claude captures this if SimpleCov is configured**
- [ ] Review critical paths have coverage

**Note:** This step is now automated. Claude will run the test suite and BLOCK the upgrade if any tests fail.

### 2. Dependency Audit
- [ ] Run `bundle outdated`
- [ ] Check gem compatibility with target Rails version
- [ ] Identify gems that need upgrading first

### 3. Database Backup
- [ ] Backup production database
- [ ] Backup development/staging databases
- [ ] Verify backup restore process works

### 4. Git Branch Strategy
- [ ] Create upgrade branch from main/master
- [ ] Set up CI for upgrade branch
- [ ] Plan merge strategy

### 5. Deprecation Warnings
- [ ] Run app with Rails deprecations turned on (configured in config/environment files)
- [ ] Address existing deprecation warnings
- [ ] Enable verbose deprecations in test environment

---

## Common Request Patterns

### Pattern 1: Full Upgrade Request
**User says:** "Upgrade my Rails app to 8.1"

Run the full Core Workflow (Steps 1–9). Step 10 (`load_defaults`) is optional and can be deferred until the target version is stable in production.

### Pattern 2: Multi-Hop Request
**User says:** "Help me upgrade from Rails 5.2 to 8.1"

Upgrades must be sequential (see "CRITICAL: Sequential Upgrade Strategy" below). For each hop, run Steps 1–9 from scratch. Step 2's latest-patch check re-applies before each hop. Step 10 is optional per hop — typically run once at the end of the chain, not between hops.

### Pattern 3: Breaking Changes Analysis Only
**User says:** "What breaking changes affect my app for Rails 8.0?"

Run Steps 1, 2, and 6 to produce the Comprehensive Upgrade Report and `app:update` Preview without executing the upgrade. Offer to continue with Steps 3–9 when ready.

---

## Quality Checklist

Before delivering, verify:

**For Direct Detection:**
- [ ] All patterns from version-specific YAML file checked
- [ ] Grep/Glob tools used correctly for each pattern
- [ ] File:line references collected for all findings
- [ ] Context captured for each finding

**For Comprehensive Upgrade Report:**
- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] Used ACTUAL findings from direct detection (not generic examples)
- [ ] Breaking changes section includes real file:line references
- [ ] Custom code warnings based on actual detected issues
- [ ] Code examples use user's actual code from affected files
- [ ] Next steps clearly outlined

**For app:update Preview:**
- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] File list matches user's actual config files
- [ ] Diffs based on real current config vs target version
- [ ] Next steps clearly outlined

---

## Key Principles

1. **Run the test suite first** — no upgrade work until the current-Rails suite is green. Baseline deprecation warnings go in the record.
2. **Resolve deprecations before hopping** — current-version deprecations are the primary signal for what breaks next. Fix them before introducing the next Rails.
3. **Dual-boot bridges the transition** — `Gemfile.next` keeps the current Rails bootable while you fix the target. Use `NextRails.next?` for code that must work on both; never `respond_to?`.
4. **Fix the build in dependency order** — errors before failures, unit → integration → system. A broken unit suite produces noise everywhere else.
5. **Smoke test beyond `rails runner`** — console, server, workers, and `assets:precompile` all need to boot on `Gemfile.next` before removing it.
6. **Remove dual-boot when done** — DELEGATE to the `dual-boot` cleanup contract. Collapse `NextRails.next?` call sites; don't leave the conditional machinery behind.
7. **`load_defaults` is optional, post-upgrade** — do NOT invoke `bin/rails app:update`'s defaults hunk as part of the upgrade. Align later, incrementally, when the target is stable in production.
8. **Upgrades are sequential** — no version skipping (see "CRITICAL: Sequential Upgrade Strategy").
9. **Detect directly, report from real findings** — Grep/Glob/Read on the actual codebase. No generic examples in reports; always flag custom code with ⚠️.

---

## Success Criteria

A successful upgrade assistance session:

✅ Ran test suite on current Rails; all tests pass; deprecation list captured (Step 1)
✅ App is on the latest patch of its current series before any minor/major hop (Step 2)
✅ Deprecation warnings resolved before introducing the next Rails (Step 3)
✅ Ruby version meets target Rails' minimum (Step 4)
✅ Dual-boot set up; both Gemfiles boot; model suite green on `Gemfile.next` (Step 5)
✅ Breaking changes detected directly; Comprehensive Upgrade Report and `app:update` Preview generated from real findings (Step 6)
✅ Build green on target Rails, fixed in error-first / unit→integration→system order (Step 7)
✅ Smoke test passed on `Gemfile.next`: console, server, workers, `assets:precompile` (Step 8)
✅ Dual-boot removed; `NextRails.next?` call sites collapsed; CI back to a single bundle (Step 9)
✅ `load_defaults` alignment deferred as optional post-upgrade work (Step 10)

---

See [CHANGELOG.md](CHANGELOG.md) for version history and current version.
