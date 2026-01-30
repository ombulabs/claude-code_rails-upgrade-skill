---
name: rails-upgrade
description: Analyzes Rails applications and generates comprehensive upgrade reports with breaking changes, deprecations, and step-by-step migration guides for Rails 2.3 through 8.1. Use when upgrading Rails applications, planning multi-hop upgrades, or querying version-specific changes. Based on FastRuby.io methodology and "The Complete Guide to Upgrade Rails" ebook.
---

# Rails Upgrade Assistant Skill v2.0

## Skill Identity
- **Name:** Rails Upgrade Assistant
- **Version:** 2.0
- **Purpose:** Intelligent Rails application upgrades from 2.3 through 8.1
- **Based on:** Official Rails CHANGELOGs, FastRuby.io methodology, and the FastRuby.io ebook
- **Upgrade Strategy:** Sequential only (no version skipping)

---

## Core Methodology (FastRuby.io Approach)

This skill follows the proven FastRuby.io upgrade methodology:

1. **Incremental Upgrades** - Always upgrade one minor/major version at a time
2. **Assessment First** - Understand scope before making changes
3. **Dual-Boot Testing** - Test both versions during transition using `next_rails` gem
4. **Test Coverage** - Ensure adequate test coverage before upgrading (aim for 80%+)
5. **Gem Compatibility** - Check gem compatibility at each step using RailsBump
6. **Deprecation Warnings** - Address deprecations before upgrading
7. **Backwards Compatible Changes** - Deploy small changes to production before version bump

**Key Resources:**
- See `reference/dual-boot-strategy.md` for dual-boot setup with `next_rails`
- See `reference/deprecation-warnings.md` for managing deprecations
- See `reference/staying-current.md` for maintaining upgrades over time

---

## Core Workflow (3-Step Process)

### Step 1: Breaking Changes Detection Script
- Claude generates an executable bash script tailored to the specific upgrade
- Script scans the user's codebase for breaking changes
- Finds issues with file:line references
- Generates findings report (TXT file)
- Runs in < 30 seconds

### Step 2: User Runs Script & Shares Findings
- User executes the detection script in their project directory
- Script outputs `rails_{version}_upgrade_findings.txt`
- User shares findings report back with Claude

### Step 3: Claude Generates Reports Based on Actual Findings
- **Comprehensive Upgrade Report**: Breaking changes analysis with OLD vs NEW code examples, custom code warnings with ⚠️ flags, step-by-step migration plan, testing checklist and rollback plan
- **app:update Preview Report**: Shows exact configuration file changes (OLD vs NEW), lists new files to be created, impact assessment (HIGH/MEDIUM/LOW)

---

## Trigger Patterns

Claude should activate this skill when user says:

**Initial Upgrade Requests (Generate Detection Script):**
- "Upgrade my Rails app to [version]"
- "Help me upgrade from Rails [x] to [y]"
- "What breaking changes are in Rails [version]?"
- "Plan my upgrade from [x] to [y]"
- "What Rails version am I using?"
- "Analyze my Rails app for upgrade"
- "Create a detection script for Rails [version]"
- "Generate a breaking changes script"
- "Find breaking changes in my code"

**After Script Execution (Generate Reports):**
- "Here's my findings.txt"
- "I ran the script, here are the results"
- "The detection script found [X] issues"
- "Can you analyze these findings?"
- *User shares/uploads findings.txt file*

**Specific Report Requests (Only After Findings Shared):**
- "Show me the app:update changes"
- "Preview configuration changes for Rails [version]"
- "Generate the upgrade report"
- "Create the comprehensive report"

---

## CRITICAL: Sequential Upgrade Strategy

### ⚠️ Version Skipping is NOT Allowed

Rails upgrades MUST follow a sequential path. Examples:

**For Rails 5.x to 8.x:**
```
5.0.x → 5.1.x → 5.2.x → 6.0.x → 6.1.x → 7.0.x → 7.1.x → 7.2.x → 8.0.x → 8.1.x
```

**You CANNOT skip versions.** Examples:
- ❌ 5.2 → 6.1 (skips 6.0)
- ❌ 6.0 → 7.0 (skips 6.1)
- ❌ 7.0 → 8.0 (skips 7.1 and 7.2)
- ✅ 5.2 → 6.0 (correct)
- ✅ 7.0 → 7.1 (correct)
- ✅ 7.2 → 8.0 (correct)

