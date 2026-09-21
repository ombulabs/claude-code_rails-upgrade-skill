# Workflow 08: Generate Upgrade Report

**Purpose:** Fill `templates/upgrade-report-template.md` with what Workflows 00 to 07 produced, so the user gets one document with every finding in its bucket, the user's own code, and a migration plan that matches the dual-boot flow the skill follows.

**When to use:** After Workflow 07. Deliverable 1 of two; the app:update preview is Workflow 09.

---

## Inputs

- Detection findings with `kind`, `priority` and file:line (from Workflow 05)
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
| Workflow 05 | findings with `kind`, `priority`, file:line, already in the two buckets |
| Workflow 06 | gem buckets: required bumps, blockers, already compatible; which check ran |
| Workflow 07 | boot smoke block, gem bumps found at boot, suite result under `Gemfile.next` and its failures, and every `DEPRECATION WARNING` line {TO} emitted at boot or during the suite |
| Workflow 04 | what changed in the working tree (Gemfile, lockfiles), committed or not |

Everything in the report comes from these. If a run skipped a workflow (request shape, blocked step), the corresponding section says so instead of being invented.

## Step 2: Load the version guide

Read `version-guides/upgrade-{FROM}-to-{TO}.md`. For each finding take the entry's "What Changed" text and its BEFORE / AFTER fix. The guide's Common Issues section maps a test failure or a warning text back to an entry by symptom.

## Step 3: Read the affected files

For every file:line in the findings, read the file so the report shows the user's actual code, never a generic example. When the quoted lines hold a secret value (a key, token or password, anything read from `ENV` or from a secrets or credentials file), keep the key name and replace the value with `<redacted>`; the report may be committed or shared.

## Step 4: Load the template

Read `templates/upgrade-report-template.md`. It is the shape of the report; this workflow does not restate it.

## Step 5: Fill the template

| Template section | Filled from |
|------------------|-------------|
| Header, Executive Summary, Baseline, Patterns checked | Step 1 counts; `{TREE_CHANGES}` from Workflow 04; `{ONE_PARAGRAPH_SUMMARY}` written last, once the buckets are known |
| 🛑 Fix Before Bump | Workflow 05 `breaking` + `deprecation` findings; Workflow 02 entries deferred to the bump (only those); Workflow 06 required bumps and blockers; Workflow 07 boot bumps, suite failures and every deprecation warning {TO} emitted. One block per entry, `{HOW_FOUND}` says which. HIGH → MEDIUM → LOW. When the cause is an absent line (no `load_defaults` at all), say so in Affected files instead of inventing a file:line |
| 📅 Fix When Ready | Workflow 05 `migration` + `optional` findings, plus anything optional found by hand along the way (a Gemfile line the target declares itself, a config key with a better default) with `{HOW_FOUND}` saying so |
| Deprecation Warnings on {FROM} | Workflow 02 inventory, one row per distinct warning, status as the template's comment lists |
| Gem Compatibility | Workflow 06 buckets and the check that produced them. With no bumps and no blockers: the one-line summary, no table |
| Boot and Tests Under `Gemfile.next` | Workflow 07 output block verbatim, plus the count of {TO} deprecation warnings |
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
| `{PATTERNS_CHECKED}` / `{PATTERNS_FIRED}` | Workflow 05 | `10` / `1` |
| `{MANUAL_CHECKS}` | the app's own features, from routes, mailers, jobs | `sign in, advisory search, RSS feed` |

No effort or risk estimates: they are subjective and the repo does not publish them (see `CLAUDE.md`, version guides rule).

## Step 8: Quality check

- [ ] Every placeholder replaced; no `{PLACEHOLDER}` token left
- [ ] Every 🛑 and 📅 entry traces to a Step 1 input with a real file:line
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
