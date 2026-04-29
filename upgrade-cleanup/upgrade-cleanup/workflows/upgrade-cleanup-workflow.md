# Upgrade Cleanup Workflow

Run when the user is done with the upgrade campaign and wants to remove dual-boot scaffolding. Aligns the codebase to the new version baseline.

Based on FastRuby.io's [Finishing an Upgrade](https://www.fastruby.io/blog/finishing-an-upgrade.html) methodology. Rule of thumb: **never start the next hop with `NextRails.next?` branches still in the tree.** They accumulate, lose context, and make the next dual-boot impossible to reason about.

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

## Phase 0: Pre-flight

Tearing down `Gemfile.next` is destructive. Before starting, confirm the dual-boot setup is *currently* functional. If the next side has rotted (bundle fails, app won't boot), the upgrade campaign isn't actually done and cleanup is premature. Stop and tell the user.

### Step 1: Detect how the app runs

Inspect the repo to infer the run environment, then **ask the user** if anything is ambiguous. Do not guess.

| Signal | Implication |
|---|---|
| `Dockerfile` + `docker-compose.yml` (or `compose.yaml`) with a Rails service | App likely runs in Docker. Smoke checks should run via `docker compose run --rm <service> <cmd>`. |
| `bin/dev` or `Procfile.dev` | Local dev with foreman/overmind. Bundler runs locally. |
| `.tool-versions` / `.ruby-version` matches local Ruby, no Docker rails service | Local. Run commands directly. |
| Multiple options present (e.g. Dockerfile for prod, local for dev) | ASK the user which path to validate against. |

If unsure after inspection, ask: *"Should I run the pre-flight checks via Docker (`docker compose run --rm <svc> ...`) or locally (`bundle ...` directly)?"* Do not pick one silently.

### Step 2: Smoke-check both sides

The commands below are shown for a local Ruby setup. If the project runs in Docker, prefix each command with the appropriate container runner (e.g. `docker compose run --rm web ...`). Try local first; fall back to Docker if local can't resolve the gems or boot the app.

1. **Current side bundles:**
   ```sh
   bundle check || bundle install
   ```
2. **Next side bundles:**
   ```sh
   BUNDLE_GEMFILE=Gemfile.next bundle check \
     || BUNDLE_GEMFILE=Gemfile.next bundle install
   ```
3. **App boots on both sides** (catches initializer / autoload / gem-API regressions that bundle alone misses). Skip only if a database is genuinely unreachable from the run environment:
   ```sh
   bin/rails runner "puts Rails.version"
   BUNDLE_GEMFILE=Gemfile.next bin/rails runner "puts Rails.version"
   ```
   The next-side output should match the upgraded-to version.

### Stop conditions

- **Next-side bundle fails:** `Gemfile.next` is stale or never validated. Cleanup is premature. Tell the user the upgrade campaign needs to finish first.
- **Next-side rails runner fails but bundle succeeds:** boot regression on the new version. Tell the user; don't tear down the rollback path until it's fixed.
- **Current-side bundle fails:** environment problem unrelated to the upgrade. Resolve before continuing — you don't want a half-broken environment during cleanup.

If the user explicitly says *"skip the pre-flight, I know it works"*, record their override and continue. Their call.

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
6. Replace `Gemfile.lock` with `Gemfile.next.lock` (`mv Gemfile.next.lock Gemfile.lock`), then delete `Gemfile.next`. This is the standard step. It preserves the exact gem versions tested during the upgrade. Do not run `bundle update` or delete the lockfile to re-resolve from scratch — that risks drift on versions you already validated.
7. Run `bundle install` (NOT `bundle update`). The swapped lockfile still pins `next_rails` and any other dual-boot-only gems because `Gemfile.next` listed them. `bundle install` is incremental: it removes references to gems no longer in the `Gemfile` without re-resolving the rest. `rails` and friends stay pinned.
8. Run the test suite (project's detected runner; see dual-boot SKILL.md Key Principle #4).
9. Update CI to drop the dual-boot job/matrix entry.

**Sanity check after lockfile swap:** `git diff Gemfile.lock` to confirm the new Rails version is actually pinned. If `Gemfile.next.lock` was never regenerated during the upgrade, it can be byte-identical to the old `Gemfile.lock`. In that case the lock is stale. Flag it to the user and run `bundle install` to resolve.

---

## Phase 2: Retire Old-Version Code

Beyond `NextRails` branches, hunt for other version-conditional code that has gone stale:

1. **Temporary monkey-patches and backports.** Search for files in `config/initializers/` named like `rails_X_Y_backport.rb`, `monkey_patches/`, or comments referencing the previous Rails version. Confirm with user before deleting.
2. **Gem version pins tied to the old Rails.** Run `bundle outdated` and check for gems that were held back for compatibility. Loosen pins now that the constraint is gone.
3. **Conditional `Gemfile` groups.** Anything keyed off the old Ruby/Rails version.
4. **Dead config/initializers.** `new_framework_defaults_X_Y.rb` from a previous hop is fine to leave until Phase 4; older ones should already be gone.
5. **Documentation drift.** Sweep `README.md`, `CONTRIBUTING.md`, `bin/setup`, setup scripts, `.tool-versions`, and `Dockerfile` for stale Ruby/Rails version references. Update to the new baseline.

---

## Phase 3: Version-Specific Housekeeping

After upgrading to the target Rails version, certain artifacts gain a version suffix:

1. **Migrations.** New migrations should subclass `ActiveRecord::Migration[X.Y]` where `X.Y` is the version that was upgraded *to*. Existing migrations keep their original suffix; do not rewrite history.
2. **`db/schema.rb`.** Rails regenerates the schema header on the next `db:migrate` or `db:schema:dump`. Run it once and commit so the suffix matches the new version. If the local environment cannot reach a database (sandboxed shell, no DB service), defer the schema dump to a follow-up commit and flag it for the user. Do NOT hand-edit `ActiveRecord::Schema[X.Y]` in place — Rails regenerates the whole file, so a manual edit risks masking a real diff if any pending migration would alter the dump.
3. **CI matrix.** Drop the old Rails version from any test matrix; you're not testing against it anymore.
4. **`Dockerfile` / `Gemfile` Ruby pin.** If the upgrade required a Ruby bump, confirm the Dockerfile, `.tool-versions`, `.ruby-version`, and CI all agree. Distinguish drift introduced by this upgrade (fix in cleanup) from pre-existing drift that predates the upgrade (flag it for the user, but leave it out of scope — fixing unrelated infra in a cleanup PR muddies the diff).

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
- [ ] No leftover `next_rails` gem in `Gemfile` (unless explicitly kept for the next hop)
- [ ] Documentation reflects the new Ruby/Rails versions
- [ ] Deprecation warnings have been triaged

If the local environment cannot run the test suite (no DB, sandboxed shell), CI on the cleanup branch is the validating environment. Commit and push the cleanup PR, then track Phase 6 as in-progress until CI is green. Do not block the commit/PR step on a local test run that cannot happen.

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

- Treat every destructive step (`rm`, lockfile replacement, gem removal, CI edits) as needing user confirmation. The workflow is reversible only via git, so move slowly.
- If `Gemfile.next.lock` does not exist, dual-boot was never set up or is already cleaned. Skip Phase 1 and tell the user.
- If `NextRails.next?` or `NextRails.current?` references appear inside vendored gems or `vendor/bundle/`, ignore them. Only application code matters.
- Detect the target version from the `Gemfile`'s `if NextRails.next?` block or `Gemfile.next.lock`, not `Gemfile.lock`, which still holds the old version during dual-boot.
- If the user wants to keep `next_rails` installed for the next hop, skip "Remove `next_rails` gem" in Phase 1 but still drop the `Gemfile.next` symlink and the `if next?` conditionals.
