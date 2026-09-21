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
| Workflow 02 | deprecation inventory: fixed entries, deferred entries with reason |
| Workflow 05 | findings with `kind`, `priority`, file:line, already in the two buckets |
| Workflow 06 | gem buckets: required bumps, blockers, already compatible; which check ran |
| Workflow 07 | boot smoke block, gem bumps found at boot, models suite result and failures |

Everything in the report comes from these. If a run skipped a workflow (request shape, blocked step), the corresponding section says so instead of being invented.

## Step 2: Load the version guide

Read `version-guides/upgrade-{FROM}-to-{TO}.md`. For each finding take the entry's "What Changed" text and its BEFORE / AFTER fix; the `Common Issues — Quick Reference` table maps models-suite failures back to an entry by symptom.

## Step 3: Read the affected files

For every file:line in the findings, read the file so the report shows the user's actual code, never a generic example.

## Step 4: Load the template

Read `templates/upgrade-report-template.md`. It is the shape of the report; this workflow does not restate it.

## Step 5: Fill the template

| Template section | Filled from |
|------------------|-------------|
| Header, Executive Summary, Baseline | Step 1 counts |
| 🛑 Fix Before Bump | Workflow 05 `breaking` + `deprecation` findings, plus Workflow 02 deferred entries, plus Workflow 06 required bumps and blockers, plus Workflow 07 boot bumps and models-suite failures. One block per entry, `{SOURCE_WORKFLOW}` names where it came from. HIGH → MEDIUM → LOW |
| 📅 Fix When Ready | Workflow 05 `migration` + `optional` findings |
| Deprecation Warnings on {FROM} | Workflow 02 inventory, one row per distinct warning |
| Gem Compatibility | Workflow 06 buckets and the check that produced them |
| Boot and Models Suite | Workflow 07 output block verbatim |
| Migration Plan | fixed phases; `{BREAKING_CHANGE_TASKS}` is one checkbox per 🛑 entry |
| Everything else | as written in the template |

Dual-boot rule for the "Change (after)" block: most fixes are direct rewrites because the new API exists on both sides; write the new form once and leave `{DUAL_BOOT_NOTE}` empty. Use the two-sided note, with a `NextRails.next?` branch, only when the new API does not exist on {FROM}, and the removed-setter note when the current-version fix raises on {TO}. Never `respond_to?`. This is the same rule as Workflow 10 Step 3 and the dual-boot skill.

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
| `{SOURCE_WORKFLOW}` | which workflow produced the entry | `Workflow 05`, `Workflow 07 models suite` |

No effort or risk estimates: they are subjective and the repo does not publish them (see `CLAUDE.md`, version guides rule).

## Step 8: Quality check

- [ ] Every placeholder replaced; no `{` left
- [ ] Every 🛑 and 📅 entry traces to a Step 1 input with a real file:line
- [ ] Code examples are the user's code
- [ ] Bucket membership follows `kind`, order inside a bucket follows `priority`
- [ ] Sections for skipped workflows say "not run" and why, rather than guessing
- [ ] Migration plan mentions `Gemfile.next`, never `bundle update rails`; `load_defaults` only in Phase 5

## Step 9: Deliver

Present the report, then state that the app:update preview (Workflow 09) follows. Offer to start Phase 1 unless the user already said they will implement themselves.

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
- [ ] Offered to help implement changes (skip if the user already said they will implement themselves)
