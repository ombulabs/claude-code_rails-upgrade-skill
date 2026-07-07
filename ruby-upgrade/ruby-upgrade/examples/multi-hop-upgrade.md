# Example: Multi-Hop Upgrade (Explicit Exception)

A small internal tool, Ruby 2.7.2, being used as a live upgrade-practice exercise. The user explicitly asks to jump straight to 3.2 in one hop rather than going 2.7 → 3.0 → 3.1 → 3.2, because the app is low-stakes and this is intentionally an exercise.

## Confirming the Exception

Before proceeding: state the sequential default (`SKILL.md`'s "CRITICAL: Sequential Upgrade Strategy") and what skipping trades away — the 2.7-era warnings for 3.0 removals and the 3.0/3.1-era warnings for 3.1/3.2 removals never get a chance to fire independently, so any breakage from any of the three skipped hops surfaces at once. User confirms: proceed anyway.

## Step 0-1: Patch Check and Baseline

`.ruby-version` is `2.7.2`; latest patch of 2.7 is `2.7.8`. Given this is an explicit multi-hop exercise ending on 3.2 regardless, and 2.7 is already EOL with no further patches coming, the user opts to skip the intermediate 2.7.8 patch bump and go straight to the minor jump — noted as a deliberate, informed choice, not an oversight. Test suite: 11 examples, 0 failures. Green, proceed.

## Step 2: Deprecation Sweep (Run Once, Against 2.7, Before Any Bump)

```bash
RUBYOPT="-W:deprecated" bundle exec rspec 2>&1 >/dev/null | grep "warning:" | sort -u
```

Clean — zero warnings. This is real signal (the app's own code doesn't call anything 2.7 already knows to warn about), but it is explicitly *not* a guarantee of 3.0/3.1/3.2-readiness — 2.7's warnings only cover what's scheduled for removal in 3.0, not the later two minors' own removals, which have no equivalent warning mechanism to run yet on a 2.7 interpreter.

## Step 3: Gemfile Audit

Two blockers found via `bundle lock` dry-run:

1. `gem "aws-sdk", "~> 2.3.0"` — no declared floor conflict, but flagged from `references/known-gotchas.md` as a known undeclared-floor risk (`Proc.new`, removed in 3.0). Planned swap to `aws-sdk-s3` ahead of the bump rather than waiting to discover it at the boot smoke test.
2. `gem "paperclip", "~> 5.0"` — same known-gotchas flag (`URI.escape`, removed in 3.0). Planned swap to `kt-paperclip`.

Both swaps applied before Step 4's version bump, verified with the existing test suite still on Ruby 2.7 first (isolating the gem-swap risk from the version-bump risk).

## Step 4: Version Bump

```ruby
ruby "3.2.11"  # was "2.7.2" -- explicit user-approved multi-hop exception, skipping 3.0 and 3.1
```

```bash
bundle lock
bundle install
```

Two further conflicts surface here (not caught by Step 3's dry-run, because they only manifest once the full lock resolves against 3.2 rather than a hypothetical intermediate version): a dev-only `spring` pin needed bumping to a 4.x release that supports 3.2, and `reek`'s locked version capped `parser`, which in turn blocked a needed `rubocop` bump — resolved by bumping `reek` itself to a release with a newer `parser` constraint.

## Step 5: Boot Smoke Test — Compound Failures, Fixed Sequentially

```bash
bundle exec rails runner "puts RUBY_VERSION"
```

First failure: `ArgumentError` from `aws-sdk-core` — wait, already swapped in Step 3. Re-checked: an unrelated require path in a different gem still pulled in the old `aws-sdk` transitively via a stale `Gemfile.lock` entry. Re-ran `bundle lock` to fully drop it, retried — clean on `aws-sdk`.

Second failure: `Spring.dangerously_allow_disabling_reloading` needed in `config/spring.rb` (the `known-gotchas.md` spring entry) — the app's test environment runs with reloading disabled, and spring 4.x now hard-requires acknowledging that. Added the config, retried — boot smoke test passes.

This two-step sequence is the compound-failure pattern multi-hop upgrades produce even in a small app: fixing the first visible error revealed a second, unrelated one hiding behind it.

## Step 6: Fix/Test Loop

```bash
bundle exec rspec
# 11 examples, 0 failures
```

## Step 7: Landing

`.ruby-version`, Gemfile, Dockerfile base image, and CI config all updated to `3.2.11`. Dockerfile base image check revealed the underlying OS also moved (`ruby:2.7.2`'s Debian 10 "buster", EOL → `ruby:3.2.11`'s Debian 13 "trixie") — this removed the need for several OS-version-specific Dockerfile workarounds (an EOL-apt-repo patch, a manual Node.js tarball install, `force_ruby_platform`) that had been carried for the old base. Verified via a full Docker Compose run and a real GitHub Actions CI run, not just locally.

## Retrospective Note for `known-gotchas.md`

This exercise is itself the source of several of `known-gotchas.md`'s current entries (`aws-sdk` v2, `paperclip`, spring, the Docker base image move, `bundle lock` platform pollution, and `OpenStruct` losing implicit availability) — a multi-hop jump surfaced all of them in one project instead of spreading them across three separate hops' worth of history, which is exactly the compound-risk trade-off this exception accepts.
