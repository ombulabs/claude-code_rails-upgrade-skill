# Gem Compatibility Workflow

**Purpose:** Produce a per-lockfile gem compatibility report against the target Rails version. Output is three buckets (`required bumps`, `blockers`, `already compatible`) that feed the upgrade report's gem-update section.

**When to use:** Step 4.5 of `SKILL.md`, after breaking-change detection and before report generation. The report's `bundle update` plan depends on this output.

---

## Two checks, one orchestrator

The orchestrator picks **one primary** and only escalates to secondary when needed. Don't run both by default.

| Check | Source | Strengths | Weaknesses |
|---|---|---|---|
| **Primary**: `bundle_report compatibility` | `next_rails` (local CLI) | Synchronous, pre-bucketed output, gives upgrade target version per gem, no third-party uptime concern | Reads gemspec metadata only — can miss transitive resolution conflicts |
| **Secondary**: railsbump.org API | `https://api.railsbump.org` | Tests actual lockfile resolution graph against a real Rails release | Async (30-600s polling), depends on third-party uptime, occasional `unknown` results |

Reach for the secondary only when:

1. `bundle_report` cannot run (next_rails not installed; `bundle exec` fails in the env).
2. `bundle_report` reports a gem under "no new compatible versions" and the user wants a second opinion before forking/replacing it.
3. The user explicitly asks for cross-validation.
4. There is reason to suspect a transitive resolution conflict.

---

## Primary: `bundle_report compatibility`

```bash
bundle exec bundle_report compatibility --rails-version=<target>
```

Requires `next_rails` installed in the project (the dual-boot skill installs it in Step 2 of the high-level workflow) and network access (Bundler fetches gem metadata).

### Output shape

`bundle_report` prints three sections. Output is stable; parse with regex.

```
=> incompatible with rails X (with new versions that are compatible):
these gems will need to be upgraded before upgrading to rails X.

paper_trail 2.7.2 - upgrade to 7.1.3
simple_form 2.1.3 - upgrade to 3.2.0
...

=> incompatible with rails X (with no new compatible versions):
these gems will need to be removed or replaced before upgrading to rails X.

rails3_acts_as_paranoid 0.1.1 (loaded from git) - new version, 0.2.5, is not compatible with rails X

=> incompatible with rails X (with no new versions):
these gems will need to be upgraded by us or removed before upgrading to rails X.

strong_parameters 0.2.3 - new version not found
turbo-sprockets-rails3 0.3.14 - new version not found
```

### Bucket mapping

| `bundle_report` section | Bucket | Plan |
| --- | --- | --- |
| "with new versions that are compatible" | required bumps | `bundle update <gem> --conservative` to the listed target version |
| "with no new compatible versions" | blockers | Replace gem, fork the in-flight PR, or drop the dependency |
| "with no new versions" | blockers | Vendor / fork / replace — gem is abandoned or pre-extraction |
| (gem not listed in any section) | already compatible | Note the locked version; no action |

If the command produces no output at all, or if the output contains no `=> incompatible with rails X` headers despite an exit code of 0, treat it as `bundle_report` failing or producing an unparseable result — escalate to the secondary check rather than assuming "all gems compatible." A future `next_rails` release that reformats the output would otherwise silently produce empty buckets.

---

## Secondary: railsbump API

Use only when the orchestrator triggered the secondary path (see "Two checks, one orchestrator" above).

### POST `/lockfiles`

```bash
curl -sS -X POST https://api.railsbump.org/lockfiles \
  -H 'Content-Type: application/json' \
  --data-binary "$(jq -Rs '{lockfile: {content: .}}' < Gemfile.lock)"
```

The lockfile content must be JSON-escaped — the `jq -Rs` filter does that. Mirrors `bin/api_check_lockfile` in the railsbump repo.

**202 Accepted** response shape:

```json
{
  "slug": "abc123",
  "status": "pending",
  "status_url": "https://api.railsbump.org/lockfiles/abc123",
  "retry_after_seconds": 45,
  "message": "Compatibility check is running. ..."
}
```

`Location` and `Retry-After` headers are also set. Capture `slug`, `status_url`, `retry_after_seconds`.

**422 Unprocessable Content** response: `{"errors": [...]}`. Typical causes: `content` blank, malformed Gemfile.lock that the server can't parse, no Rails entry. Surface the messages verbatim and stop — do not retry.