If user requests a multi-hop upgrade (e.g., 5.2 → 8.1):
1. Explain the sequential requirement
2. Break it into individual hops
3. Generate separate reports for each hop
4. Recommend completing each hop fully before moving to next

---

## Supported Upgrade Paths

### Legacy Rails (2.3 - 4.2)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 2.3.x | 3.0.x | Very Hard | XSS protection, routes syntax | 1.8.7 - 1.9.3 |
| 3.0.x | 3.1.x | Medium | Asset pipeline, jQuery | 1.8.7 - 1.9.3 |
| 3.1.x | 3.2.x | Easy | Ruby 1.9.3 support | 1.8.7 - 2.0 |
| 3.2.x | 4.0.x | Hard | Strong Parameters, Turbolinks | 1.9.3+ |
| 4.0.x | 4.1.x | Medium | Spring, secrets.yml | 1.9.3+ |
| 4.1.x | 4.2.x | Medium | ActiveJob, Web Console | 1.9.3+ |
| 4.2.x | 5.0.x | Hard | ActionCable, API mode, ApplicationRecord | 2.2.2+ |

### Modern Rails (5.0 - 8.1)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 5.0.x | 5.1.x | Easy | Encrypted secrets, yarn default | 2.2.2+ |
| 5.1.x | 5.2.x | Medium | Active Storage, credentials | 2.2.2+ |
| 5.2.x | 6.0.x | Hard | Zeitwerk, Action Mailbox/Text | 2.5.0+ |
| 6.0.x | 6.1.x | Medium | Horizontal sharding, strict loading | 2.5.0+ |
| 6.1.x | 7.0.x | Hard | Hotwire/Turbo, Import Maps | 2.7.0+ |
| 7.0.x | 7.1.x | Medium | Composite keys, async queries | 2.7.0+ |
| 7.1.x | 7.2.x | Medium | Transaction-aware jobs, DevContainers | 3.1.0+ |
| 7.2.x | 8.0.x | Very Hard | Propshaft, Solid gems, Kamal | 3.2.0+ |
| 8.0.x | 8.1.x | Easy | Bundler-audit, max_connections | 3.2.0+ |

---

## Available Resources

### Core Documentation
- `SKILL.md` - This file (entry point)

### Version-Specific Guides (Load as needed)

**Legacy Rails:**
- `version-guides/upgrade-3.2-to-4.0.md` - Rails 3.2 → 4.0 (Strong Parameters)
- `version-guides/upgrade-4.2-to-5.0.md` - Rails 4.2 → 5.0 (ApplicationRecord)

**Modern Rails:**
- `version-guides/upgrade-5.0-to-5.1.md` - Rails 5.0 → 5.1 (Encrypted secrets)
- `version-guides/upgrade-5.1-to-5.2.md` - Rails 5.1 → 5.2 (Active Storage, Credentials)
- `version-guides/upgrade-5.2-to-6.0.md` - Rails 5.2 → 6.0 (Zeitwerk)
- `version-guides/upgrade-6.0-to-6.1.md` - Rails 6.0 → 6.1 (Horizontal sharding)
- `version-guides/upgrade-6.1-to-7.0.md` - Rails 6.1 → 7.0 (Hotwire/Turbo)
- `version-guides/upgrade-7.0-to-7.1.md` - Rails 7.0 → 7.1 (Composite keys)
- `version-guides/upgrade-7.1-to-7.2.md` - Rails 7.1 → 7.2 (Transaction jobs)
- `version-guides/upgrade-7.2-to-8.0.md` - Rails 7.2 → 8.0 (Propshaft)
- `version-guides/upgrade-8.0-to-8.1.md` - Rails 8.0 → 8.1 (bundler-audit)

### Workflow Guides (Load when generating deliverables)
- `workflows/upgrade-report-workflow.md` - How to generate upgrade reports
- `workflows/detection-script-workflow.md` - How to generate detection scripts
- `workflows/app-update-preview-workflow.md` - How to generate app:update previews

