# Upgrade Cleanup Workflow

Run when the user is done with the upgrade campaign and wants to remove dual-boot scaffolding. Aligns the codebase to the new version baseline.

Based on FastRuby.io's [Finishing an Upgrade](https://www.fastruby.io/blog/finishing-an-upgrade.html) methodology. Rule of thumb: **never start the next hop with `NextRails.next?` branches still in the tree.** They accumulate, lose context, and make the next dual-boot impossible to reason about.

---

## When to Run This

Run when the user has explicitly decided to **end the dual-boot phase** in one of two directions:

- **Keep next** — upgrade is done (final hop or stopping point). Drop the `else` / current branches.
- **Keep current** — abandoning or pausing this hop. Drop the `if NextRails.next?` / next branches and `Gemfile.next*`.

The other side (whichever is being dropped) must no longer be needed (no rollback window, no parallel branch). Deployment to production is not required. If the user wants to clean up before deploying, that is their decision.

---

## Prerequisites

- Test suite passes on the side the user is keeping
- Working tree is clean (or on a dedicated cleanup branch)
- User confirms direction (next vs current) and, if keeping next, target version (e.g. "we just upgraded to 7.1")

---

## Phase 0: Pre-flight

Tearing down dual-boot scaffolding is destructive and direction-dependent. Settle direction first, then validate the side that is being kept.

### Step 1: Confirm direction

Before any destructive step, ask the user which side they want to keep. Do not infer it.

> *"Are we cleaning up because the upgrade succeeded and you want to keep the **next** version, or because you're abandoning/pausing this hop and want to keep the **current** version?"*

Record the answer as **keep next** or **keep current**. Every later step in this workflow branches on that label — Phase 1 onward spells out what each path does. If the user is unsure, stop and clarify. Don't guess from repo signals, both sides may look healthy.

### Step 2: Detect how the app runs

Inspect the repo to infer the run environment, then **ask the user** if anything is ambiguous. Do not guess.

| Signal | Implication |
|---|---|
| `Dockerfile` + `docker-compose.yml` (or `compose.yaml`) with a Rails service | App likely runs in Docker. Smoke checks should run via `docker compose run --rm <service> <cmd>`. |
| `bin/dev` or `Procfile.dev` | Local dev with foreman/overmind. Bundler runs locally. |
| `.tool-versions` / `.ruby-version` matches local Ruby, no Docker rails service | Local. Run commands directly. |
| Multiple options present (e.g. Dockerfile for prod, local for dev) | ASK the user which path to validate against. |

If unsure after inspection, ask: *"Should I run the pre-flight checks via Docker (`docker compose run --rm <svc> ...`) or locally (`bundle ...` directly)?"* Do not pick one silently.

### Step 3: Smoke-check the side being kept

Only validate the side that survives cleanup. The side being dropped is about to be deleted, so its health doesn't matter.

The commands below are shown for a local Ruby setup. If Step 2 settled on Docker, prefix each command with the appropriate container runner (e.g. `docker compose run --rm web ...`). If Step 2 was inconclusive and the user said "just try", run local first and fall back to Docker only if local can't resolve gems or boot the app.

**If keeping next:**

1. Next side bundles:
   ```sh
   BUNDLE_GEMFILE=Gemfile.next bundle check \
     || BUNDLE_GEMFILE=Gemfile.next bundle install
   ```
2. App boots on the next side (catches initializer / autoload / gem-API regressions that bundle alone misses). Skip only if a database is genuinely unreachable:
   ```sh
   BUNDLE_GEMFILE=Gemfile.next bin/rails runner "puts Rails.version"
   ```
   Output should match the upgraded-to version.

**If keeping current:**

1. Current side bundles:
   ```sh
   bundle check || bundle install
   ```
2. App boots on the current side:
   ```sh
   bin/rails runner "puts Rails.version"
   ```

### Stop conditions

- **Kept-side bundle fails:** the side the user wants to keep is broken. Cleanup is premature. Stop and tell the user; resolve the environment or boot regression before tearing down the parallel branch.
- **Kept-side rails runner fails but bundle succeeds:** boot regression on the version being kept. Tell the user; don't tear down the rollback path until it's fixed.

If the user explicitly says *"skip the pre-flight, I know it works"*, record their override and continue. Their call.

---

## Phase 1: Remove `NextRails.next?` / `NextRails.current?` Branches and Dual-Boot Scaffolding

This skill owns these steps. The `dual-boot` skill's `workflows/cleanup-workflow.md` is older optional reading; if it conflicts, follow the steps below.

Each step indicates the action for **keep next** vs **keep current**, per Phase 0 Step 1. The two paths are symmetric: whichever branch is kept becomes unconditional code.

