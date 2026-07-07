# Gemfile Ruby-Floor Audit Workflow

**Purpose:** Find every gem in the Gemfile that will block or silently misbehave on the target Ruby, before spending time on the bump itself.

**When to use:** Step 3 of the Ruby upgrade workflow, after the deprecation sweep (Step 2) is clean.

---

## Two Distinct Failure Modes

1. **Declared floor exceeds the target.** Cheap to check, and Bundler enforces it automatically at `bundle lock` time — you'll find out the moment you bump the Gemfile's `ruby` directive.
2. **Declared floor is honest, but the gem's actual code isn't.** It calls a Ruby API that was removed, or uses syntax only valid on a newer Ruby than it claims. Static checks and `bundle install` both say "compatible"; only running the code proves otherwise. This is what `boot-smoke-test-workflow.md` (Step 5) exists to catch — this workflow's job is to catch what it *can* see cheaply and to flag known-risky gems for extra attention at the boot smoke test.
3. **The gem installs and runs fine, but refuses to *analyze* against the new Ruby.** Linters/analyzers (RuboCop and its plugins, `standard`, RBS/`steep` tooling) key off an internal Ruby-version table; a version released before your target Ruby existed rejects it as unknown (`RuboCop found unknown Ruby version: 3.4`) and aborts. Neither `bundle install`, the boot smoke test, nor the test suite catches this — only a CI **lint** step does, so it's a common "everything green locally, CI lint red" surprise. Fix: bump the analyzer(s) in the same hop (see `references/known-gotchas.md`, "A pinned linter/analyzer rejects the new Ruby").

---

## Step 1: Check Every Gem's Declared Floor

```bash
bundle exec gem list --local | awk '{print $1}' | while read -r gem_name; do
  version=$(bundle exec gem list "^${gem_name}$" --local | grep -oE '\([^)]+\)' | tr -d '()')
  echo "$gem_name $version"
done
```

In practice, the fastest real signal is just bumping the Gemfile's `ruby` directive and running `bundle lock` (Step 4 of `SKILL.md`) — if any gem's `required_ruby_version` conflicts, Bundler's resolver error names the exact gem and constraint. Running this check *before* the bump is only useful when you want a report ahead of actually attempting the change; otherwise, Step 4's `bundle lock` output is the audit.

## Step 2: Check `references/known-gotchas.md` for Known-Risky Gems

Cross-reference the Gemfile against gems already known to have runtime-only (undeclared) Ruby-floor issues: `aws-sdk` v2 (`Proc.new`, removed in 3.0), old `paperclip` (`URI.escape`, removed in 3.0). If either is present, plan the swap (modern per-service SDK, `kt-paperclip` fork) as part of this hop rather than discovering it at the boot smoke test.

## Step 3: Check Gems With an Independent Ruby Floor of Their Own

Dev/test-only gems (spring, certain linters, certain debugging gems) sometimes have a Ruby floor *unrelated* to the app's own framework version. If any such gem was previously removed because it needed a newer Ruby than the app had at the time, check whether the target Ruby now clears that floor and whether re-adding it introduces a *new* requirement (see `known-gotchas.md`'s spring example) — don't assume re-adding it is a no-op just because the original blocking reason is now resolved.

## Step 4: Read Each Blocking Gem's CHANGELOG

When `bundle lock` (Step 4 of `SKILL.md`) reports a conflict, it names the gem and the required version bump directly. For each:

1. Check if a newer release fixes the Ruby-floor issue — bump it.
2. If no fix exists, check for a maintained fork.
3. If neither, evaluate whether the gem can be dropped or replaced.

---

## Output

A short list, per blocking gem: current version, required Ruby, target Ruby, and the resolution (bump / fork / replace / drop). Feed this into `templates/upgrade-report-template.md`.
