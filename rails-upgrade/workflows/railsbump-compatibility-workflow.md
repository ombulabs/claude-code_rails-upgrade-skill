# Railsbump Compatibility Workflow

**Purpose:** Cross-check gem compatibility against the target Rails version using the railsbump.org API, when the primary local check (`next_rails`'s `bundle_report compatibility`) is unavailable, ambiguous, or insufficient.

**When to use:** This is the **secondary** compatibility source. Primary is `bundle exec bundle_report compatibility --rails-version=<target>` from `next_rails` — it runs locally, returns upgrade-target versions per gem, and pre-buckets results into three actionable categories. See `SKILL.md` Step 4.5 for the primary path.

Reach for railsbump only when:

1. `bundle_report` cannot run (next_rails not installed; `bundle exec` fails in the env).
2. `bundle_report` reports a gem under "no new compatible versions" and the user wants a second opinion before forking/replacing it.
3. The user explicitly asks for cross-validation.
4. There is reason to suspect a transitive resolution conflict — `bundle_report` reads gemspec metadata, while railsbump tests the actual lockfile resolution graph against a real Rails release.

---

## Why this endpoint exists

Static gem compatibility tables drift out of date and ignore the user's actual locked versions. Railsbump analyzes the real `Gemfile.lock` against a real Rails release and returns the **earliest gem version compatible with the target Rails** for every gem in the lockfile. It complements `bundle_report` — different blind spots, different failure modes.

---

## API contract

**Base host:** `https://api.railsbump.org`

### POST `/lockfiles`

Submit a `Gemfile.lock` for analysis.

**Request:**

```http
POST /lockfiles HTTP/1.1
Host: api.railsbump.org
Content-Type: application/json

{"lockfile": {"content": "<raw Gemfile.lock contents>"}}
```

**Response (202 Accepted):**

```json
{
  "slug": "abc123",
  "status": "pending",
  "status_url": "https://api.railsbump.org/lockfiles/abc123",
  "retry_after_seconds": 45,
  "message": "Compatibility check is running. Wait ~45 seconds, then GET https://api.railsbump.org/lockfiles/abc123 to retrieve results. Re-poll if status is still 'pending'."
}
```

`Location` and `Retry-After` headers are also set. Use them.

**Failure (422):** `{"errors": ["..."]}` — typically a malformed lockfile.

### GET `/lockfiles/:slug`

Fetch results.

**Response (200):**

```json
{
  "slug": "abc123",
  "status": "complete",
  "lockfile_checks": [
    {
      "target_rails_version": "7.2.0",
      "ruby_version": "3.3.0",
      "bundler_version": "2.5.6",
      "rubygems_version": "3.5.6",
      "status": "complete",
      "gem_checks": [
        {
          "name": "devise",
          "locked_version": "4.8.1",
          "status": "complete",
          "result": "incompatible",
          "earliest_compatible_version": "4.9.4",
          "error_message": null
        }
      ]
    }
  ]
}
```

Top-level `status`: `pending` | `complete` | `failed`. Per-`gem_check` `result`: typically `compatible` | `incompatible` | `unknown`. Treat any unrecognized value as `unknown` and surface it.

**404:** `{"errors": ["Lockfile not found"]}` — slug expired or never existed.

---

## Step-by-Step

### Step 1: Confirm the lockfile to send

Default: the project's top-level `Gemfile.lock`.

If the user is dual-booted (a `Gemfile.next.lock` exists), prefer `Gemfile.lock` here — railsbump answers "what is the earliest version of each gem that works on the target Rails", which is the question to ask *before* the dual-boot bump. Once the upgrade is committed, the same call against `Gemfile.next.lock` becomes a regression check.

Stop if no `Gemfile.lock` exists. Tell the user to run `bundle install` first.

### Step 2: POST the lockfile

Use Bash. The lockfile content must be JSON-escaped — pipe through `jq -Rs` exactly like `bin/api_check_lockfile` in the railsbump repo:

```bash
curl -sS -X POST https://api.railsbump.org/lockfiles \
  -H 'Content-Type: application/json' \
  --data-binary "$(jq -Rs '{lockfile: {content: .}}' < Gemfile.lock)"
```

Capture the response. Extract `slug`, `status_url`, and `retry_after_seconds`.

If the response is 422, surface `errors` to the user verbatim and stop. Do not retry.

### Step 3: Poll until terminal

Wait `retry_after_seconds` (clamped 30-600 by the server). Then GET the `status_url`:

```bash
curl -sS https://api.railsbump.org/lockfiles/<slug> | jq .
```

Loop until top-level `status` is `complete` or `failed`. Cap at ~10 polls (~10 minutes max) before giving up — at that point report the slug to the user so they can check manually and fall back to `next_rails`'s `bundle_report compatibility --rails-version=X.Y`.

Do not poll faster than the server's `retry_after_seconds`. The check is per-gem CPU work; hammering the endpoint will not return results sooner.

### Step 4: Parse results

Find the `lockfile_check` whose `target_rails_version` matches the upgrade hop's target (e.g., `7.2.0` for a 7.1 → 7.2 hop). The API may return multiple `lockfile_checks` (one per Rails release it tested against); pick the right one.

Bucket `gem_checks` by `result`:

| Bucket | What to do |
|---|---|
| `incompatible` with `earliest_compatible_version` set | The user must update this gem. Plan `bundle update <name>` to at least `earliest_compatible_version`. |
| `incompatible` with `earliest_compatible_version` null | No compatible version exists yet. Flag as a blocker. Suggest the user check the gem's repo, or look for a fork / alternative. |
| `compatible` | No action needed. |
| `unknown` / errored (non-empty `error_message`) | Surface the error to the user. Cross-check against `bundle_report compatibility` if possible. |

### Step 5: Reconciling with `bundle_report`

When this workflow runs as a secondary check, you already have `bundle_report` output. Compare per-gem:

- **Both agree the gem is compatible** → no action.
- **Both agree the gem needs a bump** → use the higher of the two target versions as the minimum bump.
- **`bundle_report` says "no new compatible versions" but railsbump returns an `earliest_compatible_version`** → trust railsbump (it sees the actual resolution graph). Bump to that version and run tests.
- **Railsbump returns `unknown` / errored on a gem `bundle_report` already answered** → trust `bundle_report`. Don't re-check.
- **They disagree on whether a gem is compatible at all** → run the user's test suite on the higher-version side; tests are ground truth.

If `bundle_report` could not run (the case that triggered this workflow as primary), proceed with railsbump's buckets directly. Tell the user `bundle_report` was skipped so they know which signal the plan is based on.

### Step 6: Hand off to the upgrade plan

Feed the bucketed list into the upgrade report's gem-update section. The output should be:

1. **Blockers** — incompatible gems with no compatible version. The hop cannot complete until each one is resolved.
2. **Required bumps** — incompatible gems with a target version. Order by dependency depth where obvious (e.g., bump `rspec-rails` before `rspec-mocks`).
3. **Already compatible** — no action needed, but note the locked version so the user can see headroom.

When the agent runs the actual `bundle update`, prefer one gem at a time (`bundle update <gem> --conservative`) so a single bad resolution does not poison the whole graph.

---

## Caveats

- **Network required.** If the API is unreachable, fall back to `bundle_report compatibility` and tell the user the railsbump check was skipped. Do not silently degrade — the gem-update plan is less reliable without it.
- **Slugs expire.** Don't store slugs across sessions. Re-POST the lockfile if the user comes back later.
- **The check is best-effort.** A `compatible` result means "the lockfile resolves and the gem's gemspec accepts the target Rails", not "your test suite will pass". Tests are still the ground truth.
- **Don't hammer the API.** Submit once per lockfile per session. Cache the slug in conversation context.
