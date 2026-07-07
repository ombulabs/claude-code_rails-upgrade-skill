# Ruby Patch Versions

How to find the latest patch of a Ruby minor, and why it matters specifically for an upgrade project (not just as general hygiene).

---

## Why This Matters For an Upgrade, Specifically

Ruby's release process backports deprecation warnings for a minor's own soon-to-be-removed behavior across that minor's patch releases as the next minor's removal list gets finalized. A late patch of `2.7.x` warns about more `3.0`-scheduled removals than `2.7.0` did. Being on an old patch when you run this skill's Step 2 deprecation sweep means the sweep runs against a Ruby that doesn't yet know about everything the next hop will break — you can pass Step 2 clean and still hit fresh breakage on the target minor, purely because the warning that would have caught it hadn't shipped yet in the patch you were on.

This is in addition to the generic reason to always be on the latest patch (security fixes, bug fixes) — that generic reason applies with or without an upgrade in progress. The deprecation-surfacing property is the reason it specifically matters *before starting a minor hop*.

---

## How to Check

```bash
# If using asdf with the ruby plugin:
asdf list all ruby | grep "^3\.2\."

# If using rbenv:
rbenv install -l | grep "^3\.2\."

# Directly against the official release list:
curl -s https://www.ruby-lang.org/en/downloads/releases/ | grep -oE "Ruby 3\.2\.[0-9]+" | sort -V | tail -1
```

Compare against `.ruby-version` or the Gemfile's `ruby "X.Y.Z"` line.

---

## Latest Patch by Minor (approximate — always re-check against the sources above)

| Minor | Latest known patch (verify before relying on this) | End of life |
|-------|------------------------------------------------------|-------------|
| 2.6 | 2.6.10 | 2022-03-31 (EOL) |
| 2.7 | 2.7.8 | 2023-03-31 (EOL) |
| 3.0 | 3.0.7 | 2024-03-31 (EOL) |
| 3.1 | 3.1.7 | 2025-03-31 (EOL) |
| 3.2 | 3.2.11 | 2026-03-31 |
| 3.3 | 3.3.9 | 2027-03-31 (projected) |
| 3.4 | 3.4.7 | 2028-03-31 (projected) |

This table is a starting point, not a source of truth — Ruby ships patch releases on an as-needed basis (security fixes especially), so treat any row here as potentially stale by the time you read it. Always confirm with one of the commands above before pinning a version.

If the app is on an EOL minor already, the patch-freshness check still applies (there may be a final patch you're missing), but the real priority is the minor hop itself — EOL means no further security patches will ever ship for that minor, regardless of which patch you're on within it.

---

## What To Do If Behind

1. Bump `.ruby-version` and the Gemfile's `ruby` directive to the latest patch of the *current* minor (not the target minor yet).
2. Bump the Dockerfile's base image tag, if any (`ruby:2.7.2` → `ruby:2.7.8`), and re-check whether the new image changed its underlying OS base — a Ruby patch bump does not usually change the OS base, but it's a cheap check.
3. Run the full test suite.
4. Ship the patch bump as its own deploy before starting the minor hop's Step 1.
