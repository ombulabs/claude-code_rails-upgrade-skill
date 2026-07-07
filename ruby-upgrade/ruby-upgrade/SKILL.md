---
name: ruby-upgrade
description: Plan and execute Ruby version upgrades one minor version at a time. Use when upgrading a Ruby application's Ruby version, planning a multi-hop Ruby upgrade, or auditing a Gemfile for Ruby-version blockers. Based on FastRuby.io methodology -- incremental, one hop at a time, verify before moving on.
---

# Ruby Upgrade Skill

## Skill Identity

- **Name:** Ruby Upgrade Assistant
- **Purpose:** Plan and execute Ruby interpreter version upgrades, one minor version at a time
- **Skill Type:** Modular with external workflows, version guides, and reference material
- **Upgrade Strategy:** Sequential only (no version skipping, by default)
- **Methodology:** FastRuby.io upgrade philosophy — incremental, deprecation-first, verify before moving on — applied to the Ruby interpreter itself rather than to Rails

This skill is self-contained. It does not assume you have read or loaded any other skill. If a Ruby version bump is happening as part of a Rails upgrade project, that's useful context, but every step below works from a plain Ruby app's Gemfile and test suite alone.

---

## Core Methodology

1. **Latest patch first.** Before any minor hop, get onto the latest patch of the *current* minor. See "Why latest patch, specifically" below — the reason is different from why you'd do the same thing for a Rails patch bump.
2. **One minor version at a time.** Never jump two or more minors in a single hop, except as an explicit, user-approved exception for low-stakes apps.
3. **Deprecation warnings before the bump.** Ruby silently accumulates warnings about next-minor removals; turn them on and clear them before touching the Gemfile.
4. **Gemfile audit for Ruby-floor blockers**, both the kind Bundler can see (declared `required_ruby_version`) and the kind it can't (a gem's actual code calling something the target Ruby removed).
5. **Boot smoke test on the target Ruby**, because gems can pass every static check and still crash at runtime.
6. **Test suite as the gate**, at every step — never move to the next step on a red suite.

---

## Why Latest Patch, Specifically

This is the one place Ruby's Step 0 differs in *reasoning* from a similar-looking step in other upgrade skills, and it's worth stating explicitly so it doesn't get treated as generic "always update patches" advice:

**For Ruby, the latest patch of a minor is where that minor's accumulated deprecation warnings for the *next* minor's removals live.** Ruby's release process adds deprecation warnings to patch releases within a minor series as the *next* minor's removals get finalized — a `2.7.z` patch late in that series warns about more soon-to-be-3.0-removed behavior than `2.7.0` did. Being behind on patches means Step 2's deprecation sweep (below) runs against a Ruby that hasn't been told yet about everything the next hop will break. You can pass Step 2 clean on an old patch and still hit fresh breakage on the target minor, purely because the warning that would have caught it hadn't been backported to the patch you were running.

This is a different rationale from "bump to the latest patch because it has security and bug fixes," which is also true but is a generically-applicable reason that doesn't depend on the upgrade project at all — every app should stay on the latest patch of its current minor regardless of whether an upgrade is planned. The deprecation-surfacing property is specific to *why this matters for the upgrade project specifically*: skipping it means Step 2 gives a false sense of a clean baseline.

---

## CRITICAL: Sequential Upgrade Strategy

### Skipping Versions Is Not the Default

```
✅ Correct: 2.7 → 3.0 → 3.1 → 3.2 → 3.3 → 3.4
❌ Wrong:   2.7 → 3.2 (skipping 3.0 and 3.1)
```

Each minor's own deprecation warnings are what prepare an app for the *next* minor's removals. Skipping 3.0 and 3.1 to jump straight from 2.7 to 3.2 means the 2.7-era warnings for 3.0-era removals never ran, and the 3.0/3.1-era warnings for 3.1/3.2-era removals never ran either — every removal across three minors surfaces simultaneously, at the hop with the least ability to isolate which change broke what.

### The Exception

Multi-hop is allowed **only when the user explicitly asks for it**, typically because the app is small, a spike/exercise, or has already been audited by other means. When that happens:

1. Explain the sequential default and what skipping trades away (see above).
2. Confirm the user still wants to skip ahead.
3. Proceed, but raise scrutiny everywhere a single hop's step normally has to catch only one minor's worth of change — Step 2's deprecation sweep and Step 5's boot smoke test are now standing in for *every skipped hop's* changes at once, not just one, so treat any warning or failure there as potentially compound (multiple independent causes bundled into one error message) rather than assuming a single root cause.

---

## Ruby Version Timeline (for planning multi-hop distance)

