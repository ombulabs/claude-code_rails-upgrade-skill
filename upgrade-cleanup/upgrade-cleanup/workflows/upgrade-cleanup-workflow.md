# Upgrade Cleanup Workflow

Run when the user is done with the upgrade campaign and wants to remove dual-boot scaffolding. Aligns the codebase to the new version baseline.

Based on FastRuby.io's [Finishing an Upgrade](https://www.fastruby.io/blog/finishing-an-upgrade.html) methodology.

---

## When to Run This

Run when both are true:

- The user has **explicitly decided to stop or pause** the upgrade campaign.
- The previous Rails version is no longer needed (no rollback window, no parallel branch).

Deployment to production is not required. If the user wants to clean up before deploying, that is their decision.

---

## Prerequisites

- Test suite passes on the upgraded version
- Working tree is clean (or on a dedicated cleanup branch)
- User confirms target version (e.g. "we just upgraded to 7.1")

---

## Phase 1: Remove `NextRails.next?` / `NextRails.current?` Branches and Dual-Boot Scaffolding

This skill owns these steps. The `dual-boot` skill's `workflows/cleanup-workflow.md` is older background reference.

1. Find all `NextRails.next?` and `NextRails.current?` references:
   ```sh
   grep -rE "NextRails\.(next|current)\?" . --include="*.rb" -l
   ```
   Both helpers ship with the `next_rails` gem and need to be removed.
2. Keep only the `if NextRails.next?` (true) branch and drop the `else`. Ternaries collapse to the true value too. For example, `config.load_defaults NextRails.next? ? 8.0 : 7.0` becomes `config.load_defaults 8.0`. For `NextRails.current?`, drop the `if current?` block entirely (it was the old-version branch).
3. Remove the `next?` / `current?` method definitions from the `Gemfile`.
4. Remove all `if next?` / `if current?` / `else` Gemfile conditionals (keep new-version gems).
5. Remove the `next_rails` gem from the `Gemfile`.
6. Replace `Gemfile.lock` with `Gemfile.next.lock` (`mv Gemfile.next.lock Gemfile.lock`), then delete `Gemfile.next`. This is the standard step. It preserves the exact gem versions tested during the upgrade. Do not run `bundle install` from scratch, since resolution drift can change versions you already validated.
7. Run the test suite (project's detected runner; see dual-boot SKILL.md Key Principle #4).
8. Update CI to drop the dual-boot job/matrix entry.

**Sanity check after lockfile swap:** `git diff Gemfile.lock` to confirm the new Rails version is actually pinned. If `Gemfile.next.lock` was never regenerated during the upgrade, it can be byte-identical to the old `Gemfile.lock`. In that case the lock is stale. Flag it to the user and run `bundle install` to resolve.

---

## Phase 2: Retire Old-Version Code

Beyond `NextRails` branches, hunt for other version-conditional code that has gone stale:

1. **Temporary monkey-patches and backports.** Search for files in `config/initializers/` named like `rails_X_Y_backport.rb`, `monkey_patches/`, or comments referencing the previous Rails version. Confirm with user before deleting.
2. **Gem version pins tied to the old Rails.** Run `bundle outdated` and check for gems that were held back for compatibility. Loosen pins now that the constraint is gone.
3. **Conditional `Gemfile` groups.** Anything keyed off the old Ruby/Rails version.
4. **Dead config/initializers.** `new_framework_defaults_X_Y.rb` from a previous hop is fine to leave until Phase 4; older ones should already be gone.

---

## Phase 3: Version-Specific Housekeeping

After upgrading to the target Rails version, certain artifacts gain a version suffix:

1. **Migrations.** New migrations should subclass `ActiveRecord::Migration[X.Y]` where `X.Y` is the version that was upgraded *to*. Existing migrations keep their original suffix; do not rewrite history.
2. **`db/schema.rb`.** Rails regenerates the schema header on the next `db:migrate` or `db:schema:dump`. Run it once and commit so the suffix matches the new version.
3. **CI matrix.** Drop the old Rails version from any test matrix; you're not testing against it anymore.
4. **`Dockerfile` / `Gemfile` Ruby pin.** If the upgrade required a Ruby bump, confirm the Dockerfile, `.tool-versions`, `.ruby-version`, and CI all agree.

---

## Phase 4: Align `load_defaults`

DELEGATE to the `rails-load-defaults` skill. That skill walks through each new framework default one at a time, runs tests between changes, and consolidates into `config/application.rb` when complete. Do NOT bump `load_defaults` to the new version in one shot, since the per-config tiered approach exists because some defaults silently change behavior.

If the user says "skip load_defaults for now" or "we'll do it later," record it as a follow-up and continue. The cleanup is still useful without it.

---

## Phase 5: Address Deprecation Warnings

The new Rails version emits deprecation warnings for things that will break on the *next* hop. Fix them now while the context is fresh.

1. Confirm deprecations are visible (see `dual-boot` skill's `references/deprecation-tracking.md` for the config knobs).
2. Run the test suite and capture deprecation output.
3. Fix call sites directly **without** wrapping them in `NextRails.next?`. The new API works on the current version, so a plain migration is correct. (See `dual-boot/references/code-patterns.md` "When NOT to Branch: Deprecations".)
4. Re-run tests. Repeat until the deprecation noise is gone or down to a known list the user accepts.

This is the single highest-leverage step before the next upgrade. A clean deprecation log on version X is the prerequisite for a sane dual-boot to version X+1.

---

## Phase 6: Final Verification

Before declaring cleanup done:

- [ ] Test suite passes on the upgraded version (no dual-boot, single Gemfile)
- [ ] CI is green on the cleanup branch
- [ ] `grep -rE "NextRails\.(next|current)\?" . --include="*.rb"` returns nothing
- [ ] `Gemfile.next` and `Gemfile.next.lock` are gone
- [ ] No leftover `next_rails` gem in `Gemfile`
- [ ] Deprecation warnings have been triaged

---

## Phase 7: Commit and Open the PR

A dedicated cleanup PR is the recommended default. The diff reads as "remove scaffolding," nothing else, which makes review fast. If the user prefers to fold it into another branch, that is their call.

Suggested commit messages:

- `Remove dual-boot setup after Rails X.Y upgrade`
- `Drop NextRails.next? / NextRails.current? branches`
- `Bump load_defaults to X.Y`
- `Fix Rails X.Y deprecation warnings`

Keep them as separate commits so reviewers can see each cleanup pass in isolation.

---

## What This Workflow Does NOT Do

- It does not roll back the upgrade. There is no rollback path here.
- It does not start the next version hop. After cleanup, the user invokes the upgrade flow again for the next version.
- It does not silence deprecations. If the user wants to defer them, that is a project decision, not a cleanup decision.

---

## Notes for Claude

- If `Gemfile.next.lock` does not exist, dual-boot was never set up or is already cleaned. Skip Phase 1 and tell the user.
- If `NextRails.next?` or `NextRails.current?` references appear inside vendored gems or `vendor/bundle/`, ignore them. Only application code matters.
- Detect the target version from the `Gemfile`'s `if NextRails.next?` block or `Gemfile.next.lock`, not `Gemfile.lock`, which still holds the old version during dual-boot.
