# Rails Upgrade Roadmap — {PROJECT_NAME}

**Generated:** {DATE} · by `/rails-roadmap`
**Current:** Rails {CURRENT_RAILS} on Ruby {CURRENT_RUBY}
**Target:** Rails {TARGET_RAILS} on Ruby {TARGET_RUBY}
**Path:** {HOP_COUNT} hops, {RUBY_BUMP_COUNT} Ruby bump(s)

> This is a **survey**, not an upgrade. Nothing in the application was changed to produce it.

---

## Summary

| | |
|---|---|
| Rails hops | {HOP_COUNT} |
| Ruby bumps | {RUBY_BUMP_COUNT} |
| Next hop | {HOP_1_FROM} → {HOP_1_TO} ({HOP_1_FINDING_COUNT} findings) |
| Gem blockers across the path | {BLOCKER_COUNT} |
| Gems outdated | {OUTDATED_COUNT} of {TOTAL_GEM_COUNT} |
| Gems sourced from git | {GIT_SOURCED_COUNT} |
| `load_defaults` gap | {LOAD_DEFAULTS_GAP} |

<!-- No cross-hop total of findings. The same line of code matches patterns in several hops;
     a summed figure would be inflated. Per-hop counts only. -->

---

## The path

```
{ORDERED_STEP_LIST}
```

<!-- e.g.
0. Patch     Rails 6.1.7.10 -> 6.1.7.12      latest patch of current series
1. Hop       Rails 6.1 -> 7.0    ACTIONABLE   12 findings
2. Hop       Rails 7.0 -> 7.1    INDICATIVE    8 patterns matched
3. Ruby      3.0.6 -> 3.3.x                   required by step 4
4. Hop       Rails 7.1 -> 7.2    INDICATIVE   15 patterns matched
5. Hop       Rails 7.2 -> 8.0    INDICATIVE   22 patterns matched
6. Hop       Rails 8.0 -> 8.1    INDICATIVE    4 patterns matched
-->

---

## Before anything else

- [ ] Test suite green. {TEST_SUITE_NOTE}
- [ ] On the latest patch of the current series: {PATCH_STEP}
- [ ] Dual-boot set up with `next_rails` — see the `dual-boot` plugin
- [ ] CI runs the suite on every push

The upgrade skill blocks on a red suite, and it is right to. A roadmap built on an app whose
tests don't pass is a roadmap with no way to tell whether a hop worked.

---

## Step {N} — Rails {FROM} → {TO}  ·  `ACTIONABLE`

**Ruby floor:** {RUBY_FLOOR} · {RUBY_FLOOR_STATUS}
**Guides:** [Official]({OFFICIAL_URL}) · [FastRuby.io]({FASTRUBY_URL})

{GUIDE_SUMMARY}

### Fix before bump ({COUNT})

<!-- kind: breaking and deprecation. Sub-ordered HIGH -> MEDIUM -> LOW. -->

#### {PATTERN_NAME}
`{KIND}` · {PRIORITY} · {OCCURRENCE_COUNT} occurrence(s)

{EXPLANATION}

**Fix:** {FIX}

```
{FILE}:{LINE}  {MATCHED_CONTENT}
{FILE}:{LINE}  {MATCHED_CONTENT}
```

{PREREQ_NOTE}

<!-- PREREQ_NOTE, when the pattern declared prereqs: and the lockfile is below the floor:
     > **Bump `rspec-rails` to >= 6.1.0 first.** config.fixture_paths= is forwarded from
     > RSpec::Core::Configuration only on 6.1+. On 6.0.x the fix below raises NoMethodError. -->

### Fix when ready ({COUNT})

<!-- kind: migration and optional. Same shape, lower urgency. -->

### Gems at this hop

**Blockers ({COUNT})** — no compatible version exists; fork, vendor, or replace

| Gem | Locked | Situation |
|---|---|---|
| {GEM} | {VERSION} | {DETAIL} |

**Required bumps ({COUNT})**

