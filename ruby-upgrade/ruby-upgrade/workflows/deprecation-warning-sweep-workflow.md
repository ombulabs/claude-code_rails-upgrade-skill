# Deprecation Warning Sweep Workflow

**Purpose:** Surface everything the *current* Ruby already warns about regarding the *next* minor's removals, and fix the app-code half of it, before touching the Gemfile's `ruby` directive.

**When to use:** Step 2 of the Ruby upgrade workflow, after the test suite is confirmed green (Step 1) and the app is on the latest patch of its current minor (Step 0).

---

## Step 1: Check for Silenced Warnings

```bash
grep -rnE "\\\$VERBOSE\s*=\s*nil|Warning\[:deprecated\]\s*=\s*false|Warning\.filters|-W0\b" \
  . --include="*.rb" --include="Rakefile" --include=".rspec" 2>/dev/null
```

If found, understand why before removing — see `references/deprecation-warnings.md` for common culprits and how to scope a fix narrowly instead of removing a silencer wholesale.

## Step 2: Run the Suite With Warnings Enabled

```bash
RUBYOPT="-W:deprecated" bundle exec rspec 2>&1 >/dev/null | grep "warning:" | sort -u
```

Substitute the app's actual test command (`bin/rails test`, `bundle exec rake test`, etc.). Full technique, including narrower single-file scoping, is in `references/deprecation-warnings.md`.

## Step 3: Triage Every Warning

Split into three buckets by file path:

- **App code** (`app/`, `lib/`, `config/`) — fix now, this hop.
- **Gem code** (the gem install path / `vendor/bundle`) — check for a newer gem release or maintained fork (see `references/known-gotchas.md` for confirmed real examples of this exact situation); if none exists and it's not yet breaking, defer to the next hop.
- **Tooling / bundler itself** (paths under bundler's own install, e.g. `.../gems/bundler-X.Y.Z/lib/bundler/vendor/...`) — not app code and not one of *your* gems, so it belongs in neither bucket above. An outdated bundler is its own source of Ruby-deprecation noise. Confirmed real example (Ruby 3.2 → 3.3): bundler `2.2.21`'s vendored Thor triggered `warning: constant DidYouMean::SPELL_CHECKERS is deprecated` on every command. The fix is to move to the bundler shipped with (or supported by) the target Ruby — which usually happens for free when you relock on the target Ruby: `bundle lock` / `bundle install` rewrites `BUNDLED WITH` to the newer bundler and the warning disappears. Don't chase these as if they were app or app-gem issues.

## Step 4: Fix Every App-Code Warning

Apply the fix, re-run Step 2's command, confirm the warning is gone. Repeat until the app-code bucket is empty.

## Step 5: Re-run the Full Test Suite

Confirm the fixes didn't break anything, using the same command as `test-suite-verification-workflow.md` Step 3.

## Step 6: Record the Sweep Result

Use the output format in `references/deprecation-warnings.md` — this becomes part of the upgrade report (`templates/upgrade-report-template.md`).

---

## Stop Conditions

- Do not proceed to Step 3 (Gemfile audit) of `SKILL.md` until every app-code warning from this sweep is fixed.
- A completely clean sweep is a real, reportable result — say so explicitly rather than treating "nothing to fix" as "nothing was checked."
