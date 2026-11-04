# External Guides and Per-Hop Ruby Floors

**Purpose:** One lookup table per upgrade hop: the official Rails guide anchor, the FastRuby.io
companion post, and the Ruby version floor. This is the roadmap's source for "what should the
reader go read" and "does a Ruby bump belong before this hop".

**When to use:** Steps 3 and 6 of `workflows/roadmap-orchestration-workflow.md`.

---

## The table

Ruby floors are transcribed from the two "Supported Upgrade Paths" tables in the `rails-upgrade`
skill's `SKILL.md`. That prose table is the authoritative in-repo source — **not** the pattern
files. Only the 7.1 and 7.2 pattern files carry a `dependencies.ruby` block; the other ten have
none, so reading Ruby floors from the catalog would silently produce nothing for most hops.

Official anchors are on `https://guides.rubyonrails.org/upgrading_ruby_on_rails.html`.

| Hop | Ruby floor | Official anchor | FastRuby.io |
|---|---|---|---|
| 2.3 → 3.0 | 1.8.7–1.9.3 | *(none — guide starts at 3.0)* | `/blog/rails/upgrades/upgrade-to-rails-3.html` |
| 3.0 → 3.1 | 1.8.7–1.9.3 | `#upgrading-from-rails-3-0-to-rails-3-1` | `/blog/rails/upgrades/upgrade-to-rails-3-1.html` |
| 3.1 → 3.2 | 1.8.7–2.0 | `#upgrading-from-rails-3-1-to-rails-3-2` | `/blog/rails/upgrades/upgrade-to-rails-3-2.html` |
| 3.2 → 4.0 | 1.9.3+ | `#upgrading-from-rails-3-2-to-rails-4-0` | `/blog/rails/upgrades/upgrade-rails-from-3-2-to-4-0.html` |
| 4.0 → 4.1 | 1.9.3+ | `#upgrading-from-rails-4-0-to-rails-4-1` | `/blog/rails/upgrades/upgrade-rails-from-4-0-to-4-1.html` |
| 4.1 → 4.2 | 1.9.3+ | `#upgrading-from-rails-4-1-to-rails-4-2` | `/blog/rails/upgrades/upgrade-rails-from-4-1-to-4-2.html` |
| 4.2 → 5.0 | 2.2.2+ | `#upgrading-from-rails-4-2-to-rails-5-0` | `/blog/rails/upgrades/upgrade-rails-from-4-2-to-5-0.html` |
| 5.0 → 5.1 | 2.2.2+ | `#upgrading-from-rails-5-0-to-rails-5-1` | `/blog/rails/upgrades/upgrade-rails-from-5-0-to-5-1.html` |
| 5.1 → 5.2 | 2.2.2+ | `#upgrading-from-rails-5-1-to-rails-5-2` | `/blog/rails/upgrades/upgrade-rails-from-5-1-to-5-2.html` |
| 5.2 → 6.0 | 2.5.0+ | `#upgrading-from-rails-5-2-to-rails-6-0` | `/blog/rails/upgrades/upgrade-rails-from-5-2-to-6-0.html` |
| 6.0 → 6.1 | 2.5.0+ | `#upgrading-from-rails-6-0-to-rails-6-1` | `/blog/rails/upgrades/upgrade-rails-from-6-0-to-6-1.html` |
| 6.1 → 7.0 | 2.7.0+ | `#upgrading-from-rails-6-1-to-rails-7-0` | `/blog/rails/upgrades/upgrade-rails-6-1-to-7-0.html` |
| 7.0 → 7.1 | 2.7.0+ | `#upgrading-from-rails-7-0-to-rails-7-1` | `/blog/rails/upgrades/upgrade-rails-7-0-to-7-1.html` |
| 7.1 → 7.2 | 3.1.0+ | `#upgrading-from-rails-7-1-to-rails-7-2` | `/blog/upgrade-rails-7-1-to-7-2.html` |
| 7.2 → 8.0 | 3.2.0+ | `#upgrading-from-rails-7-2-to-rails-8-0` | `/blog/upgrade-rails-7-2-to-8-0.html` |
| 8.0 → 8.1 | 3.2.0+ | `#upgrading-from-rails-8-0-to-rails-8-1` | `/blog/upgrade-rails-8-0-to-8-1.html` |

FastRuby paths are relative to `https://www.fastruby.io`. **Note the path change after 7.1** —
hops up to 7.0 → 7.1 live under `/blog/rails/upgrades/`, and 7.1 → 7.2 onward live directly
under `/blog/`. Do not construct these URLs from a template; use the table.

The index of the whole series is
`https://www.fastruby.io/blog/rails/upgrade/rails-upgrade-series.html`. Link it once in the
roadmap's closing section.

---

## Ruby floors are floors, not targets

The floor column is the minimum Ruby that the target Rails will run on. It is not what the
reader should upgrade *to*. When the roadmap emits a Ruby bump step, target the latest stable
patch of a supported line, not the floor — landing exactly on the floor means doing the Ruby
work again at the next hop that raises it.

Two floors in the modern range actually bite, and they are where Ruby bump steps belong:

- **7.1 → 7.2** raises the floor to 3.1.0
- **7.2 → 8.0** raises it to 3.2.0

An app already on Ruby 3.3+ clears every hop in the 7.x–8.x range and needs no interleaved Ruby
step at all. Say so explicitly rather than emitting a no-op step.

---

## Fetch policy

**Fetch the two guides for hop 1 only.** Use `WebFetch` on the official anchor and the FastRuby
post for the immediate next hop, to enrich its `ACTIONABLE` section with specifics the pattern
catalog doesn't carry. For every later hop, emit the links without fetching.

This is a deliberate bound. Fetching all 16 posts plus 15 guide anchors would add minutes of
latency to produce prose the reader will not act on for months.

If a fetch fails or times out, **emit the link and move on**. A third-party site being down is
not a reason to fail a roadmap, and it is not worth a retry loop. Note the skip in the document
so the reader knows that section is thinner than it would otherwise be.

---

## Guides are context, not findings

Never let fetched guide prose become a roadmap finding. Findings come from grepping the user's
code against the pattern catalog; guide content only explains findings that already exist. A
roadmap that lists "Zeitwerk migration" because the guide mentions it — rather than because the
app has `config.autoloader = :classic` at a real file:line — is exactly the failure mode this
plugin exists to avoid.
