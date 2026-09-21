# Rails {FROM} → {TO} Upgrade Report

**Generated:** {DATE}
**Project:** {PROJECT_NAME}
**Current version:** {FROM_FULL}, latest patch of its series
**Target version:** {TO_FULL}
**Dual-boot:** `Gemfile.next` resolves {TO_FULL}; the default `Gemfile` stays on {FROM_FULL} until the pin changes (see the plan)

**Changes made while producing this report:** {TREE_CHANGES}
<!-- e.g. "Gemfile: next_rails gem and if next? branch added; Gemfile.lock and Gemfile.next.lock re-resolved. Uncommitted." or "none" -->

---

## Executive Summary

| | Count |
|--|-------|
| 🛑 Fix before bump | {FIX_BEFORE_COUNT} |
| 📅 Fix when ready | {FIX_WHEN_READY_COUNT} |
| Deprecation warnings on {FROM}: fixed / deferred | {DEP_FIXED} / {DEP_DEFERRED} |
| Deprecation warnings emitted by {TO} at boot or in the suite | {TARGET_DEP_COUNT} |
| Gems: required bumps / blockers / already compatible | {GEM_BUMPS} / {GEM_BLOCKER_COUNT} / {GEM_OK} |
| Boot under `Gemfile.next` | {BOOT_RESULT} |
| Test suite under `Gemfile.next` | {NEXT_SUITE_RESULT} |

**Baseline on {FROM_FULL}:** {TEST_COUNT} tests, {ASSERTION_COUNT} assertions, {FAILURE_COUNT} failures.
**Patterns checked:** {PATTERNS_CHECKED} for this hop; {PATTERNS_FIRED} matched.

---

## 🛑 Fix Before Bump ({FIX_BEFORE_COUNT})

Everything that raises, fails to boot, or warns on {TO} about behavior that changes there. All of it lands before the default `Gemfile` moves to {TO}. Ordered HIGH → MEDIUM → LOW. Sources: the pattern catalog, the deprecation warnings {TO} emitted at boot or in the suite, the gem bumps the boot check needed, the test failures under `Gemfile.next`, and the current-version fixes deferred because their setter is removed on {TO}.

<!-- Repeat this block for each finding -->

### {ISSUE_NAME}

**Kind:** `{KIND}` · **Priority:** {PRIORITY} · **Found:** {COUNT} occurrence(s) · **How found:** {HOW_FOUND}
<!-- HOW_FOUND: "pattern catalog", "warning at boot under Gemfile.next", "warning in the suite under Gemfile.next", "test failure under Gemfile.next", "gem compatibility check", "deferred from the current-version deprecation pass" -->

**Affected files:**
{FILE_LIST}
<!-- When the cause is an absent line (for example no config.load_defaults at all), write "no line sets this; the {FROM} default applies" and name the file where the line belongs -->

**What changes in Rails {TO}:** {EXPLANATION}

**Your code (before):**
```ruby
# {FILE_PATH}:{LINE_NUMBER}
{ACTUAL_CODE}
```
<!-- For an absent line: show the surrounding block and a comment "# nothing here sets <key>" -->

**Change (after):**
```ruby
{FIXED_CODE}
```

{DUAL_BOOT_NOTE}
<!-- DUAL_BOOT_NOTE is one of:
     - nothing, when the new form works on both Rails versions (the usual case: a direct rewrite)
     - "Two-sided: the new API does not exist on {FROM}. Branch with `NextRails.next?` (target form on top, current form below) and drop the branch at cleanup."
     - "Setter removed on {TO}: apply it as the default pin changes, not before." -->

{CUSTOM_CODE_WARNING}
<!-- "⚠️ Custom code: <file> <what it does> <why it interacts with this change>", only when detected -->

<!-- End repeat block -->

---

## 📅 Fix When Ready ({FIX_WHEN_READY_COUNT})

Silent and working on {TO}; recommended, not tied to the bump. Same block shape as above.

{FIX_WHEN_READY_BLOCKS}
<!-- When empty: "None. All {PATTERNS_CHECKED} patterns for this hop were searched." -->

---

## Deprecation Warnings on {FROM}

The warnings the current version emits, collected before any dual-boot work.

