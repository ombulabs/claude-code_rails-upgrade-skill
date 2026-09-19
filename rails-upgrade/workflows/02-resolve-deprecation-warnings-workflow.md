# Workflow 02: Resolve Deprecation Warnings

**Purpose:** Make deprecation warnings visible, collect the ones the current Rails version emits, and fix them on the current version before any dual-boot or version bump. Deprecation warnings are the roadmap of the next hop: what warns on X is what breaks on X+1. Fixing them on X, with the suite green on X, is the cheapest point in the campaign to do it, and it keeps the later diff (Workflow 10) about the version bump only.

**When to use:** After Workflow 01 has the app on the latest patch of its series. Before dual-boot setup (Workflow 04), so no `NextRails.next?` branching is needed: every fix here is an unconditional replacement that the current version already accepts.

## Inputs

- Green test baseline from Workflow 00, plus the result of its Step 2 sweep for deprecation-behavior overrides
- `references/deprecation-warnings-reference.md` (how to find, read and fix warnings, per Rails version)

## Outputs

- Deprecation inventory: every distinct warning the suite emitted on the current version, with count, first location and status (fixed / deferred with reason)
- Fixes applied on the current version, suite green after them
- The inventory is handed to Workflow 08 for the report's deprecation section

## Gates (must be true before the next workflow that runs)

- Deprecation warnings are visible in the test environment (no `:silence`, no `report_deprecations = false`, no override hiding them)
- Every warning emitted by the current Rails version about an API that changes at the target version is either fixed or deferred with a written reason in the inventory
- Test suite still passes (0 failures) after the fixes

## Pre-upgrade checklist (FastRuby.io best practices, recommended before starting any upgrade)

**Deprecation Warnings**
- [ ] Run app with Rails deprecations turned on (configured in config/environment files)
- [ ] Address existing deprecation warnings
- [ ] Enable verbose deprecations in test environment

## Step 1: Make sure deprecation warnings are not silenced

Read the Workflow 00 Step 2 sweep result. If anything silences or hides deprecations in the test environment (`config.active_support.deprecation = :silence`, `config.active_support.report_deprecations = false`, an `ActiveSupport::Deprecation.silence` block around suite setup, a `disallowed_warnings` list that swallows them), change the test environment so warnings reach the output:

```ruby
# config/environments/test.rb
config.active_support.deprecation = :stderr   # or :log if the team reads log/test.log; :raise is stricter
```

Prefer the least invasive change that makes warnings visible; do not turn on `:raise` in this step unless the team already uses it, because a raising suite hides every warning after the first. The behavior table and per-version forms are in `references/deprecation-warnings-reference.md`, section "Deprecation Configuration Options".

## Step 2: Run the suite and collect the warnings

Run the full suite once with output captured, then extract the distinct warnings:

```bash
bundle exec rails test 2>&1 | tee tmp/deprecations.log      # or: bundle exec rspec 2>&1 | tee tmp/deprecations.log
grep -h "DEPRECATION WARNING" tmp/deprecations.log | sed 's/^.*DEPRECATION WARNING: //' | sort | uniq -c | sort -rn
```

Record each distinct warning with its count and the first file:line the message names. For apps that will keep a running inventory across the campaign, `next_rails` ships `DeprecationTracker`; the dual-boot skill's `references/deprecation-tracking.md` shows the RSpec and Minitest setup. Optional here, useful from Workflow 04 on.

Also boot the app once outside the suite (`bin/rails runner 'puts Rails.version'`): initializer-time warnings do not always appear in test output.

## Step 3: Triage each warning

Keep two piles:

- **Fix now:** warnings emitted by the current Rails version about behavior or APIs that change at the target version. These are the reason this workflow exists.
- **Defer:** warnings about behavior scheduled to change two or more versions out, or warnings that come from a gem rather than the app (those are Workflow 06's concern, note the gem). Write the reason next to each deferred entry.

The version guide for this hop (`version-guides/upgrade-{FROM}-to-{TO}.md`) says what each warning becomes at the target version; `references/deprecation-warnings-reference.md`, section "Common Deprecation Patterns by Rails Version", has the usual fixes.

## Step 4: Fix the "fix now" pile on the current version

Apply each fix as an unconditional replacement: the current version already accepts the new form, that is what the warning says. No `NextRails.next?` branch, no dual-boot yet. One commit per warning type keeps the review readable. Re-run the affected tests after each fix and the full suite at the end.

## Step 5: Record the inventory

Write the inventory (fixed / deferred, counts, locations) where Workflow 08 will find it, for example `tmp/deprecation-inventory.md` or the notes location the user prefers. The upgrade report's deprecation section is built from it.

## Self-review checklist

- [ ] Test environment shows deprecation warnings (verified after Step 1, not assumed)
- [ ] Suite run captured; distinct warnings listed with counts
- [ ] Each warning is marked fixed or deferred with a reason
- [ ] Fixes are unconditional replacements, no version branching
- [ ] Suite green after the fixes
- [ ] Inventory saved for the report