### Examples (Load when user needs clarification)
- `examples/simple-upgrade.md` - Single-hop upgrade example
- `examples/multi-hop-upgrade.md` - Multi-hop upgrade example
- `examples/detection-script-only.md` - Detection script only request

### Reference Materials
- `reference/dual-boot-strategy.md` - Dual-boot with next_rails gem
- `reference/deprecation-warnings.md` - Finding and fixing deprecations
- `reference/staying-current.md` - Keeping up with Rails releases
- `reference/breaking-changes-by-version.md` - Quick lookup
- `reference/multi-hop-strategy.md` - Multi-version planning
- `reference/testing-checklist.md` - Comprehensive testing
- `reference/gem-compatibility.md` - Common gem version requirements

### Detection Script Resources
- `detection-scripts/patterns/rails-*.yml` - Version-specific patterns
- `detection-scripts/templates/detection-script-template.sh` - Bash template

### Report Templates
- `templates/upgrade-report-template.md` - Main upgrade report structure
- `templates/app-update-preview-template.md` - Configuration preview

---

## High-Level Workflow

When user requests an upgrade, follow this workflow:

### Step 1: Detect Current Version
```
1. Read Gemfile to find current Rails version
2. Read config/application.rb for load_defaults version
3. Store: current_version, target_version
```

### Step 2: Validate Upgrade Path
```
1. Check if upgrade is single-hop or multi-hop
2. If multi-hop, explain sequential requirement
3. Plan individual hops
```

### Step 3: Load Detection Script Resources
```
1. Read: detection-scripts/patterns/rails-{VERSION}-patterns.yml
2. Read: detection-scripts/templates/detection-script-template.sh
3. Read: workflows/detection-script-workflow.md (for generation instructions)
```

### Step 4: Generate Detection Script
```
1. Follow workflow in detection-script-workflow.md
2. Generate version-specific bash script
3. Deliver script to user
4. Instruct user to run script and share findings.txt
```

### Step 5: Wait for User to Run Script
```
User runs: ./detect_rails_{version}_breaking_changes.sh
Script outputs: rails_{version}_upgrade_findings.txt
User shares findings back with Claude
```

### Step 6: Load Report Generation Resources
```
1. Read: templates/upgrade-report-template.md
2. Read: version-guides/upgrade-{FROM}-to-{TO}.md
3. Read: templates/app-update-preview-template.md
4. Read: workflows/upgrade-report-workflow.md
5. Read: workflows/app-update-preview-workflow.md
```

### Step 7: Analyze User's Actual Findings
```
1. Parse the findings.txt file
2. Extract detected breaking changes and affected files
3. Read user's actual config files for context
4. Identify custom code patterns from findings
```

### Step 8: Generate Reports Based on Findings

**Deliverable #1: Comprehensive Upgrade Report**
- **Workflow:** See `workflows/upgrade-report-workflow.md`
- **Input:** Actual findings from script + version guide data
- **Output:** Report with real code examples from user's project

**Deliverable #2: app:update Preview**
- **Workflow:** See `workflows/app-update-preview-workflow.md`
- **Input:** Actual config files + findings
- **Output:** Preview with real file paths and changes

### Step 9: Present Reports
```
1. Present Comprehensive Upgrade Report first
2. Present app:update Preview Report second
3. Explain next steps
4. Offer to help implement changes
```

---

## Pre-Upgrade Checklist (FastRuby.io Best Practices)

Before starting ANY upgrade:

### 1. Test Coverage Assessment
- [ ] Run test suite - all tests passing?
- [ ] Check test coverage (aim for >70%)
- [ ] Review critical paths have coverage

### 2. Dependency Audit
- [ ] Run `bundle outdated`
- [ ] Check gem compatibility with target Rails version
- [ ] Identify gems that need upgrading first

### 3. Database Backup
- [ ] Backup production database
- [ ] Backup development/staging databases
- [ ] Verify backup restore process works

### 4. Git Branch Strategy
- [ ] Create upgrade branch from main/master
- [ ] Set up CI for upgrade branch
- [ ] Plan merge strategy

### 5. Deprecation Warnings
- [ ] Run app with `RAILS_DEPRECATION_WARNINGS=1`
- [ ] Address existing deprecation warnings
- [ ] Enable verbose deprecations in test environment