| Gem | Locked | Bump to |
|---|---|---|
| {GEM} | {VERSION} | {TARGET} |

Bump top-level gems before their transitive dependencies, and one at a time
(`bundle update <gem> --conservative`) so a bad resolution doesn't poison the graph.

---

## Step {N} — Rails {FROM} → {TO}  ·  `INDICATIVE`

> Surveyed against today's code. Earlier hops will change these files — re-run
> `/rails-roadmap` before starting this hop.

**Ruby floor:** {RUBY_FLOOR} · {RUBY_FLOOR_STATUS}
**Guides:** [Official]({OFFICIAL_URL}) · [FastRuby.io]({FASTRUBY_URL})

| Kind | Patterns | Occurrences |
|---|---|---|
| breaking | {N} | {N} |
| deprecation | {N} | {N} |
| migration | {N} | {N} |
| optional | {N} | {N} |

**Patterns matched:** {PATTERN_NAME} ({N}), {PATTERN_NAME} ({N}), …

### Gems at this hop

{GEM_BUCKETS}

---

## Step {N} — Ruby {FROM} → {TO}

Required by step {FORCING_STEP} (Rails {RAILS_VERSION} needs Ruby {FLOOR}+).

Targeting {TO} rather than the {FLOOR} floor so later hops don't force the work again.

- [ ] `.ruby-version`, `Gemfile`, `.tool-versions`
- [ ] CI matrix
- [ ] Dockerfile / deployment images
- [ ] `bundle_report compatibility --ruby-version={TO_MINOR}` for gems that won't survive it

---

## Dependency debt

{OUTDATED_COUNT} of {TOTAL_GEM_COUNT} gems are behind latest. Age matters more than count: a gem
four years stale is far likelier to block a hop than one four months stale, and git-sourced gems
can't be reasoned about by any compatibility checker.

| Gem | Installed | Age | Latest | Age |
|---|---|---|---|---|
| {NAME} | {INSTALLED} | {INSTALLED_AGE} | {LATEST} | {LATEST_AGE} |

{GIT_SOURCED_NOTE}

<!-- e.g. 3 gems are sourced from git. These bypass version resolution entirely — check each
     one's upstream manually before the hops that touch them. -->

---

## `load_defaults`

{LOAD_DEFAULTS_SECTION}

<!-- When there's a gap:
     `config.load_defaults {X.Y}` while running Rails {A.B} — {N} versions of framework
     defaults not yet adopted. This is separate from the version hops: the app runs fine, but
     it isn't getting the behaviour of the Rails it's on, and each hop widens the gap.
     Walk it with the `rails-load-defaults` plugin, one config at a time, after a hop lands. -->

---

## What this roadmap does not tell you

- **Later hops decay.** Only the first hop's findings carry file:line, because only the first
  hop is measured against code that will still look like this when you start it.
- **Counts don't add up across hops.** One line can match patterns in three different hops.
  There is deliberately no project-wide total.
- **Compatible ≠ working.** `bundle_report` reads gemspec constraints. A gem can accept the
  target Rails and still call an internal that was removed. Only a boot and a green suite settle
  it.
- **Custom code is invisible here.** Monkey patches, vendored engines, and anything
  metaprogrammed won't match a regex. Budget for what the greps can't see.
- **This is a snapshot** taken {DATE}. Re-run it per hop.

{UNAVAILABLE_SECTIONS}

<!-- UNAVAILABLE_SECTIONS lists anything that could not be checked and why — next_rails absent,
     network down, pattern file missing for a hop, a Grep that errored. Never omit a check
     silently; an empty section reads as "no problems found". -->

---

## Next

- **`rails-upgrade`** — executes hop 1, same buckets as above
- **`dual-boot`** — `next_rails` setup, before the first hop
- **`rails-load-defaults`** — the `load_defaults` gap
- [The FastRuby.io upgrade series](https://www.fastruby.io/blog/rails/upgrade/rails-upgrade-series.html)
