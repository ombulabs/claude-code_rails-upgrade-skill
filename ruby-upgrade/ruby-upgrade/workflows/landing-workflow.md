# Landing Workflow

**Purpose:** Make sure every place the Ruby version is pinned actually agrees, and verify in a deploy-shaped environment before calling the hop done.

**When to use:** Step 7 of the Ruby upgrade workflow, after Step 6's fix/test loop is green.

---

## Step 1: List Every Place the Version Is Pinned

```bash
cat .ruby-version 2>/dev/null
grep -n "^ruby " Gemfile
grep -n "^FROM ruby" Dockerfile 2>/dev/null
grep -rn "ruby-version" .github/workflows/*.yml 2>/dev/null
grep -n "RubyVersion\|ruby_version" .circleci/config.yml 2>/dev/null
```

Every one of these needs to match the target version. A mismatch here is a common, easy-to-miss source of "works locally, breaks in CI/production" — CI installing a different Ruby than the one just verified locally silently re-runs the whole upgrade's risk surface on a version that was never actually tested.

## Step 2: Update Every Mismatch

- `.ruby-version` — the target's full patch version (e.g. `3.2.11`), not just the minor.
- `Gemfile`'s `ruby "X.Y.Z"` line.
- `Dockerfile`'s base image tag, if the app runs in Docker. Re-check whether the new Ruby's base image also changed its underlying OS release (see `references/known-gotchas.md`'s Docker-base-image entry) — a Ruby bump and an OS-base bump are two different things that happen to travel together in the official Ruby images.
- CI config (`ruby/setup-ruby`'s `ruby-version:` in GitHub Actions, the equivalent in CircleCI/other CI).

## Step 3: Verify in a Deploy-Shaped Environment

Local verification (Steps 1-6) is necessary but not sufficient — it doesn't catch environment differences (OS package versions, locale settings, resource limits) that only show up in Docker or CI. Run the full test suite one more time in whichever of these the app actually deploys through:

```bash
docker compose run --rm web bundle exec rspec
# or trigger the actual CI pipeline and wait for it to go green
```

## Step 4: Commit and Open the PR

Bundle the version-pin changes together with whatever Step 2/6 fixes were needed to reach a green suite — this is one logical change (the version hop), not several unrelated ones, even though it may touch several files.

## Step 5: Note What's Next

If a future dependency bump (a Rails hop, another framework upgrade) will need a higher Ruby floor than the one just landed, note it now rather than rediscovering the floor mismatch mid-upgrade of that dependency later. This hop itself is done at this point — the next Ruby hop only starts when it's actually scheduled, back at `SKILL.md` Step 0.

---

## Output Format

```
Landing checklist (Step 7):

  - .ruby-version: PASS (3.2.11)
  - Gemfile ruby directive: PASS (3.2.11)
  - Dockerfile base image: PASS (ruby:3.2.11)
  - CI config: PASS (ruby/setup-ruby ruby-version: "3.2.11")
  - Deploy-shaped verification: PASS (Docker / CI run <link or summary>)
```
