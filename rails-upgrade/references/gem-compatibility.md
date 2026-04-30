# Gem Compatibility Reference

**When to read this:** Step 4.5's compatibility check returned at least one blocker (a gem with no released version that supports the target Rails). This file is the playbook for resolving those.

For the compatibility check itself, see `SKILL.md` Step 4.5 (primary: `next_rails` `bundle_report compatibility`; secondary: `workflows/railsbump-compatibility-workflow.md`). Don't load this file unless you're already past the check and have blockers to work through.

This file used to carry static `gem × Rails-version` lookup tables. They drifted out of date and ignored the user's actual lockfile, so they were removed in favor of the live checks.

---

## Update order

When applying the bumps the compatibility check produced:

1. **Ruby** — meet the target Rails version's minimum.
2. **Rails** — update to the target version.
3. **Auth / authorization gems** — `devise`, `pundit`, `cancancan`, `doorkeeper`. Boot-blocking when wrong.
4. **Testing gems** — `rspec-rails`, `factory_bot_rails`, `capybara`, `shoulda-matchers`. Required to validate the upgrade.
5. **Everything else** — incrementally, one gem at a time (`bundle update <gem> --conservative`).

The compatibility check tells you the minimum target for each gem. Use it to decide which gems can stay on their current version and which need an explicit bump.

---

## Playbook: gem has no compatible version

When `bundle_report` lists a gem under "with no new compatible versions" or "with no new versions", or railsbump returns `incompatible` with no `earliest_compatible_version`, you have a blocker. Options, in order of preference:

1. **Look for a maintained fork** that adds Rails support — search GitHub for "fork of <gem>" with the target Rails in recent commits.
2. **Check the gem's open PRs / issues** for in-flight Rails support. If a PR is close to merging, ask the user whether to vendor the branch as a temporary `git:` source.
3. **Wait for an upstream release** if the gem is actively maintained and the next release is imminent.
4. **Switch to an alternative** if the gem is abandoned (e.g., `paperclip` → `shrine` / Active Storage; `strong_parameters` is built into Rails ≥ 4 so just remove it).
5. **Fork and patch** as a last resort. Document the fork in the Gemfile and open an upstream PR.

Surface the choice to the user — do not silently swap gems. Each option has a different long-term cost.

A common false-blocker pattern: pre-extraction gems. `strong_parameters`, `turbo-sprockets-rails3`, `protected_attributes`, etc. were merged into Rails core in a later version. If `bundle_report` flags one of these with "new version not found", check the version guide for the target Rails — odds are the gem just needs to be removed.