| Warning | Count | Status | Note |
|---------|-------|--------|------|
{DEPRECATION_INVENTORY_ROWS}
<!-- Status: fixed (already in the baseline above) / deferred to the bump (setter removed on {TO}; also listed in Fix Before Bump) / deferred to a later hop (about a version after {TO}) / gem-owned (belongs to the gem's own update) -->

---

## Gem Compatibility

Check used: {GEM_CHECK_USED}.
<!-- "next_rails bundle_report compatibility", "railsbump", or "not run: <reason>" -->

{GEM_SUMMARY}
<!-- When nothing changes: "All {GEM_OK} direct gems already declare support for {TO}." and no table.
     Otherwise the table below, one row per gem that needs a bump or has no compatible release. -->

| Gem | Locked | Needed for {TO} | Bucket |
|-----|--------|-----------------|--------|
{GEM_ROWS}

Blockers (no released version supports {TO}): {GEM_BLOCKER_LIST}.

---

## Boot and Tests Under `Gemfile.next`

```
{BOOT_SMOKE_BLOCK}
```

Suite under `Gemfile.next`: {NEXT_SUITE_RESULT}. Deprecation warnings {TO} emitted during boot or the suite: {TARGET_DEP_COUNT}; each one is a Fix Before Bump entry above. Test failures, if any, are Fix Before Bump entries too.

---

## Plan

The analysis is done; this is what remains, in order. How the work is split into branches and pull requests is the team's call.

### Fix before bump
- [ ] Every 🛑 entry above, on both sides of the dual-boot. Direct rewrite unless the entry says two-sided
- [ ] Suite green on `Gemfile` and on `Gemfile.next`
{BREAKING_CHANGE_TASKS}

### Bump the default pin
- [ ] Database backup taken and a restore tested
- [ ] `Gemfile`: change the `else` branch's pin to {TO_FULL} so both sides resolve {TO}; leave the `if next?` / `else` structure, `Gemfile.next` and `Gemfile.next.lock` in place until cleanup
- [ ] `bundle install` for both lockfiles; suite green on both
- [ ] Configuration: apply the app:update preview (deliverable 2) file by file on the {TO} side; do not run `rails app:update` blind. Keys that do not exist on {FROM} go under a `NextRails.next?` guard until cleanup
- [ ] Do not change `config.load_defaults` yet (see below)
- [ ] CI configuration matches the upgraded Gemfile: Ruby version, Rails matrix, service versions
- [ ] Deploy and verify

### Fix when ready
- [ ] The 📅 entries, at the team's pace

### Align `load_defaults`
- [ ] After the bump ships and is stable, move `config.load_defaults` to {TO} one setting at a time, running the suite between settings

### Cleanup
- [ ] When the team is ready and not heading straight into the next hop: remove the `NextRails.next?` branches, the `if next?` / `else` structure and `Gemfile.next`

---

## Testing Checklist

Run after the fix-before-bump work and again after the default pin changes. Tailor the manual list to this app's routes, mailers and jobs; drop what it does not have.

- [ ] Unit, controller, integration and system tests green on both Gemfiles
- [ ] {MANUAL_CHECKS}
- [ ] Boot time and request times comparable to {FROM}; no new N+1

---

## Rollback Plan

Dual-boot is the rollback: the {FROM} side stays intact until cleanup.

- Before the default pin changes: nothing to roll back; the default side never moved.
- After the default pin changes: set the `else` branch's pin back to {FROM_FULL}, `bundle install`, redeploy. Roll back migrations only if {TO} added any (`rails db:rollback STEP=N`).
- Cache: `bin/rails runner 'Rails.cache.clear'` and `rails tmp:clear` if the cache format version changed.
- Database: restore the backup taken before the pin change only if data changed shape.

---

## Post-Upgrade Tasks

- [ ] CI configuration reviewed and attached to the upgrade pull request
- [ ] Deployment scripts and Dockerfile on the new Ruby / Rails pins
- [ ] Team notified; error rates and performance watched after deploy

---

## Resources

- [Rails {TO} Release Notes](https://guides.rubyonrails.org/{TO_UNDERSCORE}_release_notes.html)
- [Rails Upgrade Guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [FastRuby.io Rails Upgrade Blog](https://www.fastruby.io/blog)

---

## Next Steps

1. Review this report; the app:update preview is deliverable 2
2. Start with the HIGH entries under Fix Before Bump
3. Run both suites after each change

---

**Report generated by Rails Upgrade Assistant**
