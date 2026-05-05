# Direct Detection Workflow

**Purpose:** Run breaking change detection directly using Claude's tools (Grep, Glob, Read)

**When to use:** Step 4 of the upgrade workflow — after tests pass and the upgrade path is validated. (load_defaults alignment is Step 7, *after* detection, not before.)

---

## Why Direct Detection?

Claude Code can:
- Search files directly using the Grep tool
- Find files by pattern using the Glob tool
- Read file contents using the Read tool
- Analyze results immediately
- Generate reports without user round-trip

---

## Step-by-Step Workflow

### Step 1: Load Pattern File

Read the version-specific pattern file:

```
detection-scripts/patterns/rails-{VERSION}-patterns.yml
```

Example for Rails 8.0:
```
detection-scripts/patterns/rails-80-patterns.yml
```

The pattern file contains:
- `upgrade_findings.high_priority` - Critical patterns to search
- `upgrade_findings.medium_priority` - Important patterns to search
- `upgrade_findings.low_priority` - Lower-urgency patterns to search
- Each pattern has: `name`, `kind`, `pattern`, `search_paths`, `explanation`, `fix`, `variable_name`
- Each pattern may optionally declare `prereqs:` — a list of gem-version floors that must be in place for the suggested `fix:` to actually work. See "The `prereqs:` field" below.
- `kind` is one of `breaking` / `deprecation` / `migration` / `optional` — see `CLAUDE.md` → "Assigning `kind:`" for the rubric. The bucket each finding lands in (see Step 4 / Output Format) is driven by `kind`, not by priority.

#### The `prereqs:` field (optional)

Some patterns describe a Rails-API change whose `fix:` only works on a *recent enough* version of a wrapper gem. The Rails API exists at the target version, but the gem that exposes it to the app may need a bump first.

Example: at Rails 7.2 the `fixture_path=` setter on `ActiveSupport::TestCase` is deprecated in favor of `fixture_paths=` (plural array). `fixture_paths=` exists from Rails 7.1+ — but in an rspec project the setter goes through `RSpec::Core::Configuration`, which only forwards `fixture_paths=` from `rspec-rails 6.1.0+`. On `rspec-rails 6.0.x` the suggested fix raises `NoMethodError`.

Declaring this in the pattern:

```yaml
- name: "fixture_path deprecated"
  kind: "deprecation"
  pattern: "fixture_path[^s]"
  exclude: "fixture_paths"
  search_paths:
    - "test/"
    - "spec/"
    - "config/"
  explanation: "fixture_path singular is deprecated in favor of fixture_paths plural"
  fix: "Change fixture_path to fixture_paths (array)"
  variable_name: "FIXTURE_PATH"
  prereqs:
    - gem: "rspec-rails"
      min_version: "6.1.0"
      reason: "config.fixture_paths= is forwarded from RSpec::Core::Configuration only on 6.1+"
      when: "rspec-rails is present in the bundle"
```

When compiling findings:

1. For each pattern with `prereqs:`, check the user's `Gemfile.lock`.
2. For each prereq whose `when:` matches (or has no `when:`):
   - If the gem is at or above `min_version`, ignore the prereq.
   - If the gem is below `min_version`, add a fix-before-bump entry **for the prereq gem bump**, in addition to (and ordered before) the original finding.

This makes the cascade explicit in the report — readers see "bump rspec-rails first, *then* rename fixture_path" instead of discovering the second step mid-implementation.

`prereqs:` is optional. Most patterns describe Rails-only API changes and need none.

---

### Step 2: Process High Priority Patterns

For each pattern in `upgrade_findings.high_priority`:

```yaml
- name: "Sprockets usage"
  pattern: "sprockets|Sprockets"
  exclude: "propshaft"
  search_paths:
    - "Gemfile"
    - "config/"
    - "app/assets/"
  explanation: "Rails 8.0 replaces Sprockets with Propshaft"
  fix: "Migrate to Propshaft or keep Sprockets explicitly"
```

**Execute using Grep tool:**

```
Grep:
  pattern: "sprockets|Sprockets"
  path: "Gemfile"
  output_mode: "content"
```

```
Grep:
  pattern: "sprockets|Sprockets"
  path: "config/"
  output_mode: "content"
```

**Collect results:**
- File paths where pattern was found
- Line numbers
- Matching content
- Context (lines before/after if helpful)

---

### Step 3: Process Medium and Low Priority Patterns

