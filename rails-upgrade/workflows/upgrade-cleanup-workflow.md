# Upgrade Cleanup Workflow

Run this **after** a Rails version upgrade is in production and before starting the next version hop. It removes the scaffolding that made the dual-boot transition safe (which now adds noise) and aligns the codebase to the new version.

Based on FastRuby.io's [Finishing an Upgrade](https://www.fastruby.io/blog/finishing-an-upgrade.html) methodology. Henrique's rule of thumb: **never start the next hop with `NextRails.next?` branches still in the tree** — they accumulate, lose context, and make the next dual-boot impossible to reason about.

---

## When to Run This

Run when ALL of these are true:

- Rails version upgrade is **deployed to production**
- The previous Rails version is no longer needed (no rollback window, no parallel branch)
- The user has decided either to **stop here** or to **start the next hop**

If any are false, stop and ask the user before continuing.

---

## Prerequisites

- Test suite passes on the upgraded version
- Working tree is clean (or on a dedicated cleanup branch)
- User confirms target version (e.g. "we just upgraded to 7.1")

---

## Phase 1: Remove `NextRails.next?` Branches and Dual-Boot Scaffolding

**DELEGATE** to the `dual-boot` skill — load `workflows/cleanup-workflow.md` from that skill and follow it.

That workflow covers:

1. Find all `NextRails.next?` references (`grep -r "NextRails.next?" . --include="*.rb" -l`)
2. Keep only the `if NextRails.next?` (true) branch, drop the `else`
3. Remove the `next?` method definition from the Gemfile
4. Remove all `if next?` / `else` Gemfile conditionals (keep new-version gems)
5. Remove the `next_rails` gem if no longer needed
6. Replace `Gemfile.lock` with `Gemfile.next.lock`, delete `Gemfile.next`
7. Run the test suite (project's detected runner — see dual-boot SKILL.md Key Principle #4)
8. Update CI to drop the dual-boot job/matrix entry

**Critical:** confirm with the user before running `rm Gemfile.next Gemfile.lock` or any `git rm`. Replacing `Gemfile.lock` with `Gemfile.next.lock` preserves the exact gem versions tested during the upgrade — running `bundle install` from scratch could resolve to different versions.

---

## Phase 2: Retire Old-Version Code

Beyond `NextRails.next?` branches, hunt for other version-conditional code that has gone stale:

1. **Temporary monkey-patches and backports** — search for files in `config/initializers/` named like `rails_X_Y_backport.rb`, `monkey_patches/`, or comments referencing the previous Rails version. Confirm with user before deleting.
2. **Gem version pins tied to the old Rails** — `bundle outdated` and check for gems that were held back for compatibility. Loosen pins now that the constraint is gone.
3. **Conditional `Gemfile` groups** — anything keyed off the old Ruby/Rails version.
4. **Dead config/initializers** — `new_framework_defaults_X_Y.rb` from a previous hop is fine to leave until Phase 4; older ones should already be gone.
5. **Documentation drift** — `README.md`, `CONTRIBUTING.md`, setup scripts, `.tool-versions`, `Dockerfile`, `bin/setup` — update Ruby/Rails version references.

---

## Phase 3: Version-Specific Housekeeping

After upgrading to the target Rails version, certain artifacts gain a version suffix:

1. **Migrations** — new migrations should subclass `ActiveRecord::Migration[X.Y]` where `X.Y` is the version that was upgraded *to*. Existing migrations keep their original suffix; do not rewrite history.
2. **`db/schema.rb`** — Rails regenerates the schema header on the next `db:migrate` or `db:schema:dump`. Run it once and commit so the suffix matches the new version.
3. **CI matrix** — drop the old Rails version from any test matrix; you're not testing against it anymore.
4. **`Dockerfile` / `Gemfile` Ruby pin** — if the upgrade required a Ruby bump, confirm the Dockerfile, `.tool-versions`, `.ruby-version`, and CI all agree.

---

## Phase 4: Align `load_defaults`

**DELEGATE** to the `rails-load-defaults` skill.

That skill walks through each new framework default one at a time, runs tests between changes, and consolidates into `config/application.rb` when complete. Do NOT bump `load_defaults` to the new version in one shot — the per-config tiered approach exists because some defaults silently change behavior.

If the user says "skip load_defaults for now" or "we'll do it later," record that as a follow-up and continue. The cleanup is still useful without it.

---

## Phase 5: Address Deprecation Warnings

The new Rails version emits deprecation warnings for things that will break on the *next* hop. Fix them now while the context is fresh.

1. Confirm deprecations are visible — see `dual-boot` skill's `references/deprecation-tracking.md` for the config knobs.
2. Run the test suite and capture deprecation output.
3. Fix call sites directly **without** wrapping them in `NextRails.next?` — the new API works on the current version, so a plain migration is correct. (See `dual-boot/references/code-patterns.md` "When NOT to Branch: Deprecations".)
4. Re-run tests. Repeat until the deprecation noise is gone or down to a known list the user accepts.

This is the single highest-leverage step before the next upgrade. A clean deprecation log on version X is the prerequisite for a sane dual-boot to version X+1.

---

## Phase 6: Final Verification

Before declaring cleanup done:

- [ ] Test suite passes on the upgraded version (no dual-boot, single Gemfile)
- [ ] CI is green on the cleanup branch
- [ ] `grep -r "NextRails.next?" . --include="*.rb"` returns nothing
- [ ] `Gemfile.next` and `Gemfile.next.lock` are gone
- [ ] No leftover `next_rails` gem in `Gemfile` (unless explicitly kept for the next hop)
- [ ] Documentation reflects the new Ruby/Rails versions
- [ ] Deprecation warnings have been triaged

---

## Phase 7: Commit and Open the PR

Open a dedicated cleanup PR — don't fold it into a feature branch. The diff should read as "remove scaffolding," nothing else.

Suggested commit messages:

- `Remove dual-boot setup after Rails X.Y upgrade`
- `Drop NextRails.next? branches`
- `Bump load_defaults to X.Y`
- `Fix Rails X.Y deprecation warnings`

Keep them as separate commits so reviewers can see each cleanup pass in isolation.

---

## What This Workflow Does NOT Do

- It does not roll back the upgrade — there is no rollback path here.
- It does not start the next version hop. After cleanup, the user invokes the upgrade flow again (or `/rails-upgrade`) for the next version.
- It does not silence deprecations. If the user wants to defer them, that is a project decision, not a cleanup decision.

---

## Notes for Claude

- Treat every destructive step (`rm`, lockfile replacement, gem removal, CI edits) as needing user confirmation. The workflow is reversible only via git, so move slowly.
- If `Gemfile.next.lock` does not exist, dual-boot was never set up or is already cleaned. Skip Phase 1 and tell the user.
- If `NextRails.next?` references appear inside vendored gems or `vendor/bundle/`, ignore them — only application code matters.
- If the user wants to keep `next_rails` installed for the next hop, skip "Remove `next_rails` gem" in Phase 1 but still drop the `Gemfile.next` symlink and the `if next?` conditionals.
