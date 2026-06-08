# No-Test-Suite Smoke Workflow

**Purpose:** Provide a concrete baseline check when a Rails app has no RSpec or Minitest suite.

**When to use:** Step 1 of the Rails upgrade workflow, only after test-suite detection finds no runnable `spec/` or `test/` suite.

This workflow is not a replacement for adding tests. It is a minimum boot and routing baseline so the upgrade report can say exactly what was checked before proceeding.

---

## Step 1: Confirm There Is No Runnable Suite

Check both files and Gemfile entries before declaring "no tests":

```bash
test -d spec || test -d test
grep -E "rspec-rails|minitest|capybara|factory_bot_rails" Gemfile Gemfile.lock
```

If there are test directories or gems, return to `test-suite-verification-workflow.md` and run the real suite. Use this fallback only when no runnable suite exists.

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
bundle exec rails routes >/tmp/rails-routes.txt
bundle exec rails db:migrate:status
```

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

If the app can boot locally, collect the most important URLs from routes:

```bash
bundle exec rails server
```

Then manually or with curl check only safe read-only endpoints, for example:

```bash
curl -I http://localhost:3000/
curl -I http://localhost:3000/users/sign_in
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
- The app has a test suite but it fails to run.
- A required database or credential is missing and the user has not authorized setup.

If the fallback passes, continue with the upgrade workflow, but mark baseline confidence as `partial` and keep recommending real test coverage.
