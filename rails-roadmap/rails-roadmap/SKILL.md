---
name: rails-roadmap
description: Surveys a Rails application read-only and writes RAILS_ROADMAP.md — the full ordered list of action steps needed to reach the latest Ruby and Rails, hop by hop, with per-hop breaking changes, gem compatibility, and Ruby floors. Use when the user wants to scope or plan an upgrade, estimate what it would take, or answer "how far behind are we?" without starting the work. Based on FastRuby.io methodology and "The Complete Guide to Upgrade Rails" ebook.
argument-hint: "[target-rails-version]"
---

# Rails Roadmap

## Identity

- **Purpose:** Answer "what would it take to get current?" without starting the work
- **Output:** One committable markdown file, `RAILS_ROADMAP.md`
- **Mode:** Read-only with respect to the application
- **Attribution:** Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)

---

## The boundary

The other plugins in this family **execute** upgrades. This one **surveys** them.

That distinction is the whole design. A team deciding whether to fund an upgrade, or a developer
sizing one before writing a ticket, needs a picture of the road — not a dual-boot setup and a
half-applied first hop. So this plugin never edits an application file, never runs
`bundle install` or `bundle update`, never sets up dual-boot, and never applies a fix.

The one thing it writes is `RAILS_ROADMAP.md`.

When the user actually wants to *do* the upgrade, hand off to `rails-upgrade`.

---

## Dependencies

- **`rails-upgrade`** ([github.com/ombulabs/claude-code_rails-upgrade-skill](https://github.com/ombulabs/claude-code_rails-upgrade-skill))
  — **Required.** This plugin owns no detection patterns. It reads that plugin's catalog of 225
  patterns, its version guides, and its gem-compatibility workflow. Without it installed,
  `/rails-roadmap` stops rather than guessing. See `references/pattern-catalog-access.md`.
- **`next_rails` gem** (in the target app) — provides `bundle_report`, used for per-hop gem
  compatibility and the dependency-debt section. Optional: without it those sections are marked
  unavailable rather than omitted.
- **`rails-load-defaults`** ([github.com/ombulabs/claude-code_rails-load-defaults-skill](https://github.com/ombulabs/claude-code_rails-load-defaults-skill))
  — not required. The roadmap reports a `load_defaults` gap and points there; it does not plan
  that work.

---

## Trigger patterns

- "How far behind is this app?"
- "What would it take to get to the latest Rails?"
- "Generate an upgrade roadmap"
- "Scope our Rails upgrade" / "estimate the upgrade"
- "What Rails and Ruby versions should we be targeting?"
- "Plan the path from Rails X to latest"

Invoked directly as `/rails-roadmap`, optionally with a target: `/rails-roadmap 8.0`.

**Not** for: performing an upgrade, fixing a breaking change, or analysing a single hop in
depth. Those are `rails-upgrade`.

---

## How it works

1. Locate the `rails-upgrade` pattern catalog — stop if it isn't there
2. Resolve current Rails/Ruby, the destination, and the ordered hop chain
3. Fetch the official and FastRuby.io guides for the first hop only
4. Grep every hop's patterns, tiered by confidence
5. Run `bundle_report compatibility` per hop and `bundle_report outdated` once
6. Assemble and write `RAILS_ROADMAP.md`

### Confidence tiering

The core idea. Hop 1 is measured against code the reader has today and will act on this week —
it gets file:line. Hops 2..N are measured against that same code, but the reader won't reach
them until earlier hops have rewritten it — they get counts only, plus a standing instruction to
re-run.

Presenting both at equal fidelity would invite planning hop 4 in detail against references that
will be stale by the time anyone gets there.

---

## Available resources

### Workflows

- `workflows/roadmap-orchestration-workflow.md` — the spine; sequences everything and writes the file
- `workflows/roadmap-versions-workflow.md` — current state, destination, hop chain, interleaved Ruby bumps
- `workflows/roadmap-survey-workflow.md` — multi-hop confidence-tiered pattern detection

### References

- `references/pattern-catalog-access.md` — how to reach the `rails-upgrade` catalog, and what to do when it's absent
- `references/external-guides.md` — per-hop official + FastRuby.io URLs and Ruby floors

### Templates

- `templates/roadmap-template.md` — the shape of `RAILS_ROADMAP.md`

---

## Principles

1. **Never write to an application file.** `RAILS_ROADMAP.md` is the only exception.
2. **Never fabricate a finding.** Everything in the document comes from a grep hit or a tool's
   output. If the catalog is missing, stop — do not generate from Rails knowledge.
3. **Never silently omit a check.** A gem section that couldn't run says so. An empty section
   reads as "no problems," which is a much stronger and different claim.
4. **Never sum occurrences across hops.** One line matches patterns in several hops; a
   project-wide total is inflated and it is the number that ends up in a slide deck.
5. **Tier by confidence and say so.** Later hops decay. The document should admit that on every
   indicative section.
6. **Quote `explanation` and `fix` verbatim** from the pattern files. They were reviewed against
   the version guides; paraphrase is how accuracy drifts.
7. **Warn before the slow part.** Per-hop `bundle_report` is roughly a minute per hop. Tell the
   user the hop count and offer to narrow before starting.
8. **Don't clobber an existing roadmap.** Diff and ask. A re-run after a completed hop is the
   main repeat case, and by then the file may be committed and annotated.
9. **Hand off, don't drift.** Close by naming `rails-upgrade`, `dual-boot`, and
   `rails-load-defaults`. Don't offer to start the upgrade — the user asked for a map.

---

See [CHANGELOG.md](CHANGELOG.md) for version history.