---

## Common Request Patterns

### Pattern 1: Full Upgrade Request
**User says:** "Upgrade my Rails app to 8.1"

**Action - Phase 1 (Generate Script):**
1. Detect current version
2. Validate upgrade path
3. Load: `workflows/detection-script-workflow.md`
4. Generate detection script
5. Deliver script with instructions to run it
6. Wait for user to share findings.txt

**Action - Phase 2 (Generate Reports):**
1. Parse findings.txt
2. Load: `workflows/upgrade-report-workflow.md`
3. Load: `workflows/app-update-preview-workflow.md`
4. Generate Comprehensive Upgrade Report (using actual findings)
5. Generate app:update Preview (using actual findings)
6. Reference: `examples/simple-upgrade.md` for structure

### Pattern 2: Multi-Hop Request
**User says:** "Help me upgrade from Rails 5.2 to 8.1"

**Action:**
1. Explain sequential requirement
2. Calculate hops: 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1
3. Reference: `reference/multi-hop-strategy.md`
4. Follow Pattern 1 for FIRST hop (5.2 → 6.0)
5. After first hop complete, repeat for next hops

### Pattern 3: Detection Script Only
**User says:** "Create a detection script for Rails 8.0"

**Action:**
1. Load: `workflows/detection-script-workflow.md`
2. Generate detection script only
3. Reference: `examples/detection-script-only.md`
4. Do NOT generate reports yet (wait for findings)

### Pattern 4: User Returns with Findings
**User says:** "Here's my findings.txt" or shares script output

**Action:**
1. Parse findings.txt
2. Load: `workflows/upgrade-report-workflow.md`
3. Load: `workflows/app-update-preview-workflow.md`
4. Generate Comprehensive Upgrade Report
5. Generate app:update Preview

---

## Quality Checklist

Before delivering, verify:

**For Detection Script:**
- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] Patterns match target Rails version
- [ ] Script includes all breaking changes from pattern file
- [ ] File paths use user's actual project structure
- [ ] User instructions are clear

**After User Runs Script (Before Generating Reports):**
- [ ] Received and parsed findings.txt from user
- [ ] Identified all detected breaking changes
- [ ] Collected affected file paths
- [ ] Noted custom code warnings from findings

**For Comprehensive Upgrade Report:**
- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] Used ACTUAL findings from script (not generic examples)
- [ ] Breaking changes section includes real file:line references
- [ ] Custom code warnings based on actual detected issues
- [ ] Code examples use user's actual code from affected files
- [ ] Next steps clearly outlined

**For app:update Preview:**
- [ ] All {PLACEHOLDERS} replaced with actual values
- [ ] File list matches user's actual config files
- [ ] Diffs based on real current config vs target version
- [ ] Next steps clearly outlined

---

## Key Principles

1. **Always Generate Detection Script First** (unless user only wants reports and has findings)
2. **Wait for User to Run Script** (reports depend on actual findings)
3. **Always Use Actual Findings** (no generic examples in reports)
4. **Always Flag Custom Code** (with ⚠️ warnings based on detected issues)
5. **Always Use Templates** (for consistency)
6. **Always Check Quality** (before delivery)
7. **Load Workflows as Needed** (don't hold everything in memory)
8. **Sequential Process is Critical** (script → findings → reports)
9. **Follow FastRuby.io Methodology** (incremental upgrades, assessment first)

---

## Success Criteria

A successful upgrade assistance session:

✅ Generated detection script (Phase 1)
✅ User ran script and shared findings.txt (Phase 2)
✅ Generated Comprehensive Upgrade Report using actual findings (Phase 3)
✅ Generated app:update Preview using actual findings (Phase 3)
✅ Used user's actual code from findings (not generic examples)
✅ Flagged all custom code with ⚠️ warnings based on detected issues
✅ Provided clear next steps
✅ Offered to help implement changes

---

**Version:** 2.0
**Last Updated:** January 2025
**Skill Type:** Modular with external workflows and examples
**Methodology:** Based on FastRuby.io upgrade best practices and "The Complete Guide to Upgrade Rails" ebook
**Attribution:** Content based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)
