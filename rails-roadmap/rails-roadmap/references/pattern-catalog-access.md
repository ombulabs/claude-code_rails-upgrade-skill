# Reaching the `rails-upgrade` Pattern Catalog

**Purpose:** This plugin owns no detection patterns. It reads the 225-pattern catalog and the
13 version guides that ship with the `rails-upgrade` plugin. This file documents how to find
them and what to do when they are missing.

**When to use:** Step 2 of `workflows/roadmap-orchestration-workflow.md`, before any surveying.

---

## Why this file exists

`rails-roadmap` and `rails-upgrade` live in the same git repository as sibling plugins, so it
is tempting to assume the roadmap can read `../rails-upgrade/detection-scripts/patterns/`.
**It cannot.** Claude Code installs each plugin as its own extracted subtree, not as a clone
of the source repo.

Measured on a real install (`claude-plugins-official`, whose source repo holds 37 sibling
plugins under `plugins/`):

```
source repo      plugins/frontend-design/        <- 36 siblings alongside it
installed        cache/claude-plugins-official/frontend-design/unknown/
                   .claude-plugin/  LICENSE  README.md  skills/
```

The installed directory contains that plugin's subtree and nothing else. No sibling plugins,
no repo root. So from the plugin root:

| Expression | Resolves to | Useful? |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}/../rails-upgrade/` | `cache/<marketplace>/rails-roadmap/rails-upgrade/` | No — does not exist |
| `${CLAUDE_PLUGIN_ROOT}/../` | `cache/<marketplace>/rails-roadmap/` | Only version dirs of *this* plugin |
| `${CLAUDE_PLUGIN_ROOT}/../../rails-upgrade/*/` | `cache/<marketplace>/rails-upgrade/<version>/` | **Yes** |

The install layout is `cache/<marketplace>/<plugin-name>/<version>/`, so a sibling plugin from
the *same marketplace* is two levels up and one across, with a glob for the version.

---

## Search order

Try these in order and use the first that contains `rails-72-patterns.yml`:

1. **Same-marketplace sibling** (the normal case):
   `${CLAUDE_PLUGIN_ROOT}/../../rails-upgrade/*/detection-scripts/patterns/`

2. **Any installed copy**, for users who installed `rails-upgrade` from a different
   marketplace or at a different scope:
   `${CLAUDE_PLUGIN_ROOT}/../../../*/rails-upgrade/*/detection-scripts/patterns/`

3. **Development checkout**, for anyone working in the source repo itself:
   `${CLAUDE_PROJECT_DIR}/rails-upgrade/detection-scripts/patterns/`
   and `${CLAUDE_PLUGIN_ROOT}/../rails-upgrade/detection-scripts/patterns/`
   (this last one *does* work in a source checkout, where the sibling really is adjacent —
   it only fails once installed)

Use `Glob` for these, not `ls`. Resolve the version guides from the same base by swapping
`detection-scripts/patterns/` for `version-guides/`.

When a candidate matches, record the resolved absolute base path once and reuse it for the
whole run. Do not re-glob per hop.

---

## When the catalog is not found

**Stop. Do not generate a roadmap.**

Say plainly that `rails-upgrade` is required and is not installed:

> This roadmap reads its detection patterns from the `rails-upgrade` plugin, which doesn't
> appear to be installed. Install it and re-run:
>
>     /plugin install rails-upgrade@ombulabs-ai

Do **not** fall back to generating a roadmap from the version guides alone, from general Rails
knowledge, or from a partial catalog. A roadmap whose per-hop findings came from the model's
memory rather than from grepping the user's code looks identical to a real one and is worth
less than nothing — the entire value of this command is that its counts are measured. Silent
degradation here is the single worst failure mode this plugin has.

The same rule applies to a *partial* catalog: if the patterns directory resolves but a hop in
the computed chain has no matching `rails-<XY>-patterns.yml`, mark that hop
`NOT SURVEYED — pattern file missing` in the document. Never leave it looking clean.

---

## Version skew

The resolved catalog may be older or newer than this plugin. Read `version:` from each pattern
file and trust it over any assumption baked in here. If a hop's pattern file is missing
entirely, that is the skew case above — report it, don't paper over it.
