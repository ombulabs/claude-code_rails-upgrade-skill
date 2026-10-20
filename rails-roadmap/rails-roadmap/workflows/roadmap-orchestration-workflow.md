# Roadmap Orchestration Workflow

**Purpose:** The spine. Sequences every other workflow and assembles `RAILS_ROADMAP.md`.

**When to use:** Invoked by `/rails-roadmap`. Follow it end to end.

> **Read-only.** This command surveys; it does not upgrade. No application file is edited, no
> `bundle install` or `bundle update` is run, no dual-boot is set up. The sole write is
> `RAILS_ROADMAP.md`, under the rules in Step 8.

---

## Step 1: Confirm this is a Rails app, and warn about cost

Check for `Gemfile.lock` and `config/application.rb`. If either is missing, say what you were
looking for and stop.

Then, once the hop chain is known (Step 3), tell the user what they are in for **before** the
expensive part:

> Rails 6.1.7.10 → 8.1.2 is 5 hops. I'll grep ~72 detection patterns and run
> `bundle_report compatibility` once per hop — that last part is the slow bit, roughly a minute
> each since it fetches metadata for the whole bundle. Want the full survey, or just the next
> hop and the final target?

Wait for an answer when the chain is **4 hops or more**. Below that, proceed. A legacy app on
4.0 has a 12-hop chain and a dozen `bundle_report` runs; springing that on someone who expected
a quick summary is the wrong default.

---

## Step 2: Locate the pattern catalog

Follow `references/pattern-catalog-access.md`.

If the catalog cannot be found, **stop and tell the user to install `rails-upgrade`**. Do not
generate a roadmap from version guides or from general Rails knowledge. That file explains why
at length; the short version is that an unmeasured roadmap is indistinguishable from a measured
one and worth less than nothing.

---

## Step 3: Resolve versions and the hop chain

Follow `workflows/roadmap-versions-workflow.md`. It returns the ordered chain of Rails hops and
interleaved Ruby bumps, plus the current-series patch step and any `load_defaults` gap.

Deliver the cost warning from Step 1 now that the hop count is known.

---

## Step 4: Fetch hop 1's guides

Per `references/external-guides.md`: `WebFetch` the official Rails anchor and the FastRuby.io
post **for the first hop only**. Later hops get links without fetching.

On failure, keep the link and move on. Never block a roadmap on a third-party site, and never
retry in a loop.

---

## Step 5: Survey the code

Follow `workflows/roadmap-survey-workflow.md`. Hop 1 comes back `ACTIONABLE` with file:line;
hops 2..N come back `INDICATIVE` with counts.

---

## Step 6: Check gem compatibility

The mechanics are already fully specified in the `rails-upgrade` plugin's
gem-compatibility workflow — the `bundle_report` invocation, its three-bucket output mapping,
the railsbump API protocol, and the reconciliation rules. **Read that file and follow it.** Do
not restate or reimplement it here. What follows is only what differs for a roadmap.

### Once per hop

```bash
bundle exec bundle_report compatibility --rails-version=<hop target>
```

Run this for **every hop in the chain**, not just the next one. Per-hop results are what let the
roadmap say "this gem blocks you at 7.2, not at 8.0" instead of collapsing every blocker into
one undifferentiated pile at the end.

This is the slow part. Each run makes Bundler fetch metadata for the whole bundle. Five hops is
roughly five minutes; twelve hops is substantially worse. The Step 1 warning exists for this.

Map output into the three buckets the existing workflow defines: **required bumps**, **blockers**,
**already compatible**. If a run produces no `=> incompatible with rails X` headers at all,
treat it as a failure to parse — not as "everything is compatible."

### Dependency debt, once

```bash
bundle_report outdated --json
```

Run this **once**, not per hop. It is relative to the lockfile, not to any Rails target, so
repeating it per hop returns identical output.

It yields `outdated_gems` (each with `name`, `installed_version`, `installed_age`,
`latest_version`, `latest_age`), plus `sourced_from_git_count` and `total_gem_count`. This
becomes the roadmap's dependency-debt section: gems years behind latest are the ones most likely
to block a hop somewhere down the chain, and git-sourced gems are the ones no compatibility
checker can reason about at all.

### railsbump stays opt-in

The existing workflow already treats railsbump as the secondary check, escalated only under
specific conditions. Keep that. Its polling protocol caps at 30 minutes per lockfile, which
makes it unsuitable for an unattended per-hop loop.

Offer it, once, when `bundle_report` reported blockers with no compatible version — those are
exactly the cases where railsbump's view of the real resolution graph can overturn the verdict.

### When the tooling is missing

If `next_rails` is not installed, or `bundle exec` fails, or the network is down: **mark the gem
sections unavailable and say why.** An empty gem section reads as "no gem problems," which is a
materially different and much more encouraging claim than "not checked."

---

## Step 7: Assemble the document

Read `templates/roadmap-template.md` and fill it from everything gathered.

Rules that matter more than the template:

- **Never sum occurrence counts across hops into a project total.** The same line can match
  patterns in three hops. A headline "247 issues" is inflated and travels badly.
- **Every indicative hop carries its re-run caveat.** Verbatim, per the survey workflow.
- **Quote `explanation` and `fix` verbatim** from the pattern files.
- **Effort estimates are ranges with stated assumptions, or they are omitted.** A roadmap is
  read by people who will turn a number into a commitment. If you give one, say what it assumes
  (test coverage, team familiarity, whether blockers are resolved) and give a range.
- Nothing is a finding unless it came from a grep hit or a tool's output.

---

## Step 8: Write `RAILS_ROADMAP.md`

Target the project root.

**Check for an existing file first.** Re-running after completing a hop is the main repeat use
case, and by then the file may be committed, annotated, or assigned. Overwriting it silently
would destroy work.

- **No existing file** → write it. Report the path and a summary.
- **Existing file** → read it, summarise what changed (hops completed, findings resolved,
  new blockers), and **ask before writing**. Offer to write alongside it if they would rather
  keep both.

Report a short summary to the conversation, not the whole document:

```
Wrote RAILS_ROADMAP.md (412 lines)

  Rails 6.1.7.10 -> 8.1.2   5 hops
  Ruby  3.0.6    -> 3.3.x   1 bump, before the 7.2 hop
  Hop 1 (6.1 -> 7.0): 12 findings, 8 fix-before-bump
  Gem blockers: 3 at 7.2, 2 at 8.0
  load_defaults gap: 5.2 behind 6.1
```

Do not dump 400 lines into the conversation. The document is the deliverable; the terminal gets
the headline.

---

## Step 9: Point at what comes next

Close by naming the tools for the actual work, so the roadmap is a starting point rather than a
dead end:

- `rails-upgrade` — executes hop 1 with the same buckets this roadmap used
- `dual-boot` — the `next_rails` setup that should precede the first hop
- `rails-load-defaults` — the `load_defaults` gap, which is separate work from the version hops

Do not offer to start the upgrade in the same breath. The user asked for a map.
