# Rails Upgrade Assistant Skill

A Claude Code skill that helps you upgrade Ruby on Rails applications from version 2.3 through 8.1.

## What Does This Skill Do?

The Rails Upgrade Assistant analyzes your Rails application and generates:

- **Detection Scripts** - Bash scripts that scan your codebase for breaking changes specific to your target Rails version
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

### Prerequisites

This skill depends on the following skills. Install them first:

**1. [rails-load-defaults skill](https://github.com/fastruby/rails-load-defaults-skill)** — incremental `load_defaults` verification and updates:

```bash
git clone https://github.com/fastruby/rails-load-defaults-skill.git
cp -r rails-load-defaults-skill ~/.claude/skills/rails-load-defaults
```

**2. [dual-boot skill](https://github.com/ombulabs/claude-code_dual-boot-skill)** — dual-boot setup and management with `next_rails`:

```bash
git clone https://github.com/ombulabs/claude-code_dual-boot-skill.git
cp -r claude-code_dual-boot-skill/dual-boot ~/.claude/skills/dual-boot
```

### Installation

Add this skill to your Claude Code configuration:

```bash
# Clone the repository
git clone https://github.com/ombulabs/claude-code_rails-upgrade-skill.git

# Add to your Claude Code skills directory
cp -r claude-code_rails-upgrade-skill/rails-upgrade ~/.claude/skills/
```

### Basic Usage

In Claude Code, navigate to your Rails application directory and use natural language:

```
"Upgrade my Rails app to 7.2"
"Help me upgrade from Rails 6.1 to 7.0"
"What breaking changes are in Rails 8.0?"
"Create a detection script for Rails 7.1"
```

### Workflow

1. **Ask for an upgrade** → Claude generates a detection script
2. **Run the script** → Script outputs `rails_{version}_upgrade_findings.txt`
3. **Share the findings** → Claude generates detailed reports based on your actual code
4. **Implement the changes** → Follow the step-by-step migration plan

## Available Commands

| Command | Description |
|---------|-------------|
| `/rails-upgrade` | Start the upgrade assistant |
| "Upgrade to Rails X.Y" | Generate detection script for target version |
| "Here's my findings.txt" | Generate reports from detection results |
| "Show app:update changes" | Preview configuration file changes |
| "Plan upgrade from X to Y" | Get multi-hop upgrade strategy |

## Design Decisions & Best Practices

This skill implements the **FastRuby.io upgrade methodology**, which includes:

### Dual-Boot Strategy

Run your application with two versions of Rails simultaneously using the [`next_rails`](https://github.com/fastruby/next_rails) gem. This allows you to test both versions during the transition and deploy backwards-compatible changes before the version bump.

See the [dual-boot skill](https://github.com/ombulabs/claude-code_dual-boot-skill) for setup, code patterns, CI configuration, and post-upgrade cleanup.

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
