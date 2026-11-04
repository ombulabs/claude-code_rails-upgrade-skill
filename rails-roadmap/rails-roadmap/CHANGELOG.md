# Changelog

All notable changes to the `rails-roadmap` plugin.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html), where the "public API" is
the plugin's contract with Claude and the user.

## [0.1.0] - 2026-09-20

Initial release.

### Added

- `/rails-roadmap` command — read-only survey of the path from the app's current Ruby and Rails
  to the latest, written to `RAILS_ROADMAP.md`.
- Confidence tiering: the immediate next hop is surveyed `ACTIONABLE` with file:line references;
  later hops are `INDICATIVE` with per-pattern counts and a standing instruction to re-run.
- Per-hop gem compatibility via `bundle_report compatibility`, and a dependency-debt section
  from `bundle_report outdated --json` (the first use of `outdated` anywhere in this repo).
- Per-hop Ruby floors with Ruby bumps interleaved into the step list at the point the floor
  first bites, targeting a supported line rather than the floor itself.
- `references/external-guides.md` — official Rails guide anchors and the FastRuby.io upgrade
  series, per hop. First use of `WebFetch` in this repo; hop 1 only, by design.

### Notes

- Depends on the `rails-upgrade` plugin for its detection patterns and version guides. Claude
  Code installs each plugin as its own extracted subtree, so the catalog is located by globbing
  the sibling plugin's install directory — see `references/pattern-catalog-access.md`. When it
  cannot be found the command stops rather than generating an unmeasured roadmap.
- `bundle_report ruby_check` is not used: it raises `TypeError` in `next_rails` 1.4.8. The Ruby
  floor is resolved from the RubyGems API directly, which is what that method does internally.
