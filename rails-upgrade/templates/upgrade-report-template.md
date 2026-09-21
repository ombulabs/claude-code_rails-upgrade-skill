# Rails {FROM} → {TO} Upgrade Report

**Generated:** {DATE}
**Project:** {PROJECT_NAME}
**Current Version:** {FROM_FULL} (latest patch of the {FROM} series: {YES_OR_LATEST_PATCH})
**Target Version:** {TO_FULL}
**Dual-boot:** `Gemfile.next` resolves {TO_FULL}; default side stays {FROM_FULL} until Phase 3

---

## Executive Summary

| | Count |
|--|-------|
| 🛑 Fix before bump (`kind: breaking` + `kind: deprecation`) | {FIX_BEFORE_COUNT} |
| 📅 Fix when ready (`kind: migration` + `kind: optional`) | {FIX_WHEN_READY_COUNT} |
| Deprecation warnings on {FROM}: fixed / deferred | {DEP_FIXED} / {DEP_DEFERRED} |
| Gems: required bumps / blockers / already compatible | {GEM_BUMPS} / {GEM_BLOCKERS} / {GEM_OK} |
| Boot under `Gemfile.next` | {BOOT_RESULT} |
| Models suite under `Gemfile.next` | {MODELS_RESULT} |

**Baseline:** {TEST_COUNT} tests, {ASSERTION_COUNT} assertions, {FAILURE_COUNT} failures on {FROM_FULL} (Workflow 01).

---

## 🛑 Fix Before Bump ({FIX_BEFORE_COUNT})

`kind: breaking` raises or fails to boot on {TO}; `kind: deprecation` warns on {FROM} about something {TO} changes. Both land before the default side moves to {TO}. Ordered HIGH → MEDIUM → LOW. Includes the deprecation warnings deferred in Workflow 02, the gem bumps from Workflows 06 and 07, and every models-suite failure from Workflow 07.

<!-- Repeat this block for each finding -->

### {ISSUE_NAME}

**Kind:** `{KIND}` · **Priority:** {PRIORITY} · **Found:** {COUNT} occurrence(s) · **Source:** {SOURCE_WORKFLOW}

**Affected files:**
{FILE_LIST}

**What changes in Rails {TO}:** {EXPLANATION}

**Your code (before):**
```ruby
# {FILE_PATH}:{LINE_NUMBER}
{ACTUAL_CODE}
```

**Change (after):**
```ruby
{FIXED_CODE}
```

{DUAL_BOOT_NOTE}
<!-- DUAL_BOOT_NOTE is one of:
     - nothing, when the new form works on both sides (the usual case: direct rewrite)
     - "Two-sided: the new API does not exist on {FROM}. Branch with `NextRails.next?` (target form on top, current form below) and drop the branch at cleanup."
     - "Setter removed on {TO}: keep it under `unless NextRails.next?` and delete it at cleanup." -->

{CUSTOM_CODE_WARNING}
<!-- "⚠️ Custom code: <file> <what it does> <why it interacts with this change>", only when detected -->

<!-- End repeat block -->

---

## 📅 Fix When Ready ({FIX_WHEN_READY_COUNT})

`kind: migration` and `kind: optional`: silent and working on {TO}. Recommended, not tied to the bump. Same block shape as above, `{SOURCE_WORKFLOW}` is Workflow 05.

{FIX_WHEN_READY_BLOCKS}

---

## Deprecation Warnings on {FROM} (Workflow 02)

| Warning | Count | Status | Note |
|---------|-------|--------|------|
{DEPRECATION_INVENTORY_ROWS}

Fixed entries are already in the baseline above. Deferred entries appear in Fix Before Bump with their reason.

---

## Gem Compatibility (Workflow 06)

Check used: {GEM_CHECK_USED} (`bundle_report compatibility` / railsbump / read-only gemspec check).

| Gem | Locked | Needed for {TO} | Bucket |
|-----|--------|-----------------|--------|
{GEM_ROWS}

Blockers (no released version supports {TO}): {GEM_BLOCKERS}. Playbook: `references/gem-compatibility-reference.md`.

---

## Boot and Models Suite Under `Gemfile.next` (Workflow 07)

```
{BOOT_SMOKE_BLOCK}
```

Models suite: {MODELS_RESULT}. Failures, if any, are Fix Before Bump entries above.

---

## Migration Plan

Workflows 00 to 09 are done; this plan is what remains. Each phase is one PR.

### Phase 1: Fix before bump (Workflow 10, Steps 1 to 3)
- [ ] Every 🛑 entry above, on both sides of the dual-boot. Direct rewrite unless the entry says two-sided
- [ ] Suite green on `Gemfile` and on `Gemfile.next`
{BREAKING_CHANGE_TASKS}

### Phase 2: Configuration (Workflow 09 output)
- [ ] Apply the app:update preview (deliverable 2) file by file; do not run `rails app:update` blind
- [ ] Do not touch `config.load_defaults` in this hop (Phase 5)

### Phase 3: Bump the default side (Workflow 10, Steps 4 to 7)
- [ ] `Gemfile`: the `if next?` branch's {TO} pin becomes the default; keep the `else` branch until cleanup
- [ ] `bundle install` for both lockfiles; suite green on both
- [ ] CI config matches the upgraded Gemfile (Workflow 11): Ruby version, Rails matrix, service versions
- [ ] Deploy and verify

### Phase 4: Fix when ready
- [ ] The 📅 entries, at the team's pace, one PR each

### Phase 5: Align `load_defaults` (Workflow 12)
- [ ] After the bump ships, delegated to the rails-load-defaults skill, one config at a time

### Phase 6: Cleanup (Workflow 13, user-triggered)
- [ ] When the team is ready and not heading straight into the next hop: remove `NextRails.next?` branches and `Gemfile.next` via the upgrade-cleanup plugin

---

## Testing Checklist

Run after Phase 1 and again after Phase 3. Full list: `references/testing-checklist-reference.md`.

- [ ] Unit, controller, integration and system tests green on both Gemfiles
- [ ] Authentication, core CRUD, file uploads, background jobs, email delivery, API endpoints exercised by hand
- [ ] Boot time and request times comparable to {FROM}; no new N+1

---

## Rollback Plan

Dual-boot is the rollback: the {FROM} side stays intact until cleanup.

- Before Phase 3: nothing to roll back; the default side never moved.
- After Phase 3: revert the Gemfile default back to {FROM_FULL}, `bundle install`, redeploy. Roll back migrations only if {TO} added any (`rails db:rollback STEP=N`).
- Cache: `rails tmp:clear` and `rails cache:clear` if `cache_format_version` changed.
- Database: restore the Phase 1 backup only if data changed shape.

---

## Post-Upgrade Tasks

- [ ] CI matrix reviewed (Workflow 11 report attached to the PR)
- [ ] Deployment scripts and Dockerfile on the new Ruby / Rails pins
- [ ] Team notified; error rates and performance watched after deploy

---

## Resources

- [Rails {TO} Release Notes](https://guides.rubyonrails.org/{TO_UNDERSCORE}_release_notes.html)
- [Rails Upgrade Guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [FastRuby.io Rails Upgrade Blog](https://www.fastruby.io/blog)
- Version guide used: `version-guides/upgrade-{FROM}-to-{TO}.md`

---

## Next Steps

1. Review this report; the app:update preview is deliverable 2
2. Start Phase 1 with the HIGH entries
3. Run both suites after each change

---

**Report generated by Rails Upgrade Assistant**
