# Workflow 08: Generate Upgrade Report

**Purpose:** Fill `templates/upgrade-report-template.md` with what Workflows 00 to 07 produced, so the user gets one document with every finding in its bucket, the user's own code, and a migration plan that matches the dual-boot flow the skill follows.

**When to use:** After Workflow 07. Deliverable 1 of two; the app:update preview is Workflow 09.

---

## Inputs

- `tmp/pattern-scan.json` from Workflow 05: every pattern's status, `kind`, `priority`, explanation, fix, `prereqs:` and sites with file:line, plus a `summary` block with the counts; or, when the scanner did not run, Workflow 05's Grep findings
- Workflow 05's findings review note: dropped false positives and prereq gem bumps
- Exact current and target versions, patch status (from Workflow 00), baseline suite numbers (from Workflow 01)
- `version-guides/upgrade-{FROM}-to-{TO}.md` and `templates/upgrade-report-template.md`
- Deprecation inventory (from Workflow 02): fixed entries for the baseline, deferred entries for the fix-before-bump bucket
- Gem compatibility buckets (from Workflow 06), boot smoke test report block and models suite result under `Gemfile.next` (from Workflow 07)

## Outputs

- **Deliverable #1: Comprehensive Upgrade Report.** A report covering findings grouped into the two buckets defined in `workflows/05-detect-breaking-changes-workflow.md` — **fix-before-bump** (`kind: breaking` and `kind: deprecation`) and **fix-when-ready** (`kind: migration` and `kind: optional`) — with OLD vs NEW code examples taken from the user's actual files, custom-code warnings flagged with ⚠️, a step-by-step migration plan, a testing checklist, and a rollback plan.

## Gates (must be true before the next workflow that runs)

- Report built from `templates/upgrade-report-template.md`, every placeholder replaced
- Every finding in the report is an actual detection finding with a real file:line reference, no generic examples
- Custom code flagged with ⚠️ warnings based on detected issues
- Migration plan uses `Gemfile.next` and defers `load_defaults` to Workflow 12; no effort or risk estimate
- Step 8 quality check passed and the report delivered

---

## Step 1: Gather the inputs

Collect, without re-deriving anything:

| From | What |
|------|------|
| Workflow 00 | exact current version, whether it is the latest patch |
| Workflow 01 | test count, assertions, failures on the current version |
| Workflow 02 | deprecation inventory: fixed entries; entries deferred to the bump (setter removed on {TO}); entries deferred to a later hop or owned by a gem |
| Workflow 05 | `tmp/pattern-scan.json`: `summary` (patterns checked and fired, sites, files, counts by kind, `unscanned`, `suppressed`) and one entry per pattern with `status`, `bucket`, `kind`, `priority`, `explanation`, `fix`, `sites`, `guide_entry`. Only `status: "found"` entries become findings. Check that its `to` is this report's {TO}; a file from another hop is stale, rerun Workflow 05 Step 2. Plus the findings review note: dropped false positives, prereq gem bumps, anything found by hand. When there is no JSON (Grep fallback, or a hop with no patterns file), use Workflow 05's Grep findings and count patterns from the patterns file |
| Workflow 06 | gem buckets: required bumps, blockers, already compatible; which check ran |
| Workflow 07 | boot smoke block, gem bumps found at boot, suite result under `Gemfile.next` and its failures, and every `DEPRECATION WARNING` line {TO} emitted at boot or during the suite |
| Workflow 04 | what changed in the working tree (Gemfile, lockfiles), committed or not |

Everything in the report comes from these. If a run skipped a workflow (request shape, blocked step), the corresponding section says so instead of being invented.

## Step 2: Load the version guide

