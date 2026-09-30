# Workflow 05: Detect Breaking Changes

**Purpose:** Run every detection pattern for the hop with `detection-scripts/scan_patterns.rb`, then read the affected files with Claude's tools (Read, Grep, Glob)

**When to use:** Workflow 05 of the upgrade workflow — after tests pass and the upgrade path is validated. (load_defaults alignment is Workflow 12, *after* detection, not before.)

## Inputs

- `detection-scripts/patterns/rails-{VERSION}-patterns.yml`
- `version-guides/upgrade-{FROM}-to-{TO}.md` for context

## Outputs

- `tmp/pattern-scan.json`: the scanner's JSON for this hop (per pattern: status, kind, priority, explanation, fix, `prereqs:`, sites with file:line; a `summary` block with the counts). Absent when the scanner could not run. Workflow 08 fills the report from it
- A findings review note: sites dropped as false positives in Step 3 (pattern, file:line, why) and the prereq gem bumps from Step 1
- All findings compiled into structured data, with file paths and line numbers, grouped by `kind` and sub-ordered by `priority`

## Gates (must be true before the next workflow that runs)

- Every pattern in the patterns file searched: by `detection-scripts/scan_patterns.rb`, or by hand with the Grep tool when the script cannot run
- Every UNSCANNED entry the script reports is either confirmed absent from this app or searched by hand

---

## Step-by-Step Workflow

### Step 1: Load Pattern File

When the scanner runs (Step 2), skip reading this file: the scanner loads it, and its output carries each pattern's name, kind, priority, explanation and fix. Read it only for the Grep fallback, or to look at one pattern's regex; the JSON carries `prereqs:` too. The version-specific pattern file:

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

### Step 2: Run the Scanner

From the app root, run the scanner with the app's Ruby (it is stdlib only and runs on Ruby 2.1 and later, so no Bundler is needed):

```bash
ruby <skill>/detection-scripts/scan_patterns.rb --format json --output tmp/pattern-scan.json
ruby <skill>/detection-scripts/scan_patterns.rb --summary
```

The JSON file is the record Workflow 08 reads. `--output` creates `tmp/` if the app has none, deletes any earlier file first and writes the new one only when the scan succeeds, so after a failed run there is no file rather than a stale or empty one. Read the `--summary` output here, not the full detail: on a large app the full markdown runs to tens of thousands of tokens. For the per-site table of the patterns that fired, run `--only VAR1,VAR2` for a few at a time.

`<skill>` is this skill's directory, the one holding `SKILL.md`. With no arguments the script reads the current Rails version from `Gemfile.lock` and scans the next hop listed in `version-guides/` (4.0 -> 4.1). `Gemfile.lock` stays on the current version while `Gemfile.next.lock` carries the target, so the default is right for the usual flow. Pass `--target X.Y` when `Gemfile.lock` already pins the target version, or to scan a later hop of a multi-hop plan. When the next hop has no patterns file (6.0 -> 6.1), or no version guide starts at the current version (3.1), the script stops and says so rather than scanning another hop's patterns. The report header and the JSON `from` are the start of the hop being scanned, taken from the version guide that ends at the target, so `--target 7.0` reads 6.1 -> 7.0 whatever `Gemfile.lock` pins.

Without `--summary` the output is markdown:

- a **Summary** table, one row per pattern that matched, with bucket, priority, kind, sites and files, already ordered the way Step 4 groups findings;
- one section per matched pattern with its `fix:` and a `file:line | code` table;
- **Scanned clean**: patterns whose search_paths had files and no match;
- **Suppressed by exclude**: sites the pattern matched that `exclude:` dropped;
- **UNSCANNED**: patterns whose search_paths resolved to no files in this app. A path-based pattern (`pattern: ""`, such as `VENDOR_PLUGINS`) is never UNSCANNED: its path being absent is the clean answer.

Flags: `--summary` prints only the summary and the status lists; `--only VAR1,VAR2` prints the per-site detail for those patterns only; `--explain VAR1,VAR2` prints those patterns' explanation, fix and `prereqs:` plus the text of each one's guide entry (or, for a guide without `**Pattern:**` markers yet, a line-numbered index of its entries), without scanning; `--format json` prints a `summary` block (patterns checked and fired, sites, files, counts by kind, unscanned and fully suppressed patterns) and one object per pattern with its bucket, status (`found` / `clean` / `suppressed` / `unscanned`), explanation, fix, `prereqs:`, sites and `guide_entry` (the guide file, heading and line range of the entry whose `**Pattern:**` marker names it, or `null` while that guide has no markers); `--show-suppressed` lists every suppressed site.

