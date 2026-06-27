# No-Test-Suite Smoke Workflow

**Purpose:** Provide a concrete baseline check when a Rails app has no RSpec or Minitest suite.

**When to use:** Step 1 of the Rails upgrade workflow, only after test-suite detection finds no runnable `spec/` or `test/` suite.

This workflow is not a replacement for adding tests. It is a minimum boot and routing baseline so the upgrade report can say exactly what was checked before proceeding.

---

## Step 1: Confirm There Is No Runnable Suite

Check for actual test **files**, not just gem presence. `minitest` ships with every Rails app (it is a transitive dependency of `activesupport` in virtually every `Gemfile.lock`), so a gem match alone does not mean a runnable suite exists. Relying on it sends abandoned-test-setup apps back to `test-suite-verification-workflow.md`, which finds nothing to run and bounces them right back here, an infinite loop.

```bash
# Test file presence (the deciding signal)
test -d spec && find spec -name "*_spec.rb" | grep -q .
test -d test && find test -name "*_test.rb" | grep -q .

# Gemfile only (never Gemfile.lock), explicit test gems only
grep -E "rspec-rails|minitest-rails" Gemfile
```

Treat the app as having **no runnable suite** unless at least one test file is found. If test files do exist, return to `test-suite-verification-workflow.md` and run the real suite. Use this fallback only when no runnable suite exists.

---

## Step 2: Run Rails Boot Checks

Start with the cheapest command that loads the Rails environment:

```bash
bundle exec rails runner "puts Rails.version"
```

If the app has multiple environments or credentials constraints, also check test-mode boot:

```bash
RAILS_ENV=test bundle exec rails runner "puts Rails.env"
```

Record PASS or FAIL and the exact error. A boot failure blocks the upgrade until the user decides whether to fix the baseline first.

---

## Step 3: Check Routes And Migrations

These commands catch common baseline failures without needing a test suite:

```bash
bundle exec rails routes > tmp/rails-routes.txt 2>&1
bundle exec rails db:migrate:status
```

Redirect both stdout and stderr (`2>&1`): routing errors such as a bad constant in `routes.rb` print to stderr, and dropping them lets the command look like it succeeded with an empty output file. Write to the app's own `tmp/` directory rather than `/tmp`, which can be read-only or sandboxed in CI, Docker, and macOS App Sandbox contexts and would fail the check for the wrong reason.

If `db:migrate:status` cannot run because the database is unavailable, report it as "not verified" rather than fabricating a pass. Do not create or migrate a database unless the user asked for that setup.

---

## Step 4: Run Asset Or Build Checks When Available

Only run commands that already exist in the app:

```bash
bundle exec rails assets:precompile
bin/vite build
yarn build
npm run build
```

Pick the app's actual build path from its files (`package.json`, `vite.config.*`, `app/assets`, `config/webpacker.yml`, or Propshaft/Sprockets config). If no asset build exists, record "not applicable."

---

## Step 5: Optional Manual Smoke URLs

If the app can boot locally, start the server in the background, capture its PID, and **always shut it down afterward** so an orphaned server does not hold port 3000 and cause conflicts in later steps:

```bash
bundle exec rails server &
SERVER_PID=$!
sleep 5  # wait for boot

# Check only safe, read-only endpoints, for example:
curl -I http://localhost:3000/
curl -I http://localhost:3000/users/sign_in

kill $SERVER_PID 2>/dev/null
```

Do not submit forms, mutate data, or hit admin/customer actions as part of this fallback.

---

## Output Format

```markdown
## No-Test-Suite Smoke Baseline

**Status:** PASS / FAIL / PARTIAL
**Reason this fallback ran:** No runnable RSpec or Minitest suite was detected.

| Check | Command | Result |
|---|---|---|
| Rails boot | `bundle exec rails runner "puts Rails.version"` | PASS |
| Test env boot | `RAILS_ENV=test bundle exec rails runner "puts Rails.env"` | PASS |
| Routes load | `bundle exec rails routes` | PASS |
| Migration status | `bundle exec rails db:migrate:status` | NOT VERIFIED - database unavailable |
| Asset/build check | `<actual command>` | PASS / NOT APPLICABLE |

**Upgrade risk:** High. This app has no automated suite. Add focused tests before or during the first upgrade hop, and treat every generated change as requiring manual verification.
```

---

## Stop Conditions

Stop and report instead of proceeding when:

- Rails cannot boot in the current environment.
- Routes cannot load.
- A required database or credential is missing and the user has not authorized setup.

If the fallback passes, continue with the upgrade workflow, but mark baseline confidence as `partial` and keep recommending real test coverage.
