---
name: upgrade-cleanup
description: Clean up after a Rails upgrade. Drop NextRails.next? and NextRails.current? branches, retire dual-boot scaffolding (Gemfile.next, Gemfile.next.lock, conditional Gemfile groups), and triage deprecations on the upgraded version. Trigger when the user says they are done with the upgrade, want to clean up dual-boot, want to drop NextRails branches, or want to finish the upgrade. Based on FastRuby.io's "Finishing an Upgrade" methodology.
---

# Upgrade Cleanup Skill

Companion to the `rails-upgrade` plugin. Runs the cleanup pass that removes dual-boot scaffolding and aligns the codebase to the new version baseline.

When activated, follow the workflow in `workflows/upgrade-cleanup-workflow.md` end-to-end. To detect the version that was upgraded to, read the `Gemfile` (look for the `if NextRails.next?` / `else` block; the `next?` branch holds the upgraded version) or `Gemfile.next.lock`. Do NOT rely on `Gemfile.lock` alone, since during dual-boot it still pins the old version.

## When to Run

Run when both are true:

- The user has explicitly decided to **stop the upgrade campaign** (final hop, or pausing for now).
- The previous Rails version is no longer needed (no rollback window, no parallel branch).

Deployment to production is not a hard prerequisite. If the user wants to remove dual-boot before deploying, that is their call.

## Ownership and Delegations

This skill **owns** the cleanup. Phase 1 below is the canonical step list. The `dual-boot` skill's `workflows/cleanup-workflow.md` is older background reference; if it drifts from this workflow, this workflow wins.

- **Dual-boot scaffolding removal**: performed here in Phase 1.
- **`load_defaults` alignment**: DELEGATE to the `rails-load-defaults` skill, which walks each new framework default one at a time with tests in between.

## Critical Rules

- **Do NOT silence deprecation warnings.** Phase 5 fixes them, not hides them. They become breaking changes on the next hop.
- **Do NOT leave `NextRails.next?` or `NextRails.current?` branches in the tree.** That is the failure mode this skill exists to prevent.

## Workflow

See `workflows/upgrade-cleanup-workflow.md` for the full process:

0. Pre-flight: detect run environment (Docker vs local), smoke-check that both sides bundle and the app boots on each. Stop if the next side has rotted.
1. Remove `NextRails.next?` / `NextRails.current?` branches and dual-boot scaffolding
2. Retire old-version code (monkey-patches, gem pins, conditional Gemfile groups)
3. Version-specific housekeeping (migration class suffix, schema dump, CI matrix, Ruby pin)
4. Align `load_defaults` (delegated to `rails-load-defaults`)
5. Address deprecation warnings emitted by the new Rails version
6. Final verification (test suite, CI green, no `NextRails.next?` / `NextRails.current?` left)
7. Commit and open the cleanup PR

## Reference

- [Finishing an Upgrade, FastRuby.io](https://www.fastruby.io/blog/finishing-an-upgrade.html)
- `workflows/upgrade-cleanup-workflow.md`, full workflow
- The `dual-boot` plugin's `workflows/cleanup-workflow.md`, background only
- The `rails-load-defaults` plugin, Phase 4
