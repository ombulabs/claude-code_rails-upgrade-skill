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
- `kind` is one of `breaking` / `deprecation` / `migration` / `optional` — see `CLAUDE.md` → "Assigning `kind:`" for the rubric. The bucket each finding lands in (see Step 4 / Output Format) is driven by `kind`, not by priority.

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

- **Fix before bump** — `kind: breaking`. The user cannot complete the upgrade without addressing these (raises, removed APIs, won't boot, silently wrong production behavior).
- **Fix when ready** — `kind: deprecation` / `migration` / `optional`. These can be addressed during or shortly after the upgrade without blocking it.

Within each bucket, sub-order by `priority` (HIGH → MEDIUM → LOW). Priority drives urgency *within the bucket*; `kind` drives the bucket itself.

Structure findings as:

```
findings = {
  fix_before_bump: {  # kind: breaking
    high_priority:   [...entries...],
    medium_priority: [...entries...],
    low_priority:    [...entries...]
  },
  fix_when_ready: {   # kind: deprecation, migration, optional
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

A HIGH `deprecation` (silently wrong, like `DIRTY_TRACKING_AFTER_SAVE`) lands in `fix_when_ready.high_priority` — the bucket reflects what kind of change it is; the priority HIGH still tells the user to address it first within that bucket.

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

### 🛑 Fix Before Bump (2 found)

These are `kind: breaking` — the upgrade cannot complete cleanly until they are addressed.

#### HIGH

##### 1. update_attributes removed
**Kind:** `breaking` · **Priority:** HIGH
**Explanation:** Rails 6.1 removes `update_attributes` — calls raise `NoMethodError`
**Fix:** Replace `record.update_attributes(...)` with `record.update(...)`

**Found in:**
- `app/controllers/posts_controller.rb:42` - `@post.update_attributes(post_params)`
- `app/services/comment_updater.rb:18` - `comment.update_attributes!(attrs)`

#### MEDIUM
...

### 📅 Fix When Ready (3 found)

These are `kind: deprecation` / `migration` / `optional` — the upgrade can land without addressing them, but the user should plan to.

#### HIGH

##### 1. ActiveModel::Dirty methods after save
**Kind:** `deprecation` · **Priority:** HIGH
**Explanation:** Rails 5.2 emits a deprecation warning when `*_changed?` / `*_was` are called post-save (silently returns `false`/`nil`)
**Fix:** Migrate to `saved_change_to_*` / `attribute_before_last_save` for post-save reads

**Found in:**
- `app/models/user.rb:78` - `if name_changed?` (inside `after_commit`)

#### MEDIUM

##### 1. Rails.application.secrets usage
**Kind:** `migration` · **Priority:** MEDIUM
...

### Summary
- Total findings: 5
- By kind: 2 breaking, 2 deprecation, 1 migration, 0 optional
- By priority: 3 HIGH, 2 MEDIUM, 0 LOW
- Affected files: 4
```

**Why two buckets?** The user reads detection output to decide what to fix when. Mixing breaking changes (must fix now) with deprecations and opt-in features (can fix later) buries the urgent signal. The kind grouping puts the "this blocks your upgrade" findings at the top, regardless of priority. Priority then controls order within each bucket.

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
- [ ] Findings grouped into the two buckets: `fix_before_bump` (`kind: breaking`) vs `fix_when_ready` (`kind: deprecation` / `migration` / `optional`)
- [ ] Within each bucket, sub-ordered by priority (HIGH → MEDIUM → LOW)
- [ ] Each finding tagged with both its `kind` and `priority` in the output
- [ ] Any search errors noted

---