The scanner matches against file content, so a call split across lines is found when the pattern is written to cross newlines. It also searches Packwerk packs, engines and components (`app/models/` also reaches `packs/*/app/models/`) and skips `node_modules` anywhere and `vendor`, `tmp` and `log` at the app or pack root, unless a search_path names them. A site that spans lines is reported as `file:start-end`.

If Ruby cannot run in the app's environment at all, fall back to the Grep tool: for every pattern in `upgrade_findings.high_priority`, `medium_priority` and `low_priority`, run one Grep per search_path with `output_mode: "content"` and `-n: true`, then drop lines that match `exclude:`. Grep is line-based, so its counts are a floor for patterns that span lines. Grep rejects look-around (`(?=`, `(?!`, `(?<=`, `(?<!`) and, without `multiline: true`, a `\n`, with a parse error rather than zero hits: split such a pattern at its top-level `|`, drop the look-around from the alternatives that carry it, and read each of the broader hits.

---

### Step 3: Check What the Scanner Could Not See

- **UNSCANNED** is "could not scan", not "clean". For each one, confirm the path does not exist in this app (a Gemfile-only pattern in an app without that file) or Grep the app's real layout by hand.
- **Suppressed by exclude**: `exclude:` is tested on the lines a match spans, so a real hit that shares a line with the excluded form is dropped with it. Re-run with `--show-suppressed` when the count is non-zero and look at any entry whose excluded form can sit next to a real hit.
- **False positives**: a pattern flags text, not behavior. Read the matched line before carrying a site into the report (Step 5), and drop sites that are not the API the pattern describes (a method that only shares a name prefix, a comment, a string). Record each dropped site (pattern, file:line, why) in the findings review note; do not edit the JSON. Workflow 08 reports the kept sites and says how many were dropped.

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

Pull context per finding, not in bulk:

- What the change is: `--explain VAR` (explanation, fix, prereqs, and the guide entry itself when the guide names the pattern in a `**Pattern:**` marker). The markdown report also shows a `Guide:` line with that entry's line range. For a guide without markers yet, `--explain` lists every entry of `version-guides/upgrade-{FROM}-to-{TO}.md` with its line range instead, so Read only the matching one with `offset` / `limit`.
- The app's code: read around each site (`offset` / `limit` near the reported line), and the whole file only when the change depends on more of it (an initializer, a model's callbacks).

Read the app's code to:
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

Pass `tmp/pattern-scan.json` and the findings review note (dropped false positives, prereq gem bumps from Step 1, anything found by hand in Step 3) to the report generation step. When the scanner could not run (Grep fallback, or a hop with no patterns file), pass the Grep findings compiled as in Step 4 instead, and say why the scanner did not run.

---

## Tool Usage Examples (Grep fallback and Step 5)

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

1. Pass findings to `workflows/08-generate-upgrade-report-workflow.md`
2. Pass config file contents to `workflows/09-generate-app-update-preview-workflow.md`
3. Generate both reports using actual findings
4. Present to user

---

## Performance Considerations

- Run the scanner once per hop instead of one Grep call per pattern and path
- When falling back to Grep, run the calls in parallel (multiple tool calls in one message)
- Use specific paths rather than searching entire codebase
- Limit context lines to what's needed
- Don't read files unnecessarily - only read what's needed for reports

---

## Self-review checklist

Before proceeding to report generation:

- [ ] All patterns from version YAML file processed
- [ ] High, medium, and low priority patterns all checked
- [ ] Findings include file:line references
- [ ] Affected file contents read for context
- [ ] Findings grouped into the two buckets: `fix_before_bump` (`kind: breaking` and `deprecation`) vs `fix_when_ready` (`kind: migration` and `optional`)
- [ ] Within each bucket, sub-ordered by priority (HIGH → MEDIUM → LOW)
- [ ] Each finding tagged with both its `kind` and `priority` in the output
- [ ] Any search errors noted
- [ ] Scanner run for the right hop (or Grep used for every pattern when it could not run)
- [ ] UNSCANNED entries confirmed absent or searched by hand
- [ ] Context captured for each finding

---
