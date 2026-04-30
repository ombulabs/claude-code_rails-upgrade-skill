# Rails Upgrade Assistant Skill

A Claude Code skill that helps you upgrade Ruby on Rails applications from version 2.3 through 8.1.

## What Does This Skill Do?

The Rails Upgrade Assistant analyzes your Rails application and generates:

- **Comprehensive Upgrade Reports** - Detailed migration guides with OLD vs NEW code examples from your actual codebase
- **app:update Previews** - Shows exactly what configuration files will change when you run `rails app:update`

The skill follows a sequential upgrade strategy—you upgrade one minor/major version at a time (e.g., 5.2 → 6.0 → 6.1 → 7.0), never skipping versions.

## Why Trust This Skill?

This skill is built on real-world experience, not just documentation:

- **60,000+ developer hours** of Rails upgrade experience
- **Upgrades from Rails 2.3 to Rails 8.1** for clients worldwide
- Based on the methodology documented in ["The Complete Guide to Upgrade Rails"](https://www.fastruby.io/upgrade) ebook
- Created by the team at [FastRuby.io](https://fastruby.io), specialists in Rails upgrades since 2017

We've encountered (and solved) edge cases that don't appear in any documentation. This skill encapsulates that hard-won knowledge.

## How to Use This Skill

### Installation

This skill depends on two companion skills: [rails-load-defaults](https://github.com/ombulabs/claude-code_rails-load-defaults-skill) and [dual-boot](https://github.com/ombulabs/claude-code_dual-boot-skill). A fourth sibling plugin, `upgrade-cleanup`, lives in this repo and runs the post-upgrade scaffolding teardown. The marketplace install handles all four.

**From inside the Claude Code CLI prompt (recommended):**

```
/plugin marketplace add ombulabs/claude-skills
/plugin install rails-upgrade@ombulabs-ai
/plugin install rails-load-defaults@ombulabs-ai
/plugin install dual-boot@ombulabs-ai
/plugin install upgrade-cleanup@ombulabs-ai
```

**From your terminal:**

```bash
claude plugin marketplace add https://github.com/ombulabs/claude-skills.git
claude plugin install rails-upgrade@ombulabs-ai
claude plugin install rails-load-defaults@ombulabs-ai
claude plugin install dual-boot@ombulabs-ai
claude plugin install upgrade-cleanup@ombulabs-ai
```

**Manual install:**

```bash
# 1. This skill
git clone https://github.com/ombulabs/claude-code_rails-upgrade-skill.git
cp -r claude-code_rails-upgrade-skill/rails-upgrade ~/.claude/skills/

# 2. upgrade-cleanup (sibling plugin, same repo)
cp -r claude-code_rails-upgrade-skill/upgrade-cleanup ~/.claude/skills/

# 3. rails-load-defaults (dependency)
git clone https://github.com/ombulabs/claude-code_rails-load-defaults-skill.git
cp -r claude-code_rails-load-defaults-skill/rails-load-defaults ~/.claude/skills/

# 4. dual-boot (dependency)
git clone https://github.com/ombulabs/claude-code_dual-boot-skill.git
cp -r claude-code_dual-boot-skill/dual-boot ~/.claude/skills/
```

### Basic Usage

In Claude Code, navigate to your Rails application directory and use natural language:

```
"Upgrade my Rails app to 7.2"
"Help me upgrade from Rails 6.1 to 7.0"
"What breaking changes are in Rails 8.0?"
```

### Workflow

1. **Ask for an upgrade** → Claude generates detailed reports based on your actual code
2. **Implement the changes** → Follow the step-by-step migration plan

## Available Commands

| Command | Description |
|---------|-------------|
| `/rails-upgrade` | Start the upgrade assistant |
| "Finish the upgrade" / "Clean up dual-boot" / "Abandon this upgrade" | Trigger the `upgrade-cleanup` plugin. Asks whether to keep the next or current version, then drops `NextRails.next?` / `NextRails.current?` branches and retires dual-boot scaffolding. |
| "Upgrade to Rails X.Y" | Generate reports from detection results |
| "Show app:update changes" | Preview configuration file changes |
| "Plan upgrade from X to Y" | Get multi-hop upgrade strategy |

## Design Decisions & Best Practices

This skill implements the **FastRuby.io upgrade methodology**, which includes:

### Dual-Boot Strategy

Run your application with two versions of Rails simultaneously using the [`next_rails`](https://github.com/fastruby/next_rails) gem. This allows you to test both versions during the transition and deploy backwards-compatible changes before the version bump.

See the [dual-boot skill](https://github.com/ombulabs/claude-code_dual-boot-skill) for setup, code patterns, and CI configuration.

### Post-Upgrade Cleanup

Once a hop is finished (or abandoned), the `upgrade-cleanup` sibling plugin tears down the dual-boot scaffolding so the tree stops carrying two Rails versions in parallel. It is scoped tightly to scaffolding removal, not a kitchen-sink "finish the upgrade" pass.

Activate it with phrases like "finish the upgrade", "clean up dual-boot", or "abandon this upgrade". The workflow:

1. **Phase 0 - Pre-flight.** Detects Docker vs local, smoke-checks `bundle` / `bin/rails runner` on both sides, and asks whether to keep the **next** version (finishing) or the **current** version (abandoning / pausing the hop).
2. **Phase 1 - Dual-boot removal.** Drops `NextRails.next?` / `NextRails.current?` branches, strips the `next?` Gemfile method and conditional groups, sweeps for `deprecation_tracker` residue *before* removing `next_rails` (the gem ships `DeprecationTracker`; leftover `require`s break test boot), swaps lockfiles, and updates CI to drop the dual-boot job.
3. **Phase 2 - Old-version code retirement.** Monkey-patches, stale gem pins, `docker-compose.yml` / `compose.yaml` sister services (`web-next`, `worker-next` with `BUNDLE_GEMFILE: Gemfile.next`), and doc drift (`README`, `bin/setup`, `.tool-versions`, `Dockerfile`).
4. **Phase 3 - Housekeeping.** CI matrix entry, `Dockerfile` / `.ruby-version` / `.tool-versions` alignment for Ruby bumps.
5. **Phase 4 - Final verification.** Local or CI, with explicit fallback to CI when the local environment can't run tests.
6. **Phase 5 - Commit and PR.** Suggested commit messages, single-purpose PR.

Out of scope by design: `load_defaults` alignment (handled by `rails-load-defaults`), deprecation triage (next-hop work owned by `rails-upgrade`), and migration class suffix / `db/schema.rb` regen (upgrade artifacts, not cleanup).

### Sequential Upgrades Only

We **never skip versions**. Each Rails minor/major version introduces changes that build on previous versions. Skipping creates compound issues that are nearly impossible to debug.

```
✅ Correct: 6.0 → 6.1 → 7.0 → 7.1
❌ Wrong:   6.0 → 7.1 (skipping 6.1 and 7.0)
```

### Deprecation-First Approach

Before upgrading:
1. Enable deprecation warnings in your current version
2. Fix all deprecation warnings
3. Deploy those fixes to production
4. Then bump the Rails version

This reduces the upgrade to a single Gemfile change.

## What This Skill Doesn't Do

Be aware of these limitations:

| Limitation | Explanation |
|------------|-------------|
| **Gradual deployments** | This skill focuses on code changes, not deployment strategies. Rolling deployments, canary releases, and feature flags are outside its scope. |
| **Debugging monkeypatching issues** | If gems or your code monkeypatch Rails internals, you may encounter weird issues that require manual investigation. |
| **Accurate time estimates** | The difficulty ratings and time estimates are rough guidelines based on typical applications. Your mileage will vary based on codebase size, test coverage, and custom code complexity. |
| **Automated code changes** | The skill provides guidance and examples, but you implement the changes. It won't automatically refactor your code. |
| **Gem compatibility resolution** | While we note common gem version requirements, resolving complex dependency conflicts requires manual intervention. |
| **Rails LTS upgrades** | While many of the things this Skill can do will work to upgrade Rails LTS, the strategy for those apps will be different and the Rails source code is not the same as the main Rails repository |

## Contributing

We welcome contributions! Here's how you can help:

### Adding or Updating Version Guides

1. Fork the repository
2. Create a branch: `git checkout -b add-rails-X-Y-guide`
3. Add/update files in `version-guides/`
4. Follow the existing format and structure
5. Submit a pull request

### Reporting Issues

- Found incorrect information? [Open an issue](https://github.com/ombulabs/claude-code_rails-upgrade-skill/issues)
- Have a suggestion? We'd love to hear it
- Encountered an edge case? Share your experience

### Guidelines

- Keep content factual and based on official Rails documentation
- Include code examples with BEFORE/AFTER patterns
- Test detection patterns against real codebases when possible
- Attribute sources appropriately

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Sponsors

This project is sponsored by:

### [OmbuLabs.ai](https://ombulabs.ai) | Custom AI Solutions

We build custom AI solutions that integrate with your existing workflows. From Claude Code skills to full AI agent systems.

### [FastRuby.io](https://fastruby.io) | Ruby Maintenance, Done Right

The Rails upgrade experts. We've been upgrading Rails applications professionally since 2017, helping companies stay current and secure.

---

**Questions?** Open an issue or reach out to us at [hello@ombulabs.com](mailto:hello@ombulabs.com)