### GET `/lockfiles/:slug`

```bash
curl -sS https://api.railsbump.org/lockfiles/<slug> | jq .
```

**200 OK** response shape:

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

**404** `{"errors": ["Lockfile not found"]}`: slug expired or never existed.

### Polling

Wait `retry_after_seconds` (clamped 30-600 by the server). Then GET `status_url`. Loop until top-level `status` is `complete` or `failed`.

**Cap: 10 polls OR 30 minutes total elapsed, whichever comes first.** Track elapsed time across the polls so the 30-minute ceiling kicks in regardless of the per-poll wait. (The server returns a `retry_after_seconds` derived from gem count and worker concurrency — both fixed for a given lockfile — so the value is constant across polls, not growing. The 30-minute cap bounds the *total* check; the 10-poll cap protects against a stuck pending state.) At the cap, give up — report the slug to the user, note that the secondary check stalled, and proceed with whatever the primary produced.

Do not poll faster than the server's `retry_after_seconds`. The check is per-gem CPU work; hammering the endpoint will not return results sooner.

### Bucket mapping

The API may return multiple `lockfile_checks` (one per Rails release it tested against). Pick the one whose `target_rails_version` matches the upgrade hop's target.

| `gem_check` shape | Bucket | Plan |
| --- | --- | --- |
| `result: "incompatible"`, `earliest_compatible_version` set | required bumps | Bump to at least `earliest_compatible_version` |
| `result: "incompatible"`, `earliest_compatible_version` null | blockers | No compatible version exists — fork / vendor / replace |
| `result: "compatible"` | already compatible | Note the locked version |
| `result: "unknown"` or non-empty `error_message` | blockers (pending information) | Surface the error to the user. If `bundle_report` was also run and answered this gem, prefer its verdict (see Reconciliation). If railsbump is the only signal, treat as a blocker until the user can verify manually — do not silently assume compatible. |

---

## Reconciliation (when both checks ran)

When the orchestrator triggered the secondary because of an ambiguous primary result, both signals exist. Reconcile per gem:

- **Both agree the gem is compatible** → no action.
- **Both agree the gem needs a bump** → use the higher of the two target versions as the minimum bump.
- **`bundle_report` says "no new compatible versions" but railsbump returns `earliest_compatible_version`** → trust railsbump (it sees the actual resolution graph). Bump to that version and run tests.
- **Railsbump returns `unknown` / errored on a gem `bundle_report` already answered** → trust `bundle_report`.
- **They disagree on whether a gem is compatible at all** → run the user's test suite on the higher-version side. Tests are ground truth.

---

## Hand-off to the upgrade plan

Whichever check ran, the output handed to Step 5 is the same three buckets:

1. **Blockers** — incompatible gems with no compatible version, plus any gems where railsbump returned `unknown`/errored and `bundle_report` did not give a clean answer. The hop cannot complete until each one is resolved (see `references/gem-compatibility.md` for the playbook). Mark "pending information" blockers separately so the user knows they may turn into "compatible" or "required bumps" once the missing data lands.
2. **Required bumps** — incompatible gems with a target version. Order top-level gems before their internal dependencies, so bundler can resolve the graph from the root. Example: bump `rspec-rails` before `rspec-mocks` — `rspec-rails` is the gem your Gemfile names directly, and it pulls `rspec-mocks` (and the rest of the rspec-* family) transitively.
3. **Already compatible** — no action needed, but note the locked version so the user can see headroom.

When the agent later runs the actual `bundle update`, prefer one gem at a time (`bundle update <gem> --conservative`) so a single bad resolution does not poison the whole graph.

---

## Caveats

- **Both checks need network.** `bundle_report` fetches gem metadata via Bundler; railsbump is a hosted service. Tell the user when either was skipped due to network failure — do not silently degrade.
- **Slugs expire.** Don't store railsbump slugs across sessions. Re-POST the lockfile if the user comes back later.
- **Compatibility ≠ green tests.** A `compatible` result means "the gem's gemspec accepts the target Rails" (and for railsbump, "the lockfile resolves"). Tests are still the ground truth.
- **Submit each lockfile once per session.** Cache the slug in conversation context.
- **Re-POST when the lockfile changes.** Any time the agent runs `bundle install`, `bundle update`, or otherwise modifies `Gemfile.lock` mid-session, discard the cached slug and POST again. The prior result was for a different lockfile and will mislead the gem-update plan.