| From | To | Notable removals / floor-relevant changes |
|------|-----|--------------------------------------------|
| 2.6.x | 2.7.x | Deprecation warnings added for most of what 3.0 removes; keyword-argument separation warnings begin |
| 2.7.x | 3.0.x | Keyword arguments fully separated from positional hashes; `Proc.new` with no block removed; `$SAFE` removed; bundled default gems begin moving out of implicit stdlib |
| 3.0.x | 3.1.x | `Time#+`/`Time#-` behavior tightened around fractional seconds; more stdlib libraries become bundled (not default) gems; `Struct.new` keyword_init inference changes |
| 3.1.x | 3.2.x | `Data.define` added; `it` block-arg experiment introduced later in the series; WeakMap/WeakRef changes; further bundled-gem migrations |
| 3.2.x | 3.3.x | New default Prism parser groundwork; `it` implicit block parameter stabilizes; YJIT becomes more broadly production-viable |
| 3.3.x | 3.4.x | Prism becomes the default parser; further stdlib-to-bundled-gem migrations |
| 3.4.x | 4.0.x | **Major.** No 3.5-3.9 exists -- 3.4 goes straight to 4.0. `ostruct` leaves the default gems (boot-blocker under Bundler if a dependency needs it -- Rails/zeitwerk does); more stdlib-to-bundled-gem migrations |

This table is for rough hop-distance planning only. Always check the specific version's own release notes and `NEWS.md` for the authoritative removal list before relying on anything here — Ruby's release notes are the ground truth, this table is a map, not the territory.

---

## Available Resources

### Core Documentation
- `SKILL.md` — this file (entry point)

### Version-Specific Guides (load as needed)
- `version-guides/upgrade-2.7-to-3.0.md`
- `version-guides/upgrade-3.0-to-3.1.md`
- `version-guides/upgrade-3.1-to-3.2.md`
- `version-guides/upgrade-3.2-to-3.3.md`
- `version-guides/upgrade-3.3-to-3.4.md`
- `version-guides/upgrade-3.4-to-4.0.md`

### Workflow Guides (load when executing each step)
- `workflows/test-suite-verification-workflow.md` — **MANDATORY FIRST STEP**
- `workflows/no-test-suite-smoke-workflow.md` — fallback when no runnable test suite exists
- `workflows/deprecation-warning-sweep-workflow.md` — Step 2
- `workflows/gemfile-ruby-floor-audit-workflow.md` — Step 3
- `workflows/boot-smoke-test-workflow.md` — Step 5
- `workflows/landing-workflow.md` — Step 7

### Reference Materials
- `references/ruby-patch-versions.md` — latest patch per minor, and how to check
- `references/deprecation-warnings.md` — how to turn on and read Ruby's own deprecation warnings
- `references/known-gotchas.md` — real, verified issues found upgrading Ruby in production apps
- `references/multi-hop-strategy.md` — planning a multi-hop Ruby upgrade

### Report Templates
- `templates/upgrade-report-template.md`

### Examples
- `examples/simple-upgrade.md` — single-hop upgrade example
- `examples/multi-hop-upgrade.md` — multi-hop upgrade example (the explicit-exception case)

---

## High-Level Workflow

### Step 0: Verify Latest Patch Version (MANDATORY PRE-STEP)

```
1. Read .ruby-version / the Gemfile's `ruby "X.Y.Z"` line for the current version
2. Read: references/ruby-patch-versions.md for how to find the latest patch of that minor
3. If current version < latest patch:
   - INFORM the user: "Your app is on Ruby X.Y.Z but the latest patch is X.Y.W"
   - Guide through the patch bump (.ruby-version, Gemfile, Dockerfile base image if any)
   - Run the test suite after the patch bump
   - Treat the patch bump as its own small, low-risk deploy, before starting the minor hop
   - Do NOT proceed to the minor hop until on the latest patch
4. If current version == latest patch:
   - Proceed to Step 1
```

See "Why Latest Patch, Specifically" above for the reasoning — it is not the same rationale as a Rails patch bump.

### Step 1: Run Test Suite (MANDATORY FIRST STEP)

```
1. Read: workflows/test-suite-verification-workflow.md
2. Detect test framework (RSpec, Minitest, or both)
3. Run the test suite
4. Capture results: total tests, passing, failing, pending
5. If no runnable test suite exists:
   - Read: workflows/no-test-suite-smoke-workflow.md
   - Run the safe, read-only smoke baseline: syntax/load check, boot, any build step
   - Record baseline confidence as partial
   - Continue only if the smoke baseline passes and the user accepts the risk
6. If ANY tests fail:
   - STOP. Report failing tests. Offer to help fix them.
   - Do NOT proceed until the suite is green.
```

