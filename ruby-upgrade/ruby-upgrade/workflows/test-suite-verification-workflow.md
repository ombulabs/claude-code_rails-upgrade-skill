# Test Suite Verification Workflow

**Purpose:** Establish a green baseline before touching anything Ruby-version-related.

**When to use:** Step 1 of the Ruby upgrade workflow, before Step 0's patch check even needs to matter in practice — no upgrade work should start against a red suite.

---

## Step 1: Detect the Test Framework

```bash
grep -E "^\s*gem\s+[\"']rspec" Gemfile
grep -E "^\s*gem\s+[\"']minitest" Gemfile
test -f .rspec
test -d spec
test -d test
```

An app can have both RSpec and Minitest present (e.g. a legacy Minitest suite alongside a newer RSpec one, mid-migration) — run both if both have actual test files, not just gem entries.

## Step 2: Confirm Runnable Test Files Exist

Gem presence alone is not proof of a runnable suite — `minitest` in particular ships as a transitive dependency of common libraries even when no test file exists.

```bash
test -d spec && find spec -name "*_spec.rb" | grep -q .
test -d test && find test -name "*_test.rb" | grep -q .
```

If neither finds a file, treat the app as having **no runnable suite** and go to `no-test-suite-smoke-workflow.md` instead of this workflow's remaining steps.

## Step 3: Run the Suite

```bash
bundle exec rspec
# or
bundle exec rails test
# or, for a non-Rails app:
bundle exec rake test
```

Capture: total examples/tests, passing, failing, pending/skipped, and the wall-clock time (useful later to sanity-check that a re-run after the version bump isn't drastically slower or faster in a way that suggests something didn't actually run).

## Step 4: Gate on the Result

- **All green:** record the baseline (test count, pass count) and proceed to Step 0 of `SKILL.md` (or Step 2 if Step 0 already passed).
- **Any failure:** STOP. Do not proceed with any upgrade work. Report the failing tests to the user and offer to help fix them first. A red baseline makes every later step's pass/fail signal meaningless — a test that fails after the Ruby bump might have already been failing before it, and there's no way to tell without a clean starting point.

## Step 5: Re-run at Every Later Gate

This same command is the gate at the end of Step 2 (after fixing deprecation warnings, before touching the Gemfile), after Step 4 (the actual version bump), and after Step 6 (applying boot-smoke-test findings). Re-run it exactly the same way each time so the results are comparable — don't switch from a full suite run to a subset partway through the upgrade.
