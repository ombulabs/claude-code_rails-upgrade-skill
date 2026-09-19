# Workflow 09: Implement and Upgrade

**Purpose:** Present both reports, apply the fix-before-bump changes, bump the Gemfile to the target Rails version and verify against both versions.

**When to use:** After both reports are generated.

## Inputs

- Comprehensive Upgrade Report (from Workflow 07)
- app:update Preview (from Workflow 08)

## Outputs

- Fix-before-bump changes applied
- Gemfile on the target Rails version
- Test suite green against both versions

## Gates (must be true before the next workflow that runs)

- Test suite passes against both versions. CI config is checked by Workflow 10, which runs next and has its own gate

## Pre-upgrade checklist (FastRuby.io best practices, recommended before starting any upgrade)

**Database Backup**
- [ ] Backup production database
- [ ] Backup development/staging databases
- [ ] Verify backup restore process works

**Git Branch Strategy**
- [ ] Create upgrade branch from main/master
- [ ] Set up CI for upgrade branch
- [ ] Plan merge strategy

## Step 1: Present Comprehensive Upgrade Report first

## Step 2: Present app:update Preview Report second

## Step 3: Apply fix-before-bump changes

Apply fix-before-bump changes (`kind: breaking` and `kind: deprecation`). Most fixes are direct rewrites — the new API typically works on both sides of the dual-boot pair (e.g., `update_attributes` → `update`). Use `NextRails.next?` only when the fix requires target-version-only APIs that don't exist in the current Rails

**Do not fix `load_defaults`-triggered runtime deprecation warnings about *future* Rails versions during this hop.** This caveat covers post-bump runtime warnings emitted by Rails X+1 about behavior scheduled to change in X+2 — typically surfaced once `load_defaults X.Y` flips on in Workflow 11. Those belong to the *next* upgrade cycle and are addressed before the next version bump.

This is **not** a contradiction of fix-before-bump. The `kind: deprecation` patterns from Workflow 04's detection are warnings emitted by the *current* Rails version about APIs that go away at the *target* version — they stay in fix-before-bump and should be addressed in this hop.

Triaging tomorrow's deprecation warnings now expands the scope of the current hop and risks shipping a half-finished change.

## Step 4: Update Gemfile to target Rails version

## Step 5: Run test suite against both versions

## Step 6: Check CI config matches the upgraded Gemfile

Load `workflows/10-sync-ci-workflow.md`, fix any mismatches before proceeding

## Step 7: Deploy and verify
