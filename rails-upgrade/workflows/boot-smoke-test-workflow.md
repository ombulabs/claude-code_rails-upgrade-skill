# Boot Smoke Test Workflow

**When to run:** Step 4.6 of the upgrade workflow, after gem-compat (Step 4.5) and before report generation (Step 5).

**Why this step exists:** Step 4 (codebase grep) only sees the user's own code. Step 4.5 (`next_rails bundle_report compatibility` / railsbump) only sees declared dependency constraints. Neither can detect a gem that resolves cleanly under the target Rails version but then crashes at boot because it calls a removed method or requires a removed file.

A booted Rails process is the only signal that catches that class of failure.

## Real examples this catches

| Hop | Gem | Failure mode | What the resolver / static patterns see |
|---|---|---|---|
| 7.1 → 7.2 | `database_cleaner-active_record 2.1.x` | `NoMethodError: undefined method 'schema_migration' for #<...PostgreSQLAdapter>` at first cleaner call | Resolver: ✓ compatible (no upper bound on activerecord). Patterns: ✗ no app-code reference. |
| 7.2 → 8.0 | `jbuilder 2.11.x` | `LoadError: cannot load such file -- active_support/proxy_object` at `Bundler.require` | Resolver: ✓ compatible (no upper bound on activesupport). Patterns: ✗ no app-code reference. |

In both cases the gem ships in default Rails-generated apps and the user did nothing wrong — the gem itself needed a newer minor version with target-Rails support.

## Procedure

### 1. Pick a boot trigger

Anything that loads `config/application.rb` is sufficient. Cheapest options first:

```bash
# Cheapest: just boot the framework
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner "puts Rails.version"

# Slightly heavier: load the test environment without running specs
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec --dry-run

# Heaviest but most thorough: full suite under target Rails
BUNDLE_GEMFILE=Gemfile.next bundle exec rspec
# or
BUNDLE_GEMFILE=Gemfile.next bundle exec rails test
```

Use `rails runner` first. If it boots cleanly, escalate to the full test suite — that catches gems whose problematic code only loads under a specific environment (e.g. test-only gems, eager-load-only paths).

### 2. Diagnose a failure

Boot failures usually show up as one of:

- `LoadError: cannot load such file -- <path>` — a gem `require`s a file Rails removed.
- `NoMethodError: undefined method '<x>' for <Rails internal>` — a gem calls a Rails API that was removed or renamed.
- `ArgumentError` / `TypeError` from a Rails class load — a gem passes args in a now-unsupported shape.

To find the offending gem:

```bash
# Search all bundled gem paths for the missing file / constant
find $(bundle show --paths | tr '\n' ' ') -name "*.rb" 2>/dev/null \
  | xargs grep -l '<missing-file-or-method>' 2>/dev/null
```

The output points at the gem version that needs to bump.

### 3. Resolve

For each offending gem:

1. Check rubygems for a newer minor or patch with target-Rails support:
   ```bash
   curl -s https://rubygems.org/api/v1/versions/<gem>.json \
     | ruby -rjson -e 'puts JSON.parse(STDIN.read).first(8).map{|x|x["number"]}'
   ```
2. Read the gem's CHANGELOG for the target-Rails-compat release.
3. Add a fix-before-bump entry to the upgrade report's gem-update list, citing:
   - The exact failure (`LoadError` / `NoMethodError` / etc.)
   - The minimum compatible version
   - Why a static check missed it (no upper bound declared)
4. Bump the floor in the Gemfile (`gem "<gem>", "~> <new-floor>"`) and re-run `bundle install` for both lockfiles.

### 4. Re-run boot

Repeat steps 1–3 until boot succeeds under `Gemfile.next`. Then proceed to Step 5.

## Output

A short report block to merge into Step 5's Comprehensive Upgrade Report:

```
Boot smoke test (Step 4.6):

  - Triggered: BUNDLE_GEMFILE=Gemfile.next bundle exec rspec --dry-run
  - Result: PASS / FAIL with N gem bumps required

If FAIL → bumps required (added to fix-before-bump):
  - <gem> <old> → <new>: <one-line failure reason>
  - ...
```

If the smoke test passes on the first run, record that explicitly — it is a positive signal that the resolver-level compat check covered everything for this hop.

## Notes

- The smoke test does not replace the post-bump test suite run in Step 6. It is a *boot* check, not a feature check. Step 6 still runs the full suite against both versions.
- Skip this step only if there is no Gemfile.next yet (very early in dual-boot setup). In all other cases, run it.