### Step 2: Surface Deprecation Warnings on the CURRENT Ruby (MANDATORY)

```
1. Read: workflows/deprecation-warning-sweep-workflow.md
2. Read: references/deprecation-warnings.md
3. Run the test suite with RUBYOPT="-W:deprecated" (and -W:experimental where relevant)
4. Dedupe and triage every warning: app code (fix now) vs. gem code (check for a newer
   gem release, a maintained fork, or defer to the next hop if it's not yet breaking)
5. Fix every app-code warning before moving on
```

This is the step most likely to get skipped, because Ruby's own deprecation warnings are silent by default (unlike Rails, which prints its deprecations to the log at normal verbosity). Skipping it converts a one-warning-at-a-time triage into an all-at-once breakage on the target Ruby.

### Step 3: Audit the Gemfile for Ruby-Version Blockers

```
1. Read: workflows/gemfile-ruby-floor-audit-workflow.md
2. Check every gem's declared `required_ruby_version` against the target Ruby
   (cheap, static — bundler enforces this at `bundle lock` time)
3. Read: references/known-gotchas.md for gems with a *undeclared* floor — code that
   calls a removed API despite an honest-looking `required_ruby_version`
4. For any blocker, check the gem's CHANGELOG for a release that fixes it, a maintained
   fork, or whether the gem can be dropped/replaced
```

### Step 4: Bump the Version Pin and Re-lock

```ruby
# Gemfile
ruby "3.0.6"  # was "2.7.2" -- one minor at a time, latest patch of the target minor
```

```bash
bundle lock
bundle install
```

If `bundle lock` reports a conflict, it names the blocking gem and its requirement directly — resolve per Step 3 before moving on.

### Step 5: Boot Smoke Test (MANDATORY)

```
1. Read: workflows/boot-smoke-test-workflow.md
2. Run a command that actually loads the app under the target Ruby
   (e.g. `bundle exec rails runner "puts RUBY_VERSION"`, or the app's own boot entrypoint
   for a non-Rails app)
3. If it fails, the trace names the offending gem's file directly. Check that gem's
   CHANGELOG, bump it, and retry.
4. Re-run until it succeeds.
```

This is the step that catches gems whose declared Ruby floor was honest on paper but whose code calls something the target Ruby actually removed — see `references/known-gotchas.md` for confirmed real examples. Static analysis and `bundle install` cannot see this class of bug; only running the code does.

### Step 6: Fix Findings, Run Test Suite, Repeat Until Clean

```
1. Apply every finding from Step 2 and Step 5
2. Run the full test suite
3. Repeat Steps 4-6 until the suite is green on the target Ruby
```

Do not fix deprecation warnings that appear only *now*, as a side effect of the bump you just made, and that describe removals scheduled for the *next* minor past your current target. Note them for that next hop's own Step 2 sweep instead of expanding the scope of the hop in progress.

### Step 7: Land It

```
1. Read: workflows/landing-workflow.md
2. Update .ruby-version, Gemfile's `ruby` directive, Dockerfile base image (if any),
   CI's Ruby version config
3. Run the full suite one more time in the actual deploy-shaped environment
   (Docker/CI), not just locally
4. Commit and open the PR
```

### Step 8: Plan the Next Hop (or Stop)

If the target Rails/framework version (or any other floor-setting dependency) needs a higher Ruby than the one just landed, plan the next Ruby hop before it's needed rather than discovering the floor mismatch mid-upgrade of that dependency. Otherwise, this hop is done — repeat from Step 0 whenever the next hop is scheduled.

---

## Quality Checklist

Before calling a hop done:

- [ ] Started from the latest patch of the *current* minor (Step 0)
- [ ] Test suite was green before starting (Step 1), or the no-suite fallback ran and the user accepted the risk
- [ ] Deprecation sweep ran and every app-code warning was fixed (Step 2)
- [ ] Gemfile was audited for both declared and undeclared Ruby-floor blockers (Step 3)
- [ ] Boot smoke test passed on the target Ruby (Step 5)
- [ ] Test suite is green on the target Ruby (Step 6)
- [ ] `.ruby-version`, Gemfile, Dockerfile, and CI all agree on the new version (Step 7)
- [ ] Only one minor was bumped, or the multi-hop exception was explicitly confirmed with the user

## Success Criteria

A hop is successful when: the app boots and the full test suite passes on the target Ruby, patch and minor version are pinned consistently everywhere (`.ruby-version`, Gemfile, Dockerfile, CI), no unresolved deprecation warnings about the target minor's own removals remain in app code, and the change has been verified in a deploy-shaped environment (not just a local shell) at least once before merging.