1. Find all `NextRails.next?` and `NextRails.current?` references:
   ```sh
   grep -rE "NextRails\.(next|current)\?" . --include="*.rb" -l
   ```
   Both helpers ship with the `next_rails` gem and need to be removed regardless of direction.
2. Collapse the conditionals based on direction:
   - **Keep next:** keep the `if NextRails.next?` true branch, drop the `else`. Drop `if NextRails.current?` blocks entirely. Ternaries collapse to their `next?`-true value (e.g. `config.load_defaults NextRails.next? ? 8.0 : 7.0` → `config.load_defaults 8.0`).
   - **Keep current:** drop the `if NextRails.next?` block entirely (keep what was in the `else`). Keep the `if NextRails.current?` true branch, drop its `else`. Ternaries collapse to their `next?`-false value (e.g. `config.load_defaults NextRails.next? ? 8.0 : 7.0` → `config.load_defaults 7.0`).
3. Remove the `next?` method definition from the `Gemfile`. (Only `next?` is defined locally in the Gemfile, application code uses `NextRails.next?` / `NextRails.current?` from the gem.)
4. Collapse `if next?` / `else` conditionals in the `Gemfile` (remove the wrapper, keep one side's gems unconditional):
   - **Keep next:** keep the next-version gems (the `if next?` branch).
   - **Keep current:** keep the current-version gems (the `else` branch).
5. **Before removing `next_rails`, sweep for `deprecation_tracker` residue.** The gem ships a `DeprecationTracker` library that projects often wire into RSpec setup. If you remove the gem first, the test boot blows up with `LoadError: cannot load such file -- deprecation_tracker` and you discover the residue by failure. Cheaper to detect it up front and tear it down alongside the gem:
   ```sh
   grep -rnE "deprecation_tracker|DeprecationTracker|DEPRECATION_TRACKER" spec/ test/ 2>/dev/null
   ```
   Drop any `require "deprecation_tracker"`, `DeprecationTracker.track_rspec(...)` (often gated on `ENV["DEPRECATION_TRACKER"]`), and the associated `spec/support/deprecation_warning.shitlist.json` if it exists. Skip this sweep if the user opted to keep `next_rails`.
6. Remove the `next_rails` gem from the `Gemfile` (both directions). If the user wants to keep `next_rails` for the next hop, skip this step and tell them.
7. Reconcile lockfiles based on direction. Either path leaves both `Gemfile.next` and `Gemfile.next.lock` gone from the tree:
   - **Keep next:** replace `Gemfile.lock` with `Gemfile.next.lock` (`mv Gemfile.next.lock Gemfile.lock`, which also removes `Gemfile.next.lock` from its old path), then delete `Gemfile.next`. This preserves the exact gem versions tested during the upgrade. Do not run `bundle update` or delete the lockfile to re-resolve from scratch, that risks drift on versions you already validated.
   - **Keep current:** delete `Gemfile.next` and `Gemfile.next.lock`. Leave `Gemfile.lock` alone, it already pins the current version.
8. Run `bundle install` (NOT `bundle update`). `bundle install` is incremental: it removes references to gems no longer in the `Gemfile` (such as `next_rails` and any dual-boot-only gems) without re-resolving the rest. Rails and friends stay pinned.
9. Run the project's test suite (detect the runner from the `Gemfile`: `rspec-rails` means `bundle exec rspec`, otherwise `bundle exec rake test` or `bin/rails test`).
10. Update CI to drop the dual-boot job/matrix entry.

**Sanity check (keep next only):** after the lockfile swap, run `git diff Gemfile.lock` to confirm the new Rails version is actually pinned. If `Gemfile.next.lock` was never regenerated during the upgrade, it can be byte-identical to the old `Gemfile.lock`. In that case the lock is stale. Flag it to the user and run `bundle install` to resolve.

---

## Phase 2: Retire Stale Version-Conditional Code

Beyond `NextRails` branches, hunt for version-conditional code that no longer applies. Direction matters: when keeping next, the *current*-version scaffolding is dead; when keeping current, the *next*-version scaffolding is dead.

1. **Temporary monkey-patches and backports.** Search `config/initializers/` for files named like `rails_X_Y_backport.rb`, `monkey_patches/`, or comments tied to a specific version.
   - **Keep next:** delete patches that targeted the current (old) Rails version, they're now unconditional.
   - **Keep current:** delete patches that were added for the next version (no longer reachable). Confirm with user before deleting.
2. **Gem version pins.** Run `bundle outdated` and inspect pins.
   - **Keep next:** loosen pins held back for current-version compatibility, the constraint is gone.
   - **Keep current:** revert any pins that were bumped in anticipation of the next version, if they break the current version.
3. **Conditional `Gemfile` groups.** Drop groups keyed off the version being dropped (direction-symmetric: keep next → drop current-version groups; keep current → drop next-version groups).
4. **`docker-compose.yml` / `compose.yaml` sister services.** Dual-boot setups commonly add a parallel service (e.g. `web-next`, `worker-next`) that sets `BUNDLE_GEMFILE: Gemfile.next` and reuses the primary service via YAML anchors. These break once `Gemfile.next` is gone. Grep both compose files:
   ```sh
   grep -nE "BUNDLE_GEMFILE.*Gemfile\.next|-next:" docker-compose.yml compose.yaml 2>/dev/null
   ```
   - **Keep next:** drop the `*-next` service definitions; if the *primary* service was the one carrying `BUNDLE_GEMFILE: Gemfile.next`, unset that env var instead of deleting the service.
   - **Keep current:** drop the `*-next` service definitions outright.
5. **Documentation drift.** Sweep `README.md`, `CONTRIBUTING.md`, `bin/setup`, setup scripts, `.tool-versions`, and `Dockerfile` for stale Ruby/Rails references.
   - **Keep next:** update to the new baseline.
   - **Keep current:** revert any docs that were updated to the next version prematurely.

---

## Phase 3: CI and Ruby Pin Alignment

Tighten the build/test surface around the kept version:

1. **CI matrix.** Drop the dropped-side Rails version from any test matrix; you're not testing against it anymore. (Keep next → drop the old version. Keep current → drop the new version.)
2. **`Dockerfile` / `Gemfile` Ruby pin.**
   - **Keep next:** if the upgrade required a Ruby bump, confirm the Dockerfile, `.tool-versions`, `.ruby-version`, and CI all agree on the new Ruby. Distinguish drift introduced by this upgrade (fix in cleanup) from pre-existing drift that predates the upgrade (flag it for the user, but leave it out of scope, fixing unrelated infra in a cleanup PR muddies the diff).
   - **Keep current:** if a Ruby bump was staged for the next version, revert it back to the current Ruby. Same scope rule, only undo what this upgrade attempt introduced.

---

## Phase 4: Final Verification

Before declaring cleanup done:

- [ ] Test suite passes on the kept version (no dual-boot, single Gemfile)
- [ ] CI is green on the cleanup branch
- [ ] `grep -rE "NextRails\.(next|current)\?" . --include="*.rb"` returns nothing
- [ ] `Gemfile.next` and `Gemfile.next.lock` are gone
- [ ] No leftover `next_rails` gem in `Gemfile` (unless explicitly kept for the next hop)
- [ ] Documentation reflects the kept Ruby/Rails versions (keep next → new baseline; keep current → unchanged from before the upgrade attempt)

If the local environment cannot run the test suite (no DB, sandboxed shell), CI on the cleanup branch is the validating environment. Commit and push the cleanup PR, then track Phase 4 as in-progress until CI is green. Do not block the commit/PR step on a local test run that cannot happen.

---

## Phase 5: Commit and Open the PR

A dedicated cleanup PR is the recommended default. The diff reads as "remove scaffolding," nothing else, which makes review fast. If the user prefers to fold it into another branch, that is their call.

Suggested commit messages (pick by direction):

- **Keep next:**
  - `Remove dual-boot setup after Rails X.Y upgrade`
  - `Drop NextRails.next? / NextRails.current? branches`
- **Keep current:** (`X.Y` is the abandoned target version, `A.B` is the version we stay on)
  - `Abandon Rails X.Y upgrade attempt; stay on Rails A.B`
  - `Drop NextRails.next? / NextRails.current? branches`

Keep them as separate commits so reviewers can see each cleanup pass in isolation.

---

## What This Workflow Does NOT Do

- It does not roll back the upgrade. There is no rollback path here.
- It does not start the next version hop. After cleanup, the user invokes the rails-upgrade skill again for the next version.
- It does not triage deprecation warnings. Those belong to the rails-upgrade skill's next-hop workflow.

---

## Notes for Claude

- **Direction first, always.** Never start collapsing branches before Phase 0 Step 1 has settled next vs current. Both sides may look healthy in the repo; only the user knows which one is the goal.
- Treat every destructive step (`rm`, lockfile replacement, gem removal, CI edits) as needing user confirmation. The workflow is reversible only via git, so move slowly.
- If `Gemfile.next.lock` does not exist, dual-boot was never set up or is already cleaned. Skip Phase 1 and tell the user.
- If `NextRails.next?` or `NextRails.current?` references appear inside vendored gems or `vendor/bundle/`, ignore them. Only application code matters.
- When keeping next, detect the target version from the `Gemfile`'s `if NextRails.next?` block or `Gemfile.next.lock`, not `Gemfile.lock`, which still holds the current version during dual-boot.
- If the user wants to keep `next_rails` installed for the next hop, skip "Remove `next_rails` gem" in Phase 1 but still delete `Gemfile.next` (and `Gemfile.next.lock` on the keep-current path) and the `if next?` conditionals.
