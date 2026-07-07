---
name: ruby-upgrade
description: Plan and execute Ruby version upgrades one minor version at a time. Use when upgrading a Ruby application's Ruby version, planning a multi-hop Ruby upgrade, or auditing a Gemfile for Ruby-version blockers. Based on FastRuby.io methodology -- the same sequential, one-hop-at-a-time philosophy as the rails-upgrade skill, applied to Ruby itself.
---

# Ruby Upgrade Skill

Companion to the `rails-upgrade` plugin. Same FastRuby.io philosophy — **incremental, one version at a time, verify before moving on** — applied to Ruby itself instead of Rails.

## Why this is a separate skill from rails-upgrade

Ruby and Rails version floors move independently (Rails 7.2 needs Ruby >= 3.1, Rails 8.0/8.1 need >= 3.2), so a Ruby upgrade is frequently its own project, not a side effect of a Rails hop. Treat them as two independently-sequenced tracks that occasionally force each other's hand — a Rails hop's Ruby floor can require a Ruby upgrade first (see `rails-upgrade`'s `references/gem-compatibility.md` → "Dev-only gems with an independent Ruby floor" for the reverse case: a dev gem needing newer Ruby than the current Rails hop targets).

## CRITICAL: Sequential Upgrade Strategy — Skipping Versions Is Not Allowed

Exactly the same rule as `rails-upgrade`, applied to Ruby minors:

```
2.7 → 3.0 → 3.1 → 3.2 → 3.3 → 3.4
```

**You CANNOT skip versions in the skill's default methodology.** Each hop's own deprecation warnings are what prepare you for the *next* hop — jumping straight from 2.7 to 3.2 means the 2.7-era deprecation warnings for 3.0-era removals were never surfaced, and the 3.0/3.1-era warnings for 3.1/3.2-era removals never fired either. You only find out about all of it at once, at the hop with the least ability to isolate which change broke what.

**Exception, and only when the user explicitly says so:** a small application, a spike/exercise, or an app the user has already fully audited by other means, where they've explicitly asked to jump multiple minors in one hop. Multi-hop is the same story as `rails-upgrade`'s multi-hop pattern — explain the sequential default, confirm the user wants to skip it, then proceed with extra scrutiny (the boot smoke test and gem-floor audit below become load-bearing for *every* skipped hop's changes at once, not just one).

## High-Level Workflow

### Step 0: Verify Latest Patch Version (MANDATORY PRE-STEP)

Same reasoning as `rails-upgrade`'s Step 0: patch releases carry security fixes and bug fixes with no compatibility cost. Read `.ruby-version` / the Gemfile's `ruby "X.Y.Z"` line for the current version, then check the latest patch for that minor:

```bash
# List available patches for a minor (works with asdf's ruby plugin)
asdf list all ruby | grep "^3\.2\."
```

If not on the latest patch of the current minor, bump to it first, run the test suite, and treat that as its own small, low-risk deploy before starting the version hop.

### Step 1: Run Test Suite (MANDATORY FIRST STEP)

Same as `rails-upgrade` Step 1 — do not proceed on a red baseline. If there's no test suite, see that skill's `workflows/no-test-suite-smoke-workflow.md` for the smoke-test fallback; the same approach applies here.

### Step 2: Surface Deprecation Warnings on the CURRENT Ruby (MANDATORY)

**This is the Ruby-upgrade equivalent of checking Rails deprecation warnings before a Rails hop, and it is the step most likely to get skipped.** Ruby's own deprecation warnings for the *next* minor's removals are silent by default. Turn them on before touching the Gemfile:

```bash
# Run the test suite with deprecation warnings enabled
RUBYOPT="-W:deprecated" bundle exec rspec
# or, inside the app / an initializer, for a narrower scope:
# Warning[:deprecated] = true
```

Read `references/deprecation-warnings.md` for the full technique, what each hop's warnings tend to look like, and how to triage app-code warnings vs. warnings coming from inside a gem you don't control (report upstream / pin below the gem version that introduced the warning / ignore if the gem's own newer release already fixed it).

**Every warning surfaced here belongs in fix-before-bump**, same rubric as `rails-upgrade`'s `kind: deprecation` — it works today and breaks at the next hop.

### Step 3: Audit the Gemfile for Ruby-Version Blockers

Two distinct failure modes, both real, both found in production use of this skill's sibling (`rails-upgrade`):

1. **A gem's declared `required_ruby_version` already exceeds the target.** Cheap to check, bundler enforces it at resolve time — you'll find out immediately when you bump the Gemfile's `ruby` directive and run `bundle lock`.
2. **A gem's declared minimum is honest but its *actual* code isn't** — it calls a Ruby API that was removed, or uses syntax only valid on a newer Ruby than it claims. Static checks and `bundle install` both say "compatible"; only running the code proves it. See `references/known-gotchas.md` for two confirmed real examples (aws-sdk v2, an ancient `paperclip`) and `rails-upgrade`'s `references/gem-compatibility.md` → "Accidentally narrow legacy Gemfile pins" for the general pattern (that reference is about Rails hops, but the mechanism — declared constraint vs. actual runtime behavior — is identical for Ruby).

Grep every gem's actual usage of removed APIs is impractical; the boot smoke test (Step 5) is what actually catches class 2. Use this step for class 1 (cheap, static) and for reading each gem's CHANGELOG when `bundle lock` reports a conflict — the error names the exact gem and required version.

### Step 4: Bump the Gemfile's `ruby` Directive and Re-lock

```ruby
# Gemfile
ruby "3.0.6"  # was "2.7.2" -- one minor at a time, latest patch of the target minor
```

```bash
bundle lock
bundle install
```

If `bundle lock` reports a conflict, it names the blocking gem and its requirement directly — resolve per Step 3's two failure modes before moving on.

### Step 5: Boot Smoke Test (MANDATORY, mirrors rails-upgrade Step 4.6)

```bash
bundle exec rails runner "puts RUBY_VERSION"
```

This is the step that catches class 2 above — a gem whose `required_ruby_version` was honest on paper but whose code calls something Ruby actually removed. Confirmed real example this session: `aws-sdk-core` 2.3.23 declared no problematic floor but called `Proc.new` relying on implicit block capture from the caller — a Ruby feature fully removed in 3.0 — and raised `ArgumentError` on first boot. See `references/known-gotchas.md`.

If it fails, the trace names the offending gem's file directly (unlike the Rails-hop version of this same step, there's no resolver ambiguity to untangle — the stack trace points straight at the `require` chain). Check the gem's CHANGELOG for a release that drops the removed API, bump, and retry.

### Step 6: Fix Findings, Run Test Suite, Repeat Until Clean

Apply Step 2's and Step 5's findings, then run the full suite. Don't fix *next*-hop deprecation warnings that appear only now as a side effect of the bump you just made (e.g., a warning about a 3.1-era removal surfacing only once you're on 3.0) — same "don't triage tomorrow's deprecations today" rule as `rails-upgrade` Step 6. Note them for the next hop's own Step 2 sweep instead.

### Step 7: Land It

Update `.ruby-version`, the Dockerfile's base image (if any — check whether the OS base itself needs to move too, see `references/known-gotchas.md`'s Debian-base-image entry), CI's Ruby version, and any `ruby/setup-ruby`-style GitHub Actions config. Run the full suite one more time in the actual deploy-shaped environment (Docker/CI), not just locally, before calling the hop done.

## Available Resources

- `references/known-gotchas.md` — real, verified issues found upgrading Ruby, not generic advice. Add to this file as new ones surface.
- `references/deprecation-warnings.md` — how to turn on and read Ruby's own deprecation warnings before a hop, and how to triage what they turn up.

## Relationship to the Rails-Version Floor

Check `rails-upgrade`'s version guide table (`rails-upgrade/SKILL.md` → "Supported Upgrade Paths") for the Ruby floor of the Rails version currently in use and any upcoming Rails hop. If a planned Rails hop's Ruby floor is higher than the current Ruby, the Ruby hop(s) needed to reach it should be planned and landed **before** that Rails hop starts — don't let a Rails upgrade force an unplanned multi-hop Ruby jump to "catch up" in a single step.
