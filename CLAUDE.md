# Project conventions for Claude

This file captures project-specific conventions Claude should follow when working in this repo.

## Version guides (`rails-upgrade/version-guides/*.md`)

- **Do NOT include "Difficulty" or "Estimated Time" in the header.** These are subjective, application-dependent, and drift out of date. Keep the header minimal: title, Ruby requirement, and the attribution line.
- Base content on primary sources: the official Rails upgrade guide, the FastRuby.io blog, the OmbuLabs ebook chapter, and RailsDiff for the matching versions.
- Organize breaking changes under 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW priority sections.
- Each breaking change entry should include: "What Changed", a detection pattern, and a BEFORE/AFTER fix.
- Use `NextRails.next?` (never `respond_to?` or `Gem::Version` comparisons) in dual-boot code examples.

## Detection patterns (`rails-upgrade/detection-scripts/patterns/rails-*-patterns.yml`)

- File naming: `rails-{VERSION}-patterns.yml` where `{VERSION}` is the major+minor without a dot (e.g., `rails-42-patterns.yml` for Rails 4.2).
- Organize patterns under `high_priority`, `medium_priority`, and `low_priority`.
- Each pattern needs: `name`, `pattern` (regex), `exclude` (regex, empty string if none), `search_paths`, `explanation`, `fix`, `variable_name`.
- Include a `dependencies` section for any bridge/compatibility gems mentioned in the guide.
- Verify YAML parses before committing (`ruby -e "require 'yaml'; YAML.safe_load(File.read('...'))"`).
