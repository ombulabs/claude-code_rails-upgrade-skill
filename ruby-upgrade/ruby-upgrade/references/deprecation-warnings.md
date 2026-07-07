# Ruby Deprecation Warnings Guide

Ruby's own equivalent of `rails-upgrade`'s deprecation-warnings sweep — surfacing what the *current* Ruby already warns about regarding removals scheduled for the *next* minor, before you bump.

---

## Why This Matters

Ruby doesn't print deprecation warnings by default — `$VERBOSE` (equivalently `Warning[:deprecated]`) is off in a normal run. That means an app can be silently accumulating calls to soon-to-be-removed APIs with zero visibility, right up until the version bump turns every one of them into a hard failure at once. Turning warnings on *before* bumping converts "discover N breakages simultaneously on the new Ruby" into "fix N warnings one at a time on the Ruby you're already running, with a green test suite as ground truth the whole way."

This is the direct Ruby-level analog of `rails-upgrade`'s Rails deprecation warnings — same idea, different framework layer.

---

## Check for Silenced Warnings First

Before assuming "no warnings" means "no problems," check whether warnings are actually being suppressed somewhere:

```bash
grep -rnE "\\\$VERBOSE\s*=\s*nil|Warning\[:deprecated\]\s*=\s*false|Warning\.filters|-W0\b" \
  . --include="*.rb" --include="Rakefile" --include=".rspec" 2>/dev/null
```

Common culprits:

- `$VERBOSE = nil` somewhere in `spec_helper.rb` / `test_helper.rb` (sometimes added to quiet a noisy third-party gem, silencing everything else along with it)
- `RUBYOPT=-W0` set in a shell profile, CI env var, or `.env` — silences all warnings globally
- A wrapper script or Rake task that redirects/filters stderr, where Ruby's own deprecation warnings are written

If you find one of these, understand why it was added before removing it — but removing it (or scoping it more narrowly) is usually the right call before an upgrade, same as `rails-upgrade`'s guidance on `ActiveSupport::Deprecation.silence` blocks.

---

## Turning Warnings On

```bash
# Whole test suite, one-shot
RUBYOPT="-W:deprecated" bundle exec rspec
# or
RUBYOPT="-W:deprecated" bin/rails test

# Narrower: just Ruby's own experimental-feature warnings
RUBYOPT="-W:experimental" bundle exec rspec

# Both together
RUBYOPT="-W:deprecated -W:experimental" bundle exec rspec
```

`-W:deprecated` and `-W:experimental` are Ruby 2.7+ category-scoped warning flags — deliberately narrower than the old bare `-w` (which also turns on a large volume of unrelated style-ish warnings: unused variables, ambiguous precedence, etc. — signal-to-noise is poor for an upgrade sweep specifically).

For a narrower scope (a single file, a single boot, without touching `RUBYOPT` globally):

```ruby
# At the top of a script, or in an initializer temporarily
Warning[:deprecated] = true
```

---

## Reading the Output

Deprecation warnings go to stderr, one line per call site (not deduplicated by default), in the shape:

```
path/to/file.rb:42: warning: <description of what's deprecated and why>
```

Capture and dedupe for triage:

```bash
RUBYOPT="-W:deprecated" bundle exec rspec 2>&1 >/dev/null \
  | grep "warning:" \
  | sort -u
```

(`2>&1 >/dev/null` keeps stderr on the pipe while dropping stdout, so test-runner progress dots don't drown out the warning lines.)

---

## Triage: App Code vs. Gem Code

Every warning names a file. Two buckets:

- **App code** (`app/`, `lib/`, `config/` paths) — yours to fix directly. Goes in fix-before-bump, same rubric as `rails-upgrade`'s `kind: deprecation` (works today, becomes a hard break at the actual version bump).
- **Gem code** (paths under `vendor/bundle` / the gem install path) — not yours to fix in place. Check:
  1. Does a newer release of that gem fix it? (`gem_name`'s CHANGELOG, or diff the warning's source location across versions on GitHub — same technique as `rails-upgrade`'s `references/gem-compatibility.md` "Known Gotchas" entries.)
  2. If no fix exists yet, is the gem still needed, or does `known-gotchas.md` already document a maintained fork?
  3. If neither, this becomes a blocker for the *next* hop, not necessarily this one — the warning means it still works today. Note it and move on unless it's already failing.

---

## What Ruby 2.7 → 3.0 Specifically Warns About

The single most consequential Ruby deprecation sweep in recent history, because Ruby 2.7 was deliberately built to warn about most of what 3.0 would break. Two categories dominate:

1. **Keyword argument / positional hash separation.** By far the largest volume of warnings on most codebases. A method call passing a trailing hash where the method itself declares keyword arguments (or vice versa) prints a warning naming the exact call site. This is *the* headline Ruby 3.0 change — budget real time for it on any app that hasn't already been swept.
2. **Everything else scheduled for removal in 3.0** — `Proc.new` with no explicit block, `$SAFE`, `Fixnum`/`Bignum` (already unified into `Integer`, but old code referencing the constants directly warns), and others. See `known-gotchas.md` for confirmed real examples of what happens when these aren't caught before the bump (`Proc.new`, `URI.escape` — the latter deprecated since 2.7 without a `-W:deprecated`-category warning in all Ruby patches, so also grep gem source directly per that file's detection tip).

Later hops (3.0→3.1, 3.1→3.2, etc.) have their own, smaller deprecation surfaces — repeat this same sweep at every hop rather than assuming 2.7→3.0's warnings were a one-time special case.

---

## Output Format for the Upgrade Report

Mirrors `rails-upgrade`'s boot-smoke-test report block:

```
Ruby deprecation sweep (Step 2):

  - Triggered: RUBYOPT="-W:deprecated" bundle exec rspec
  - Result: N unique warnings (M app-code, K gem-code)

App-code warnings (fix-before-bump):
  - <file>:<line>: <one-line description>
  - ...

Gem-code warnings (tracked, not directly fixable):
  - <gem> <version>: <one-line description> -- <fixed in newer release? / known fork? / defer to next hop>
  - ...
```

If the sweep comes back completely clean, record that explicitly — it's a real signal that this hop's app-code surface is already 3.0-ready (or whatever the target minor is), not an absence of effort.
