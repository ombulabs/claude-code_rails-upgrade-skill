# Deprecation Resolution Workflow (Step 3)

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

Owns the *procedure* for Core Workflow Step 3. Resolve the current-Rails deprecation backlog before introducing the next Rails version, because current-version deprecations are the primary signal for what breaks next version.

**See also:**
- `references/deprecation-resolution/deprecation-warnings.md`, where warnings surface and Rails config options
- `references/deprecation-resolution/deprecation-strategies.md`, fix strategies (regex / synvert / `NextRails.next?` / gem upgrade)

---

## Preconditions

- Step 1 (Run Test Suite) is complete. Suite is green on the current Rails.
- A baseline deprecation list was captured during Step 1.
- Test env is configured to surface warnings (`:stderr` or `:log`), **not** `:silence`, and **not** `:raise` yet. `:raise` halts the suite on the first warning and hides the rest of the list.

If the baseline list is missing or the suite was silencing deprecations, start at step 1 below; otherwise jump to step 2.

---

## Procedure

### 1. Unsilence and recapture (if needed)

If `config.active_support.deprecation = :silence` is set anywhere, or the Step 1 log has no `DEPRECATION WARNING` lines and you suspect it should, reconfigure:

```ruby
# config/environments/test.rb
config.active_support.deprecation = :stderr  # or :log
```

Rerun the suite and capture output:

```bash
bundle exec rspec 2>&1 | tee test_output.log
# or: bundle exec rails test 2>&1 | tee test_output.log
```

### 2. Collect and dedupe

```bash
grep "DEPRECATION WARNING" test_output.log | sort -u > deprecations.txt
wc -l deprecations.txt
```

Also check `log/test.log` if the suite writes deprecations there instead of stdout.

### 3. Group by root cause

Many unique warning messages share a fix. Group the list:

- By method name (`update_attributes`, `before_filter`, `render :text`)
- By Rails subsystem (ActiveRecord, ActionController, ActiveSupport)
- Count occurrences per group, some gems or helpers emit the same warning from one callsite per test case

Output: a prioritized list of *root causes*, not raw warning lines.

### 4. Prioritize

Order by, in this sequence:

1. **Blocks next-version boot** first. If a warning corresponds to an API *removed* on the target Rails, resolving it is load-bearing for Step 5 dual-boot.
2. **Frequency**. High-count groups fix large swaths of the list with one change.
3. **Ease**. Batch mechanical renames before AST refactors.

### 5. Resolve each root cause

Loop:

1. Pick the top group.
2. Read `references/deprecation-resolution/deprecation-strategies.md`, pick the smallest tool that fits (strategy-selection table).
3. **Prefer a backward-compatible fix** over `NextRails.next?`. Use `NextRails.next?` only when no shared call form exists (rationale in the strategies file).
4. Apply the fix.
5. Run the focused subset of the suite for the touched layer (e.g., `bundle exec rspec spec/models`), then a full run before moving on if the change is broad.
6. Commit per root cause. Small commits make bisect cheap if something breaks later.

For gem-origin warnings, follow the gem path in the strategies file, do not paper over with `NextRails.next?` in app code.

### 6. Gate

Rerun the full suite (use the same `tee test_output.log` pattern as step 1 so the artefact is the single source of truth) and recapture:

```bash
bundle exec rspec 2>&1 | tee test_output.log
grep "DEPRECATION WARNING" test_output.log | sort -u
```

**Exit criteria:** the list is empty, or down to known, justified exceptions. Document each remaining exception inline (comment on the callsite or a note in the upgrade report) with:
- Why it is being deferred
- What would unblock fixing it (e.g., "waiting on gem X v2.0")

### 7. Lock in (Rails 6.1+)

For each resolved pattern, add it to `disallowed_warnings` so reintroduction fails tests:

```ruby
# config/environments/test.rb

# `disallowed_behavior` = [:raise] only raises on patterns in
# `disallowed_warnings`; other (unknown) deprecations still log per the
# global `config.active_support.deprecation` setting. Pairing the two:
# known patterns are locked; everything else is discovered via the
# global setting flipped to :raise below.
ActiveSupport::Deprecation.disallowed_behavior = [:raise]
ActiveSupport::Deprecation.disallowed_warnings += [
  /update_attributes/,
  "before_filter",
]
```

For Rails < 6.1, use a custom Rubocop cop instead (example in `deprecation-strategies.md`).

Once the backlog is zero and `disallowed_warnings` is wired up, flip test env to `:raise`:

```ruby
config.active_support.deprecation = :raise
```

Any new deprecation now halts CI.

### 8. Hand-off

Step 3 is done when:

- [ ] Current-Rails deprecation list is empty or explicit exceptions documented
- [ ] Resolved patterns locked via `disallowed_warnings` or custom cops
- [ ] Test env set to `:raise` (or equivalent regression gate)
- [ ] Changes committed and deployable on the current Rails (no `NextRails.next?` conditionals introduced unless justified)

Proceed to Step 4 (Review Ruby Compatibility).

---

## Why this order

Running the resolution loop before dual-boot (Step 5) means:

- The diff at version-bump time is smaller (fewer `NextRails.next?` conditionals to collapse in Step 9).
- Fixes ship on the current Rails independently, reducing risk and allowing partial rollouts.
- The next-version suite surfaces genuinely new breakage, not pre-existing debt masquerading as upgrade work.
