# No-Test-Suite Smoke Workflow

**Purpose:** Provide a concrete baseline check when an app has no RSpec or Minitest suite with actual test files.

**When to use:** Step 1 of the Ruby upgrade workflow, only after `test-suite-verification-workflow.md` finds no runnable suite.

This workflow is not a replacement for adding tests. It is a minimum load-and-boot baseline so the upgrade report can say exactly what was checked before proceeding, and so upgrade risk can be reported honestly as "partial confidence" rather than implying full test coverage exists.

---

## Step 1: Confirm There Is No Runnable Suite

Already established by `test-suite-verification-workflow.md` Step 2 before arriving here — don't re-derive it, but do sanity-check nothing changed (e.g. a test dir was added since).

## Step 2: Syntax-Check Every Ruby File

Cheapest possible check — catches nothing about semantics, but confirms every file at least parses under the *current* Ruby before you touch anything:

```bash
find . -name "*.rb" -not -path "./vendor/*" -not -path "./tmp/*" \
  -print0 | xargs -0 -n1 ruby -c
```

## Step 3: Boot the App

For a Rails app:

```bash
bundle exec rails runner "puts Rails.version"
RAILS_ENV=test bundle exec rails runner "puts Rails.env"
```

For a non-Rails app, use whatever its actual entrypoint is — a `bin/console`, a `require "./lib/app"` smoke script, a Rake task that loads the full environment. Pick the app's real boot path from its files rather than inventing one; a synthetic boot script that doesn't match how the app actually starts in production tells you little.

Record PASS or FAIL and the exact error. A boot failure blocks the upgrade until the user decides whether to fix the baseline first.

## Step 4: Run Build/Asset Steps When Available

Only run commands that already exist in the app — check `package.json`, `Rakefile`, `bin/` for what's real:

```bash
bundle exec rails assets:precompile
yarn build
npm run build
```

If none apply, record "not applicable."

## Step 5: Optional Manual Smoke

If the app can boot a server locally, start it, hit a couple of safe read-only endpoints, and shut it down:

```bash
bundle exec rails server &
SERVER_PID=$!
sleep 5
curl -I http://localhost:3000/
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
| Syntax check | `find . -name "*.rb" | xargs ruby -c` | PASS |
| App boot | `<actual boot command>` | PASS |
| Build/assets | `<actual command>` | PASS / NOT APPLICABLE |

**Upgrade risk:** High. This app has no automated suite. Add focused tests before or during the first upgrade hop, and treat every generated change as requiring manual verification.
```

---

## Stop Conditions

Stop and report instead of proceeding when:

- The app cannot boot in the current environment.
- A syntax check fails on a file that isn't already known-broken/unreachable dead code.

If the fallback passes, continue with the upgrade workflow, but mark baseline confidence as `partial` in the final report and keep recommending real test coverage.