Same process for `upgrade_findings.medium_priority` and `upgrade_findings.low_priority` patterns.

---

### Step 4: Compile Findings (group by `kind`, sub-order by `priority`)

Group findings into **two buckets** based on each pattern's `kind`:

- **Fix before bump** — `kind: breaking` and `kind: deprecation`. These either raise / remove APIs / prevent boot at the target version, or emit a deprecation warning at the target version. Both should be addressed during the same upgrade campaign:
  - `breaking` blocks the upgrade outright.
  - `deprecation` works at this hop but warns at runtime (log noise in production) and typically becomes `breaking` at the next hop. Addressing it now is the same work either way and de-risks the next upgrade.
- **Fix when ready** — `kind: migration` and `kind: optional`. These are silent and fully working at this hop:
  - `migration` is a recommended path forward (e.g., `secrets.yml` → `credentials.yml.enc`) with no warning today.
  - `optional` is an opt-in feature or improvement that can be safely ignored.

Within each bucket, sub-order by `priority` (HIGH → MEDIUM → LOW). Priority drives urgency *within the bucket*; `kind` drives the bucket itself.

Structure findings as:

```
findings = {
  fix_before_bump: {  # kind: breaking and deprecation
    high_priority:   [...entries...],
    medium_priority: [...entries...],
    low_priority:    [...entries...]
  },
  fix_when_ready: {   # kind: migration and optional
    high_priority:   [...entries...],
    medium_priority: [...entries...],
    low_priority:    [...entries...]
  },
  summary: {
    total_issues: 5,
    breaking_count: 2,
    deprecation_count: 2,
    migration_count: 1,
    optional_count: 0,
    affected_files: ["Gemfile", "config/initializers/assets.rb", ...]
  }
}
```

Each entry retains its individual fields plus `kind` and `priority`:

```
{
  name: "Sprockets usage",
  kind: "migration",
  priority: "high_priority",
  explanation: "Rails 8.0 replaces Sprockets with Propshaft",
  fix: "Migrate to Propshaft or keep Sprockets explicitly",
  occurrences: 3,
  files: [
    { path: "Gemfile", line: 16, content: "gem 'sprockets-rails'" },
    { path: "config/initializers/assets.rb", line: 5, content: "config.assets.compile = true" },
    { path: "config/application.rb", line: 23, content: "require 'sprockets/railtie'" }
  ]
}
```

A HIGH `deprecation` (silently wrong, like `DIRTY_TRACKING_AFTER_SAVE`) lands in `fix_before_bump.high_priority` — both because it warns at runtime today and because skipping it now means it becomes a `breaking` hard-break at the next hop. Priority HIGH within the bucket means address before MEDIUM/LOW deprecations or breakings.

---

### Step 5: Read Affected Files for Context

For files with findings, read the full content to:
- Understand surrounding code
- Provide accurate OLD vs NEW examples
- Identify custom code that needs ⚠️ warnings

Use Read tool:
```
Read:
  file_path: "/path/to/project/config/initializers/assets.rb"
```

---

### Step 6: Return Findings

Pass structured findings to the report generation step.

---

## Tool Usage Examples

### Using Grep for Pattern Search

**Search for a specific pattern:**
```
Grep:
  pattern: "config\\.assets\\."
  path: "config/environments/"
  output_mode: "content"
  -n: true
```

**Search with exclusion (grep -v equivalent):**
Run the search, then filter results in analysis.

**Search multiple paths:**
Make separate Grep calls for each path, or use a parent directory.

### Using Glob to Find Files

**Find all Ruby files in config:**
```
Glob:
  pattern: "config/**/*.rb"
```

**Find specific file types:**
```
Glob:
  pattern: "app/models/**/*.rb"
```

### Using Read for Full Context

**Read a specific file:**
```
Read:
  file_path: "/absolute/path/to/file.rb"
```

---

## Pattern File Format Reference

```yaml
version: "8.0"
description: "Breaking change patterns for Rails 7.2 → 8.0 upgrade"

upgrade_findings:
  high_priority:
    - name: "Human-readable name"
      kind: "breaking"  # one of: breaking | deprecation | migration | optional
      pattern: "regex pattern"
      exclude: "exclusion pattern (optional)"
      search_paths:
        - "path/to/search"
        - "another/path"
      explanation: "Why this is a breaking change"
      fix: "How to fix it"
      variable_name: "UNIQUE_NAME"  # For reference

  medium_priority:
    - name: "Another pattern"
      # same structure
```

