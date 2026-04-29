---
name: upgrade-cleanup
description: Clean up after a Rails upgrade. Drop NextRails.next? and NextRails.current? branches and retire dual-boot scaffolding (Gemfile.next, Gemfile.next.lock, conditional Gemfile groups). Trigger when the user says they are done with the upgrade, want to clean up dual-boot, want to drop NextRails branches, or want to finish the upgrade. Based on FastRuby.io's "Finishing an Upgrade" methodology.
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

This skill **owns** the cleanup. Phase 1 below is the step list to follow. The `dual-boot` skill's `workflows/cleanup-workflow.md` is older optional reading; if it drifts from this workflow, this workflow wins.

- **Dual-boot scaffolding removal**: performed here in Phase 1.
- **`load_defaults` alignment**: out of scope. The `rails-upgrade` skill handles this via its `rails-load-defaults` step before cleanup runs.

## Critical Rules

- **Do NOT leave `NextRails.next?` or `NextRails.current?` branches in the tree.** That is the failure mode this skill exists to prevent.

## Workflow

See `workflows/upgrade-cleanup-workflow.md` for the full process: a pre-flight check, dual-boot scaffolding removal, old-version code retirement, version housekeeping, final verification, and the cleanup PR.

## Reference

- [Finishing an Upgrade, FastRuby.io](https://www.fastruby.io/blog/finishing-an-upgrade.html)
- `workflows/upgrade-cleanup-workflow.md`, full workflow
- The `dual-boot` plugin's `workflows/cleanup-workflow.md`, optional reading for context. This skill's Phase 1 is the step list to follow, do not use dual-boot's version when it conflicts.
