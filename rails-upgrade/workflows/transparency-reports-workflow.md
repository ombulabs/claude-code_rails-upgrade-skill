# Transparency Reports Workflow

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

Every Core Workflow step writes a short progress report to disk. Reports give the user a durable, reviewable trail of what Claude did at each step, what it found, and what the user needs to decide. They are always-on and cheap to remove later (two edits: delete this file, delete the pointer in `SKILL.md`).

---

## Folder layout

```
upgrade_reports/
  <current>-to-<target>/
    00-summary.md
    01-run-test-suite.md
    02-verify-latest-patch.md
    03-resolve-deprecations.md
    04-review-ruby-compatibility.md
    05-set-up-dual-boot.md
    06-run-breaking-changes-detection.md
    07-fix-broken-build.md
    08-smoke-test.md
    09-remove-dual-boot.md
    10-align-load-defaults.md     # only if Step 10 is run
```

- One subfolder per hop. A multi-hop upgrade (5.2 → 6.0 → 6.1) creates two subfolders: `5.2-to-6.0/` and `6.0-to-6.1/`.
- Filenames: `NN-<step-slug>.md`, zero-padded NN matches the Core Workflow step number.
- `00-summary.md` is written last (or updated after each step) and links every per-step report.

Suggest the user add `upgrade_reports/` to `.gitignore` on first invocation. Reports are intermediate artefacts, not source of truth for the repo.

---

## When to write

Write the report **after** the step's actions complete, not before. Write even if the step was skipped (e.g., Step 2 finds the app already on the latest patch), with status set accordingly. Update `00-summary.md` at the end of each step so the summary always reflects current state.

---

## Per-step report template

```markdown
# Step NN: <Step Name>

**Hop:** <current> → <target>
**Status:** complete | skipped | blocked
**Started:** <ISO 8601 datetime>
**Finished:** <ISO 8601 datetime>

## What ran

<Commands executed, tools invoked, files touched. File:line references
where relevant.>

## Findings

<What Claude discovered. For detection steps, the raw finding list. For
fix steps, the diff summary.>

## Decisions

<Choices Claude made and why. Especially when multiple strategies were
available (e.g., regex vs synvert for a deprecation).>

## Blockers / exceptions

<Anything deferred, skipped, or requiring human input. Empty if none.>

## Next

<The next step, and any prerequisites the user must handle before it
can start.>
```

Keep reports short. Link to source files or existing artefacts rather than duplicating content. A report for a clean Step 1 run is five lines; a report for Step 6 on a large app may be a page.

---

## `00-summary.md` template

```markdown
# Upgrade Summary: <current> → <target>

**Started:** <ISO 8601>
**Current status:** Step N complete | in progress at Step N | blocked at Step N

| # | Step | Status | Report |
|---|------|--------|--------|
| 1 | Run Test Suite | complete | [01-run-test-suite.md](01-run-test-suite.md) |
| 2 | Verify Latest Patch Version | complete | [02-verify-latest-patch.md](02-verify-latest-patch.md) |
| 3 | Resolve Deprecation Warnings | complete | [03-resolve-deprecations.md](03-resolve-deprecations.md) |
| 4 | Review Ruby Compatibility | complete | [04-review-ruby-compatibility.md](04-review-ruby-compatibility.md) |
| 5 | Set Up Dual-Boot | complete | [05-set-up-dual-boot.md](05-set-up-dual-boot.md) |
| 6 | Run Breaking Changes Detection | complete | [06-run-breaking-changes-detection.md](06-run-breaking-changes-detection.md) |
| 7 | Fix Broken Build | in progress | [07-fix-broken-build.md](07-fix-broken-build.md) |
| 8 | Smoke Test | pending | (pending) |
| 9 | Remove Dual-Boot | pending | (pending) |
| 10 | Align load_defaults | optional | (pending) |

## Outstanding blockers

<Pulled from per-step report "Blockers / exceptions" sections. Empty if none.>

## Key decisions

<One line per major decision with pointer to the per-step report.>
```

---

## Rationale for always-on

No dev/prod toggle until real noise emerges. Reports are opt-out (via `.gitignore` + deletion), not opt-in. This keeps the workflow prescriptive and avoids a branching matrix inside each step ("write a report if...").

## Removal

If reports prove not worth keeping:

1. Delete `workflows/transparency-reports-workflow.md`.
2. Delete the pointer line under "Transparency" in `SKILL.md`.

No other step sections reference reports inline, so nothing else needs editing.
