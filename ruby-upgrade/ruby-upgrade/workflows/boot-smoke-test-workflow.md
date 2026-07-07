# Boot Smoke Test Workflow

**Purpose:** Catch gem-internal Ruby-version incompatibilities that a resolver-level check (`bundle install`, `bundle lock`) cannot see — a gem calling a removed API or using syntax the target Ruby no longer supports, despite an honest-looking `required_ruby_version`.

**When to use:** Step 5 of the Ruby upgrade workflow, immediately after bumping the Gemfile's `ruby` directive and re-locking (Step 4).

---

## Why a Resolver Check Isn't Enough

A gem's `required_ruby_version` is a claim, not a guarantee. `bundle install` succeeding means the *declared* constraints are satisfiable — it says nothing about whether the gem's actual code still runs. Confirmed real example: `aws-sdk-core` 2.3.23 declared no problematic Ruby floor and installed cleanly under Ruby 3.2, but called `Proc.new` relying on implicit block capture — a feature fully removed in Ruby 3.0 — and raised `ArgumentError` on the very first `require`. See `references/known-gotchas.md` for this and other confirmed examples.

## Step 1: Run a Command That Actually Boots the App

For a Rails app:

```bash
bundle exec rails runner "puts RUBY_VERSION"
```

For a non-Rails app, use its real entrypoint — whatever `require`s the bulk of the dependency tree in normal operation (a `bin/console`, the app's main executable, a Rake task that loads the full environment). A synthetic script that only requires a handful of gems misses anything loaded lazily by the app's actual boot path.

## Step 2: If It Fails, Read the Trace Directly

Unlike a Rails-version resolver conflict, there's no ambiguity to untangle here — the stack trace points straight at the `require` chain and the exact line that broke. Identify the gem from the trace's file path.

## Step 3: Check the Gem's CHANGELOG

Look for a release that drops the removed API. If found, bump the gem and re-run Step 1.

## Step 4: If No Fix Exists

Check for a maintained fork (see `references/known-gotchas.md` for the `paperclip` → `kt-paperclip` example) or evaluate whether the gem can be replaced or dropped.

## Step 5: Repeat Until Clean

Boot failures are often sequential, not simultaneous — fixing the first one can reveal a second gem with the same class of problem. Re-run Step 1 after every fix rather than assuming one fix means the whole tree is clear.

## Step 6: Run the Full Test Suite

Once the boot smoke test passes, run the full test suite (same command as `test-suite-verification-workflow.md`) — a clean boot does not guarantee every code path is exercised.

---

## Output Format

```
Boot smoke test (Step 5):

  - Command: bundle exec rails runner "puts RUBY_VERSION"
  - Result: PASS (after N fix-and-retry cycles) / FAIL

Fixes applied:
  - <gem> <old version> -> <new version>: <what broke, one line>
  - ...
```
