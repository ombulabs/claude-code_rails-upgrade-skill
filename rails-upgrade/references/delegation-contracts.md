# Delegation Contracts

Defines responsibility boundaries between `rails-upgrade` and its dependent skills. Read this when unsure which skill owns a step.

## Principle

`rails-upgrade` is the **orchestrator**. It drives the 7-step process end to end, but delegates bounded sub-tasks to specialist skills. Never reimplement logic owned by a dependent skill.

---

## Owned by `rails-upgrade`

- Step 0: Latest-patch verification (`Gemfile.lock` inspection, RubyGems API, static EOL table)
- Step 1: Baseline test suite run and pass/fail gate
- Step 3: Breaking-change detection (Grep/Glob/Read against `detection-scripts/patterns/*.yml`)
- Step 4: Comprehensive upgrade report + `app:update` preview generation
- Step 5: Gemfile version bump, implementation of breaking-change fixes, post-bump test runs, deploy coordination
- Multi-hop planning (sequence calculation, per-hop orchestration)
- Version-specific context loaded from `version-guides/upgrade-X.Y-to-A.B.md`

## Delegated to `dual-boot` skill — Step 2

**Scope (dual-boot owns):**
- Detecting existing `Gemfile.next` (avoid duplicate `next?` method definitions)
- Installing `next_rails` gem, running `next_rails --init`
- Generating and maintaining `Gemfile.next`
- `NextRails.next?` code patterns for version-branching in application code
- CI configuration for dual-boot builds
- Post-upgrade cleanup (removing `Gemfile.next`, `NextRails.next?` branches)

**Contract:**
- **Input from rails-upgrade:** current Rails version, target Rails version
- **Output back:** confirmation dual-boot is ready; `Gemfile` and `Gemfile.next` installed and bundling

**Do NOT reimplement in rails-upgrade:**
- Do not write `Gemfile.next` logic directly
- Do not suggest `respond_to?` as a substitute for `NextRails.next?`
- Do not document dual-boot CI config here — point to the dual-boot skill

## Delegated to `rails-load-defaults` skill — Step 6 (FINAL)

**Scope (rails-load-defaults owns):**
- Detecting current `load_defaults` value vs target Rails version
- Tiered config migration (Tier 1 low-risk, Tier 2 codebase-grep, Tier 3 human review)
- Running tests between each config flip
- Consolidation back into `config/application.rb`

**Contract:**
- **Input from rails-upgrade:** target Rails version (called AFTER version bump ships)
- **Output back:** `load_defaults` aligned to target version, tests green

**Do NOT reimplement in rails-upgrade:**
- Do not advise flipping `load_defaults` mid-upgrade
- Do not document per-config risk tiers here — that is the load_defaults skill's job

**Ordering rule:** `load_defaults` is the LAST step. Never before the Rails version bump is in production (or at minimum fully deployed in staging and tests pass).

---

## Anti-patterns (do not do these)

- Inlining dual-boot setup steps into the rails-upgrade workflow
- Showing `NextRails.next?` full examples in `SKILL.md` — reference the dual-boot skill instead
- Running `load_defaults` changes during Step 5 (implementation) — wrong phase
- Claiming rails-upgrade can handle dual-boot or load_defaults without the dependent skill installed
