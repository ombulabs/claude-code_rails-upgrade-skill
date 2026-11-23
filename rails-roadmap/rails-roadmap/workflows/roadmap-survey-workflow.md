# Roadmap Survey Workflow

**Purpose:** Run the detection pattern catalog against the codebase for **every hop** in the
chain, and return findings tiered by how much they can be trusted.

**When to use:** Step 5 of `workflows/roadmap-orchestration-workflow.md`, after the hop chain is
computed and the catalog is located.

> **This workflow reads and counts. It never writes, never edits, never fixes.** The
> `rails-upgrade` plugin's detection workflow feeds an implementation step; this one feeds a
> document. Same patterns, opposite intent. If you find yourself about to change an application
> file, you are in the wrong workflow.

---

## Why tiering, and why it is the whole point

The obvious way to survey five hops is to grep all five pattern sets and present every hit the
same way. That produces a document that is confidently wrong about most of its own content.

Hop 1 is grepped against the code the reader has today, and they will act on it this week — its
file:line references are real. Hop 4 is grepped against that same code, but the reader will not
reach hop 4 until hops 1–3 have rewritten large parts of it. Those findings are a **signal about
scale**, not a task list. Some will be gone; new ones will have appeared.

Presenting both at the same fidelity invites the reader to plan hop 4 in detail against
references that will be stale by the time they get there. So:

| Tier | Which hops | What it carries |
|---|---|---|
| `ACTIONABLE` | Hop 1 only | file:line, matched content, `kind`, `priority`, the `fix:` text, checked `prereqs:` |
| `INDICATIVE` | Hops 2..N | Per-pattern counts, pattern `name`, `kind`, `priority`. No file:line, no code |

---

## Step 1: Load the hop's pattern file

Read `rails-<MAJORMINOR>-patterns.yml` from the base path resolved via
`references/pattern-catalog-access.md`. No dot in the filename: the 7.2 hop is
`rails-72-patterns.yml`.

Each file has `upgrade_findings` split into `high_priority`, `medium_priority`, and
`low_priority`. Every entry carries eight required keys — `name`, `kind`, `pattern`, `exclude`,
`search_paths`, `explanation`, `fix`, `variable_name` — and may optionally carry `prereqs:`.

`kind` is one of `breaking`, `deprecation`, `migration`, `optional`. It decides the bucket;
`priority` decides ordering within it.

If the file is absent, mark the hop `NOT SURVEYED — pattern file missing` and move on. Do not
substitute knowledge of what usually changes in that Rails version.

---

## Step 2: Grep the patterns

For each entry, run `Grep` with the entry's `pattern` across each of its `search_paths`, then
drop any hit matching the entry's `exclude` regex (when `exclude` is non-empty).

**Batch aggressively.** Issue every `Grep` for a hop in a single message so they run
concurrently. This is the difference between a roadmap that takes one minute and one that takes
ten.

Two things not to bother with:

- **Do not build a dedup layer across hops.** There are 236 pattern entries in the catalog and
  225 distinct `variable_name`s — only 11 repeat. Deduplication would add real complexity to
  save under 5% of the greps.
- **Do not grep the whole catalog.** Only the hops in the computed chain. An app on 6.1 heading
  to 8.1 greps ~72 patterns; one on 4.0 greps ~220. The chain bounds the cost, not the catalog.

An entry whose `pattern` is the empty string is path-based detection (e.g. `VENDOR_PLUGINS`) —
check for the existence of its `search_paths` instead of grepping.

If a `Grep` errors, record the pattern as not-checked and carry that into the document. A
pattern that failed to run is not a pattern that found nothing.

---

## Step 3: Tier 1 — the actionable hop

For hop 1 only, build a full entry per pattern that matched:

```
{
  variable_name: "SECRETS_REMOVED",
  name: "Rails.application.secrets removed",
  kind: "breaking",
  priority: "high_priority",
  explanation: "...",          # verbatim from the pattern file
  fix: "...",                  # verbatim from the pattern file
  occurrences: 2,
  files: [
    { path: "config/initializers/api.rb", line: 3, content: "Rails.application.secrets.api_key" },
    { path: "app/models/user.rb",         line: 78, content: "..." }
  ]
}
```

Quote `explanation` and `fix` verbatim. They were written and reviewed against the version
guides; paraphrasing them in a roadmap is how accuracy drifts.

**Resolve `prereqs:` for hop 1.** When a matched entry declares `prereqs:`, check each one
against `Gemfile.lock`:

- Prereq has a `when:` condition that doesn't apply → ignore it.
- Named gem is at or above `min_version` → ignore it.
- Named gem is below `min_version` → emit a **separate step, ordered before the finding it
  guards**, saying to bump that gem first, with the prereq's `reason` as justification.

This is what turns "rename `fixture_path` to `fixture_paths`" from advice that raises
`NoMethodError` into a two-step sequence that works. Only `rails-72-patterns.yml` uses
`prereqs:` today, but handle it generally.

Read the affected files for context where it sharpens the finding. Do not read every file in
every finding — that is a lot of tokens for a document the reader will skim.

---

## Step 4: Tier 2 — the indicative hops

For hops 2..N, collapse to counts. Per pattern that matched, keep only:

```
{ variable_name: "AR_CONNECTION", name: "ActiveRecord.connection deprecated",
  kind: "deprecation", priority: "high_priority", occurrences: 14 }
```

No file paths, no line numbers, no code excerpts, no `fix:` text. If the reader wants that
detail they should re-run the roadmap when they reach the hop — which is exactly what the
caveat on each indicative section tells them to do.

Roll up a per-hop summary by `kind` so the reader can compare hop weights at a glance:

```
Hop 4 of 5 — Rails 7.2 -> 8.0   INDICATIVE
  breaking     6 patterns, 23 occurrences
  deprecation  3 patterns,  9 occurrences
  migration    4 patterns, 31 occurrences
  optional     2 patterns,  2 occurrences
```

Occurrence counts across hops are **not additive** into a project total. The same line of code
can match patterns in three different hops, and fixing it once may clear all three. Never sum
them into a headline "247 issues" figure — it is inflated and it is the kind of number that ends
up in a slide deck.

---

## Step 5: Bucket by `kind`

Within every hop, at either tier, group findings the way the `rails-upgrade` detection workflow
already does:

- **Fix before bump** — `kind: breaking` and `kind: deprecation`. Breaking blocks the upgrade;
  deprecation warns at this hop and usually becomes breaking at the next. Same campaign.
- **Fix when ready** — `kind: migration` and `kind: optional`. Silent and fully working at this
  hop.

Sub-order by `priority` (HIGH → MEDIUM → LOW) inside each bucket.

Keeping the same two buckets as `rails-upgrade` matters: a reader who takes the roadmap into the
upgrade skill should see the same shape, not a second taxonomy to translate.

---

## Step 6: Return the survey

Hand back, per hop: the tier, the two buckets with their findings, the per-`kind` rollup, any
`prereqs:`-derived gem bump steps, and the list of patterns that errored or were not checked.

Every indicative hop carries this caveat verbatim into the document:

> Surveyed against today's code. Earlier hops will change these files — re-run `/rails-roadmap`
> before starting this hop.
