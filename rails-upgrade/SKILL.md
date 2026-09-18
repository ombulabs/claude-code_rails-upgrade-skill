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

## Terminology

| Term | Meaning | Where |
|------|---------|-------|
| **Workflow** | One numbered unit of the upgrade flow, one file | `workflows/<NN>-<name>-workflow.md` |
| **Step** | A `Step N` header inside a workflow file | inside the workflow |
| **Reference** | Material loaded on demand: lookup tables, playbooks, conditional branches | `references/<name>-reference.md` |

No sub-steps: a "Step 4.1" is either two sequential steps or a conditional branch inside one step (`### A.` / `### B.` headers). Refer to a whole workflow as Workflow NN; refer to a step as file path plus step, e.g. `workflows/01-run-test-suite-workflow.md` Step 4. Not used in headings: Stage, Phase, Sub-step, dotted step numbers.

---

## Dependencies

- **dual-boot skill** ([github.com/ombulabs/claude-code_dual-boot-skill](https://github.com/ombulabs/claude-code_dual-boot-skill)) — Sets up and manages dual-boot environments using the `next_rails` gem. Covers setup, `NextRails.next?` code patterns, CI configuration, and post-upgrade cleanup. Must be installed for Workflow 02 (`workflows/02-setup-next-rails-workflow.md`).
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
- See `references/deprecation-warnings-reference.md` for managing deprecations
- See `references/staying-current-reference.md` for maintaining upgrades over time

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

## Available Resources

### Core Documentation
- `SKILL.md` - This file (entry point)

### Version-Specific Guides (Load as needed)

**Legacy Rails:**
- `version-guides/upgrade-3.2-to-4.0.md` - Rails 3.2 → 4.0 (Strong Parameters)
- `version-guides/upgrade-4.0-to-4.1.md` - Rails 4.0 → 4.1 (Spring, secrets.yml, enums)
- `version-guides/upgrade-4.1-to-4.2.md` - Rails 4.1 → 4.2 (ActiveJob, Web Console)
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

### Examples (Load when user needs clarification)
- `examples/simple-upgrade.md` - Single-hop upgrade example
- `examples/multi-hop-upgrade.md` - Multi-hop upgrade example

### External Dependencies
- **dual-boot skill** - Dual-boot setup and management with next_rails (Workflow 02) (https://github.com/ombulabs/claude-code_dual-boot-skill)
- **rails-load-defaults skill** - Incremental load_defaults alignment (Workflow 11) (https://github.com/ombulabs/claude-code_rails-load-defaults-skill)
- **`upgrade-cleanup` companion plugin** - User-triggered. Removes dual-boot scaffolding and drops `NextRails.next?` / `NextRails.current?` branches. Deprecation triage stays with this skill for the next hop.

### Reference Materials
- `references/sequential-strategy-reference.md` - Sequential upgrade rule (no version skipping) and the supported upgrade paths tables. Load in Workflow 03.
- `references/request-patterns-reference.md` - Which workflows run for each request shape (full upgrade, multi-hop, analysis only, reports only). Read at the start of a session.
- `references/no-test-suite-smoke-reference.md` - **Load from Workflow 01 when no runnable RSpec/Minitest suite exists** - Rails boot, routes, migration-status, and build smoke baseline with partial-confidence reporting
- `references/deprecation-warnings-reference.md` - Finding and fixing deprecations
- `references/staying-current-reference.md` - Keeping up with Rails releases
- `references/breaking-changes-by-version-reference.md` - Quick lookup
- `references/multi-hop-strategy-reference.md` - Multi-version planning
- `references/testing-checklist-reference.md` - Comprehensive testing
- `references/gem-compatibility-reference.md` - Gem update order and the "no compatible version" playbook (fork / vendor / replace). Load only when Workflow 05's compatibility check produced blockers.
- `references/js-compressor-sprockets-mismatch-reference.md` - Keeping terser / closure-compiler working when the target Rails pins Sprockets to the 2.x line. Load only when JS_COMPRESSOR_GEM_MISMATCH fires.

### Detection Pattern Resources
- `detection-scripts/patterns/rails-*.yml` - Version-specific patterns for direct detection

### Report Templates
- `templates/upgrade-report-template.md` - Main upgrade report structure
- `templates/app-update-preview-template.md` - Configuration preview

---

## Workflow index

When user requests an upgrade, follow this workflow. Sequential Process is Critical: run in order, read each file when you reach it. Gates block.

| #  | Name | Purpose | File |
|----|------|---------|------|
| 00 | Verify latest patch | MANDATORY PRE-STEP. App on the latest patch of its current series before any minor/major hop | `workflows/00-verify-latest-patch-workflow.md` |
| 01 | Run test suite | MANDATORY FIRST STEP. How to run and verify test suite; blocks on any failure | `workflows/01-run-test-suite-workflow.md` |
| 02 | Set up next_rails | EARLY SETUP. Delegated to the skill listed under External Dependencies | `workflows/02-setup-next-rails-workflow.md` |
| 03 | Validate upgrade path | Single-hop or multi-hop, individual hops planned | `workflows/03-validate-upgrade-path-workflow.md` |
| 04 | Detect breaking changes | How to run breaking change detection directly | `workflows/04-detect-breaking-changes-workflow.md` |
| 05 | Check gem compatibility | Per-lockfile gem compatibility check against the target Rails version | `workflows/05-check-gem-compatibility-workflow.md` |
| 06 | Boot smoke test | Run a Rails-loading command against `Gemfile.next` to catch gem-level runtime incompat that the resolver can't see | `workflows/06-boot-smoke-test-workflow.md` |
| 07 | Generate upgrade report | How to generate upgrade reports | `workflows/07-generate-upgrade-report-workflow.md` |
| 08 | Generate app:update preview | How to generate app:update previews | `workflows/08-generate-app-update-preview-workflow.md` |
| 09 | Implement and upgrade | Present reports, apply fix-before-bump changes, bump the Gemfile, run tests against both versions | `workflows/09-implement-and-upgrade-workflow.md` |
| 10 | Sync CI config | MANDATORY before opening the upgrade PR. How to verify CI config matches the upgraded Gemfile | `workflows/10-sync-ci-workflow.md` |
| 11 | Align load_defaults | AFTER THE UPGRADE IS COMPLETE. Delegates to the rails-load-defaults skill | `workflows/11-align-load-defaults-workflow.md` |
| 12 | Mention cleanup | USER-TRIGGERED. Delegates to the `upgrade-cleanup` plugin only when the user explicitly asks | `workflows/12-mention-cleanup-workflow.md` |

The Purpose column is a summary. Gates live only in each workflow's `## Gates` section. Which workflows run depends on the request shape (full upgrade, multi-hop, analysis only, reports only): `references/request-patterns-reference.md`.

---

## Key Principles

1. **Run Detection Directly** (use Grep/Glob/Read tools - no script generation needed)
2. **Load Workflows as Needed** (don't hold everything in memory)
3. **Follow FastRuby.io Methodology** (incremental upgrades, assessment first)

Everything else that used to be listed here lives in the workflow it governs: see each workflow's Purpose and Gates.
