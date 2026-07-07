# Example: Simple Single-Hop Upgrade

A Rails app on Ruby 3.1.7, needing to move to 3.2 to satisfy a planned Rails 8.0 upgrade's Ruby floor. This walks through a single, sequential hop.

## Step 0: Latest Patch Check

`.ruby-version` reads `3.1.4`. Checking `references/ruby-patch-versions.md`'s method, the latest patch of 3.1 is `3.1.7`. The app is behind. Bump `.ruby-version`, the Gemfile's `ruby` directive, and the Dockerfile base image to `3.1.7`, run the test suite, and ship that as its own deploy before starting the minor hop.

## Step 1: Test Suite Baseline

```bash
bundle exec rspec
# 342 examples, 0 failures
```

Green. Proceed.

## Step 2: Deprecation Sweep

```bash
RUBYOPT="-W:deprecated" bundle exec rspec 2>&1 >/dev/null | grep "warning:" | sort -u
```

Output: 3 unique warnings, all from `app/models/legacy_report.rb` using a `Hash#each` pattern affected by 3.1's yielding change (see `version-guides/upgrade-3.1-to-3.2.md`). Fixed by switching to explicit key/value destructuring. Re-ran the sweep: clean. Re-ran the full suite: still green.

## Step 3: Gemfile Audit

`bundle lock` dry-run (bumping the `ruby` directive locally without committing) surfaces one conflict: `some-old-gem 1.2.0` declares `required_ruby_version < 3.2`. Checked its CHANGELOG — version 1.4.0 drops that ceiling with no other changes. Bumped it.

## Step 4: Version Bump

```ruby
ruby "3.2.11"  # was "3.1.7"
```

```bash
bundle lock
bundle install
# clean, no conflicts after the Step 3 gem bump
```

## Step 5: Boot Smoke Test

```bash
bundle exec rails runner "puts RUBY_VERSION"
# 3.2.11
```

Passes on the first try — no undeclared-floor issues found in this app's dependency tree.

## Step 6: Fix/Test Loop

```bash
bundle exec rspec
# 342 examples, 0 failures
```

## Step 7: Landing

- `.ruby-version`: `3.2.11` ✓
- Gemfile: `3.2.11` ✓
- Dockerfile: `FROM ruby:3.2.11` ✓ (checked base OS release via `docker run --rm ruby:3.2.11 cat /etc/os-release` — no workaround changes needed this time, same Debian release as 3.1's image)
- CI: `ruby/setup-ruby` `ruby-version: "3.2.11"` ✓
- Ran the full suite in CI: green.

Committed as a single PR: version pin changes + the one gem bump + the one app-code fix.