The `kind` field determines the output bucket (fix-before-bump vs fix-when-ready). See `CLAUDE.md` → "Assigning `kind:`" for the full rubric and decision flow.

---

## Handling Search Results

### When Pattern Found

1. Record the finding with file:line reference
2. Note the matching content
3. Add to findings list
4. Continue to next pattern

### When Pattern Not Found

1. Pattern is "clear" - no issues for this check
2. Don't include in findings (or include as "✅ None found")
3. Continue to next pattern

### When Search Errors

1. Log the error
2. Note which check couldn't be performed
3. Continue with other patterns
4. Report incomplete checks to user

---

## Output Format

Present findings grouped by `kind` (fix-before-bump vs fix-when-ready), with `priority` driving sub-ordering inside each bucket:

```markdown
## Detection Results

### 🛑 Fix Before Bump (4 found)

These are `kind: breaking` and `kind: deprecation` — they either block the upgrade outright or warn at runtime today (and typically become `breaking` at the next hop). Address them in the same upgrade campaign.

#### HIGH

##### 1. update_attributes removed
**Kind:** `breaking` · **Priority:** HIGH
**Explanation:** Rails 6.1 removes `update_attributes` — calls raise `NoMethodError`
**Fix:** Replace `record.update_attributes(...)` with `record.update(...)`

**Found in:**
- `app/controllers/posts_controller.rb:42` - `@post.update_attributes(post_params)`
- `app/services/comment_updater.rb:18` - `comment.update_attributes!(attrs)`

##### 2. ActiveModel::Dirty methods after save
**Kind:** `deprecation` · **Priority:** HIGH
**Explanation:** Rails 5.2 emits a deprecation warning when `*_changed?` / `*_was` are called post-save (silently returns `false`/`nil`); becomes `breaking` at a later hop
**Fix:** Migrate to `saved_change_to_*` / `attribute_before_last_save` for post-save reads

**Found in:**
- `app/models/user.rb:78` - `if name_changed?` (inside `after_commit`)

#### MEDIUM
...

### 📅 Fix When Ready (1 found)

These are `kind: migration` and `kind: optional` — silent and fully working at this hop. Addressing them is recommended but not tied to the upgrade boundary.

#### MEDIUM

##### 1. Rails.application.secrets usage
**Kind:** `migration` · **Priority:** MEDIUM
**Explanation:** `Rails.application.secrets` still works at 5.2 with no warning; `credentials.yml.enc` is the recommended path forward
**Fix:** Run `rails credentials:edit`, migrate readers to `Rails.application.credentials.*`

**Found in:**
- `config/initializers/api.rb:3` - `Rails.application.secrets.api_key`

### Summary
- Total findings: 5
- By kind: 2 breaking, 2 deprecation, 1 migration, 0 optional
- By priority: 3 HIGH, 2 MEDIUM, 0 LOW
- Affected files: 4
```

**Why two buckets?** The user reads detection output to decide what to fix when. Putting `breaking` and `deprecation` together as "fix before bump" reflects the practical truth: deprecations warn in production logs at this hop and become hard breaks at the next, so addressing them in the same campaign is cheaper than splitting the work across two upgrades. `migration` and `optional` are silent at this hop — they don't compete for the user's attention during the upgrade itself.

---

## Integration with Report Generation

After detection completes:

1. Pass findings to `workflows/upgrade-report-workflow.md`
2. Pass config file contents to `workflows/app-update-preview-workflow.md`
3. Generate both reports using actual findings
4. Present to user

---

## Performance Considerations

- Run Grep calls in parallel when possible (multiple tool calls in one message)
- Use specific paths rather than searching entire codebase
- Limit context lines to what's needed
- Don't read files unnecessarily - only read what's needed for reports

---

## Quality Checklist

Before proceeding to report generation:

- [ ] All patterns from version YAML file processed
- [ ] High, medium, and low priority patterns all checked
- [ ] Findings include file:line references
- [ ] Affected file contents read for context
- [ ] Findings grouped into the two buckets: `fix_before_bump` (`kind: breaking` and `deprecation`) vs `fix_when_ready` (`kind: migration` and `optional`)
- [ ] Within each bucket, sub-ordered by priority (HIGH → MEDIUM → LOW)
- [ ] Each finding tagged with both its `kind` and `priority` in the output
- [ ] Any search errors noted

---