For each finding take the guide entry's "What Changed" text and its BEFORE / AFTER fix from `version-guides/upgrade-{FROM}-to-{TO}.md`. Do not read the whole guide: `ruby <skill>/detection-scripts/scan_patterns.rb --explain VAR1,VAR2` prints the patterns' explanation and fix and, for each pattern whose guide entry carries its `**Pattern:**` marker, the entry text itself (the JSON `guide_entry` gives the same entry's line range). For a guide without markers it prints a line-numbered index of the guide's entries instead, so read each needed entry with `offset` / `limit`. The guide's Common Issues section (also in the index) maps a test failure or a warning text back to an entry by symptom; read it when a Workflow 07 failure or warning needs an entry.

## Step 3: Read the affected files

For every file:line in the findings, read around that line (`offset` / `limit`) so the report shows the user's actual code, never a generic example; read the whole file only when the change depends on more of it. When a pattern has many sites, quote a few representative ones in the block and list the rest in Affected files. When the quoted lines hold a secret value (a key, token or password, anything read from `ENV` or from a secrets or credentials file), keep the key name and replace the value with `<redacted>`; the report may be committed or shared.

## Step 4: Load the template

Read `templates/upgrade-report-template.md`. It is the shape of the report; this workflow does not restate it.

## Step 5: Fill the template

| Template section | Filled from |
|------------------|-------------|
| Header, Executive Summary, Baseline, Patterns checked | Step 1 counts (pattern counts from the JSON `summary`, never recounted); `{TREE_CHANGES}` from Workflow 04; `{ONE_PARAGRAPH_SUMMARY}` written last, once the buckets are known |
| What Was Checked (four subsections) | Workflow 02 inventory, the pattern scan (one `{PATTERN_SCAN_ROWS}` row per `found` entry, then the `unscanned` and `suppressed` lists), Workflow 06 buckets and check used, Workflow 07 output block. Evidence, not a second to-do list: anything actionable from them is also a Fix Before Bump entry |
| 🛑 Fix Before Bump | Workflow 05 `found` entries with `bucket: "fix_before_bump"` (`breaking` + `deprecation`), one block each: `{COUNT}` is the number of `sites` kept after the false-positive review, `{FILE_LIST}` lists them as `file:line` (`file:start-end` for a site that spans lines; for a `path_only` entry, the path, with no line), `{EXPLANATION}` comes from the version guide entry, falling back to the JSON `explanation`. An entry with `prereqs:` whose floor the app's `Gemfile.lock` does not meet gets a gem-bump entry placed before it, per Workflow 05 Step 1; Workflow 02 entries deferred to the bump (only those); Workflow 06 required bumps and blockers; Workflow 07 boot bumps, suite failures and every deprecation warning {TO} emitted. One block per entry, `{HOW_FOUND}` says which. HIGH → MEDIUM → LOW. When the cause is an absent line (no `load_defaults` at all), say so in Affected files instead of inventing a file:line |
| 📅 Fix When Ready | Workflow 05 `found` entries with `bucket: "fix_when_ready"` (`migration` + `optional`), same block shape, plus anything optional found by hand along the way (a Gemfile line the target declares itself, a config key with a better default) with `{HOW_FOUND}` saying so |
| Plan | fixed sections; `{BREAKING_CHANGE_TASKS}` is one checkbox per 🛑 entry. The plan never names workflows or steps: the reader does not have this skill's files |
| Testing Checklist | `{MANUAL_CHECKS}` tailored to the app's routes, mailers and jobs; drop what the app does not have |
| Everything else | as written in the template |

Dual-boot rule for the "Change (after)" block: most fixes are direct rewrites because the new API exists on both sides; write the new form once and leave `{DUAL_BOOT_NOTE}` empty. Use the two-sided note, with a `NextRails.next?` branch, only when the new API does not exist on {FROM}, and the removed-setter note when the current-version fix raises on {TO} (Workflow 02 Step 4 defers those to the pin change). Never `respond_to?`. This is the same rule as `workflows/10-implement-and-upgrade-workflow.md` Step 3 and the dual-boot skill.

## Step 6: Add custom code warnings

For each finding, check whether the app has code that interacts with the change: initializers touching the affected area, monkey patches of the affected classes, non-standard configuration, third-party gem integrations. Write the warning only when you found something, naming the file and what it does:

```markdown
⚠️ Custom code: `config/initializers/custom_loader.rb` registers its own autoload paths; Zeitwerk will read them differently. Review and test.
```

## Step 7: Replace every placeholder

| Placeholder | Source | Example |
|-------------|--------|---------|
| `{FROM}` / `{TO}` | minor versions | `7.0` / `7.1` |
| `{FROM_FULL}` / `{TO_FULL}` | exact versions | `7.0.10` / `7.1.6` |
| `{TO_UNDERSCORE}` | target minor with underscore, for the release-notes URL | `7_1` |
| `{DATE}` | today | `September 21, 2026` |
| `{PROJECT_NAME}` | app directory or `config/application.rb` module | `rubymem` |
| counts | Step 1 | numbers, never estimates |
| `{HOW_FOUND}` | how the entry was found, in the reader's words | `pattern catalog`, `warning at boot under Gemfile.next`, `manual review of the 7.1 source` |
| `{ONE_PARAGRAPH_SUMMARY}` | three or four plain sentences for someone who reads nothing else | see template comment |
| `{TREE_CHANGES}` | Workflow 04's edits, committed or not | `Gemfile: next_rails and if next? branch; both lockfiles re-resolved. Uncommitted.` |
| `{GEM_BLOCKER_COUNT}` / `{GEM_BLOCKER_LIST}` | Workflow 06 | `0` / `none` |
| `{TARGET_DEP_COUNT}` | distinct `DEPRECATION WARNING` lines from the `Gemfile.next` boot and suite | `2` |
| `{PATTERNS_CHECKED}` / `{PATTERNS_FIRED}` | JSON `summary.patterns_checked` / `summary.patterns_fired` | `23` / `10` |
| `{PATTERN_SCAN_ROWS}` | one row per `found` entry: name, kind, priority, sites kept (and dropped as false positives, when any), distinct files (`path` for a `path_only` entry) | `\| default_scope in models \| breaking \| HIGH \| 5 \| 5 \|` |
| `{PATTERNS_NOT_SCANNED}` / `{PATTERNS_ALL_SUPPRESSED}` | JSON `summary.unscanned` / `summary.suppressed`, as pattern names with what was done about each, or `none` | `CACHE_DIGESTS_BACKPORT (no Gemfile.lock; checked by hand, absent)` |
| `{MANUAL_CHECKS}` | the app's own features, from routes, mailers, jobs | `sign in, advisory search, RSS feed` |

No effort or risk estimates: they are subjective and the repo does not publish them (see `CLAUDE.md`, version guides rule).

## Step 8: Quality check

- [ ] Every placeholder replaced; no `{PLACEHOLDER}` token left
- [ ] Every 🛑 and 📅 entry traces to a Step 1 input with a real file:line
- [ ] Every `status: "found"` entry in `tmp/pattern-scan.json` is a 🛑 or 📅 block, unless every one of its sites was dropped as a false positive, in which case its Detection Patterns row says so; `{PATTERNS_CHECKED}` / `{PATTERNS_FIRED}` match the `summary`
- [ ] Code examples are the user's code, with secret values redacted
- [ ] Bucket membership follows `kind`, order inside a bucket follows `priority`
- [ ] Sections for skipped workflows say "not run" and why, rather than guessing
- [ ] Plan mentions `Gemfile.next`, never `bundle update rails`; `load_defaults` only in its own section after the bump
- [ ] No workflow number, step number or skill file path in the report body; the reader does not have this skill

## Step 9: Deliver

Present the report and state that the app:update preview (Workflow 09) follows. Do not offer to implement here: that offer belongs to `workflows/10-implement-and-upgrade-workflow.md` Step 1, after both deliverables are on the table.

---

## Report quality standards

**Code examples must be real.** Bad: `config.some_setting = true`. Good: the line from `config/environments/production.rb:42`.

**Warnings must be specific.** Bad: "you might have custom code". Good: "`config/initializers/sprockets.rb` configures the asset pipeline and needs migration to Propshaft".

**Nothing invented.** A section whose source workflow did not run says so. A count is a count.

---

**Related files:**
- Template: `templates/upgrade-report-template.md`
- Version guides: `version-guides/upgrade-{FROM}-to-{TO}.md`
- Testing checklist: `references/testing-checklist-reference.md`

---

## Self-review checklist

Before delivering, verify:

- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] Used ACTUAL findings from direct detection (not generic examples)
- [ ] Findings grouped into the two buckets — fix-before-bump (`kind: breaking` and `kind: deprecation`) and fix-when-ready (`kind: migration` and `kind: optional`) — with real file:line references
- [ ] Custom code warnings based on actual detected issues
- [ ] Code examples use user's actual code from affected files
- [ ] Next steps clearly outlined
- [ ] Stated that the app:update preview follows; no implementation offer yet
