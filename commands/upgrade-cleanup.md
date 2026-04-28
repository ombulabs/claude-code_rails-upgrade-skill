---
description: Finish a Rails upgrade — remove dual-boot, clean NextRails.next? branches, retire old version code, and prep the codebase for the next hop. Based on FastRuby.io's "Finishing an Upgrade" methodology.
argument-hint: "[upgraded-version]"
---

The user just shipped a Rails upgrade and is ready to "finish" it before starting the next version hop. Run the post-upgrade cleanup workflow from the rails-upgrade skill.

1. Load `rails-upgrade/workflows/upgrade-cleanup-workflow.md` and follow it end-to-end.
2. If the user passed an upgraded-version argument (e.g. `/upgrade-cleanup 7.1`), use it as the version that was just shipped. Otherwise, read `Gemfile.lock` to detect the current Rails version and confirm with the user that the upgrade to that version is in production before proceeding.
3. The workflow delegates two sub-tasks:
   - **Dual-boot removal** → DELEGATE to the `dual-boot` skill (`workflows/cleanup-workflow.md` there).
   - **`load_defaults` alignment** → DELEGATE to the `rails-load-defaults` skill.
4. Do NOT run any destructive command (`rm`, `git rm`, gem removal, lockfile replacement, CI edits) without confirming with the user first. The workflow flags every destructive step.

Reference: [Finishing an Upgrade — FastRuby.io](https://www.fastruby.io/blog/finishing-an-upgrade.html).
