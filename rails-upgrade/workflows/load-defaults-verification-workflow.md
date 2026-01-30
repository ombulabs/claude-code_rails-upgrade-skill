# load_defaults Verification Workflow

**Purpose:** Verify that `load_defaults` matches the current Rails gem version BEFORE attempting any upgrade

**When to use:** MANDATORY second step for ALL upgrade requests - after test suite passes

---

## Why This Step is Critical

The FastRuby.io methodology requires your `load_defaults` to match your current Rails version before upgrading:

1. **Ensures Full Compatibility** - You're using all the defaults for your current version
2. **Prevents Compounding Issues** - Don't carry old defaults into a new Rails version
3. **Isolates Problems** - If something breaks, you know which version's defaults caused it
4. **Smoother Upgrades** - Each hop starts from a clean, current baseline

**Example Problem:**
- App is on Rails 8.0.2 with `load_defaults 7.2`
- User wants to upgrade to Rails 8.1
- If we upgrade directly, user would be jumping from 7.2 defaults → 8.1 defaults
- This skips 8.0 defaults, making it harder to identify breaking changes

---

## Step-by-Step Workflow

### Step 1: Detect Rails Gem Version

Read the current Rails gem version from Gemfile.lock:

```bash
# Extract Rails version from Gemfile.lock
grep "rails (" Gemfile.lock | head -1 | sed 's/.*(\(.*\))/\1/'
```

**Or read from Gemfile:**
```ruby
# Gemfile
gem "rails", "8.0.2"
```

Store as: `RAILS_GEM_VERSION` (e.g., "8.0.2" → major.minor = "8.0")

---

### Step 2: Detect load_defaults Version

Read `config/application.rb` to find `load_defaults`:

```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    config.load_defaults 7.2  # ← This is what we're looking for
    # ...
  end
end
```

**Pattern to search:**
```
config.load_defaults X.Y
```

Store as: `LOAD_DEFAULTS_VERSION` (e.g., "7.2")

---

### Step 3: Compare Versions

Compare the major.minor versions:

| Rails Gem | load_defaults | Status | Action |
|-----------|---------------|--------|--------|
| 8.0.x | 8.0 | ✅ Aligned | Proceed with upgrade |
| 8.0.x | 7.2 | ⚠️ Behind | Recommend update first |
| 8.0.x | 7.0 | ⚠️ Far Behind | Strongly recommend update |
| 7.2.x | 7.2 | ✅ Aligned | Proceed with upgrade |
| 7.2.x | 7.0 | ⚠️ Behind | Recommend update first |

**Comparison Logic:**
```
if LOAD_DEFAULTS_VERSION < RAILS_GEM_VERSION.major_minor:
    status = "BEHIND"
    action = "RECOMMEND_UPDATE"
elif LOAD_DEFAULTS_VERSION == RAILS_GEM_VERSION.major_minor:
    status = "ALIGNED"
    action = "PROCEED"
else:
    status = "AHEAD"  # Unusual - load_defaults shouldn't be ahead
    action = "INVESTIGATE"
```

---

### Step 4: Handle Mismatch (If load_defaults is Behind)

If `load_defaults` is behind the current Rails version:

#### 4a. Inform the User

```markdown
## load_defaults Version Mismatch Detected

| Setting | Value |
|---------|-------|
| Rails gem version | 8.0.2 |
| load_defaults | 7.2 |
| Status | ⚠️ Behind |

Your application is running Rails **8.0.2** but using `load_defaults **7.2**`.

This means you're not using all the default behaviors introduced in Rails 8.0.
```

#### 4b. Explain the Recommendation

```markdown
### Recommendation

**Update `load_defaults` to 8.0 before upgrading to the next Rails version.**

Why?
1. Ensures you're using all Rails 8.0 defaults before moving to 8.1
2. Makes it easier to identify which version's changes cause issues
3. Follows the FastRuby.io best practice of incremental changes
4. Reduces the "surface area" of changes in each upgrade step

### What Changes with load_defaults 8.0?

Key default changes you'll be adopting:
- `config.active_support.to_time_preserves_timezone = :zone`
- `config.active_record.before_committed_on_all_enrolled_records = true`
- `config.active_record.postgresql_adapter_decode_dates = true`
- `config.active_record.validate_migration_timestamps = true`
- `config.active_job.enqueue_after_transaction_commit = :default`
```

#### 4c. Ask the User

Use the AskUserQuestion tool:

```markdown
**Would you like to update load_defaults to 8.0 first?**

| Option | Description |
|--------|-------------|
| **Yes (Recommended)** | Update load_defaults to 8.0, run tests, then proceed with upgrade |
| **No** | Skip load_defaults update, proceed directly to upgrade (not recommended) |
```

---

### Step 5: If User Chooses YES (Update load_defaults)

#### 5a. Generate load_defaults Update Plan

```markdown
## Updating load_defaults from 7.2 to 8.0

### Step 1: Update config/application.rb

Change:
```ruby
config.load_defaults 7.2
```

To:
```ruby
config.load_defaults 8.0
```

### Step 2: Review New Defaults

The following defaults will now be active:

| Setting | New Default | Previous |
|---------|-------------|----------|
| `to_time_preserves_timezone` | `:zone` | `:offset` |
| `before_committed_on_all_enrolled_records` | `true` | `false` |
| `postgresql_adapter_decode_dates` | `true` | `false` |
| `validate_migration_timestamps` | `true` | `false` |
| `enqueue_after_transaction_commit` | `:default` | `:never` |

### Step 3: Run Test Suite

After updating, run the test suite to verify nothing breaks:

```bash
bundle exec rspec
# or
bundle exec rails test
```

### Step 4: Fix Any Issues

If tests fail, the failures are likely due to:
- Time zone handling changes
- Transaction commit timing in jobs
- PostgreSQL date handling

Fix these issues before proceeding with the Rails version upgrade.
```

#### 5b. Help User Update

1. Make the edit to `config/application.rb`
2. Run the test suite again
3. If tests pass → Proceed with upgrade
4. If tests fail → Help fix the failures first

---

### Step 6: If User Chooses NO (Skip Update)

```markdown
## Proceeding Without load_defaults Update

⚠️ **Warning:** You are choosing to upgrade Rails without first updating load_defaults.

This means:
- You will jump from load_defaults 7.2 → (target version) defaults
- It may be harder to identify which changes cause issues
- This deviates from the recommended FastRuby.io methodology

Proceeding with upgrade assessment...
```

**Action:** Continue to next step in main workflow but log this decision.

---

### Step 7: If Versions are Aligned

```markdown
## load_defaults Verification ✅

| Setting | Value |
|---------|-------|
| Rails gem version | 8.0.2 |
| load_defaults | 8.0 |
| Status | ✅ Aligned |

Your `load_defaults` matches your Rails version. Ready to proceed with upgrade.
```

**Action:** Continue to next step in main workflow.

---

## Output Formats

### Mismatch Detected (Needs User Input)

```markdown
## load_defaults Verification ⚠️

**Mismatch Detected**

| Current State | Value |
|---------------|-------|
| Rails gem | 8.0.2 |
| load_defaults | 7.2 |
| Target upgrade | 8.1 |

### Recommendation

Before upgrading to Rails 8.1, we recommend updating `load_defaults` to **8.0**.

**Why?**
- Your app should use all Rails 8.0 defaults before moving to 8.1
- This isolates changes and makes debugging easier
- Follows FastRuby.io best practices

### What Changes?

| New Default | Description |
|-------------|-------------|
| `to_time_preserves_timezone = :zone` | Time zone handling improved |
| `enqueue_after_transaction_commit = :default` | Jobs enqueue after commit |
| ... | ... |

---

**Would you like to update load_defaults to 8.0 first?**
```

### Aligned (Proceed)

```markdown
## load_defaults Verification ✅

| Setting | Value |
|---------|-------|
| Rails gem | 8.0.2 |
| load_defaults | 8.0 |
| Status | Aligned |

Ready to proceed with upgrade to Rails 8.1.
```

---

## Common Scenarios

### Scenario 1: User on Rails 7.2 with load_defaults 7.0

```
Rails: 7.2.x
load_defaults: 7.0
Target: 8.0

Recommendation:
1. First update load_defaults 7.0 → 7.1
2. Run tests
3. Then update load_defaults 7.1 → 7.2
4. Run tests
5. THEN upgrade Rails 7.2 → 8.0
```

### Scenario 2: User on Rails 8.0 with load_defaults 7.2 (Your Current Case)

```
Rails: 8.0.2
load_defaults: 7.2
Target: 8.1

Recommendation:
1. First update load_defaults 7.2 → 8.0
2. Run tests
3. THEN upgrade Rails 8.0 → 8.1
```

### Scenario 3: Multiple Version Gap

```
Rails: 7.0.x
load_defaults: 5.2
Target: 8.0

Recommendation:
1. This is a significant gap - update load_defaults incrementally:
   5.2 → 6.0 → 6.1 → 7.0
2. Run tests after each update
3. Then proceed with Rails upgrades
```

---

## Integration with Main Workflow

```
┌─────────────────────────────────────────┐
│  Step 1: Test Suite Verification        │
│  (Must pass before continuing)          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Step 2: load_defaults Verification     │
│  (THIS WORKFLOW)                        │
│                                         │
│  ┌─────────────────────────────────────┐│
│  │ Compare Rails gem vs load_defaults  ││
│  └─────────────────────────────────────┘│
│                    │                    │
│       ┌────────────┴────────────┐       │
│       ▼                         ▼       │
│  ┌─────────┐              ┌──────────┐  │
│  │ Aligned │              │ Mismatch │  │
│  └─────────┘              └──────────┘  │
│       │                         │       │
│       │                         ▼       │
│       │              ┌──────────────────┐│
│       │              │ Ask User:        ││
│       │              │ Update first?    ││
│       │              └──────────────────┘│
│       │                    │            │
│       │         ┌──────────┴──────────┐ │
│       │         ▼                     ▼ │
│       │    ┌────────┐           ┌──────┐│
│       │    │  YES   │           │  NO  ││
│       │    └────────┘           └──────┘│
│       │         │                   │   │
│       │         ▼                   │   │
│       │    ┌────────────┐           │   │
│       │    │ Update     │           │   │
│       │    │ load_defaults         │   │
│       │    │ Run tests  │           │   │
│       │    └────────────┘           │   │
│       │         │                   │   │
│       └─────────┴───────────────────┘   │
│                    │                    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Step 3: Validate Upgrade Path          │
│  (Continue main workflow)               │
└─────────────────────────────────────────┘
```

---

## Quality Checklist

Before proceeding past this step:

- [ ] Rails gem version detected correctly
- [ ] load_defaults version detected correctly
- [ ] Comparison performed correctly
- [ ] If mismatch: User informed clearly
- [ ] If mismatch: User asked for preference
- [ ] If updating: Tests re-run after update
- [ ] If updating: All tests pass before proceeding
- [ ] Decision logged for reference

---

## Reference: load_defaults by Version

| Version | Key Defaults Introduced |
|---------|------------------------|
| 5.0 | `belongs_to_required_by_default = true` |
| 5.1 | `form_with_generates_remote_forms = true` |
| 5.2 | `active_storage.queues.analysis/purge = :active_storage_*` |
| 6.0 | `autoloader = :zeitwerk`, `action_view.default_enforce_utf8 = false` |
| 6.1 | `cookies_same_site_protection = :lax`, `action_dispatch.cookies_serializer = :json` |
| 7.0 | `cache_format_version = 7.0`, `partial_inserts = false` |
| 7.1 | `generate_schema_after_migration = true`, `raise_on_missing_translations = true` |
| 7.2 | `run_after_transaction_callbacks_in_order_defined = true` |
| 8.0 | `to_time_preserves_timezone = :zone`, `enqueue_after_transaction_commit = :default` |

---

**This step ensures a clean baseline before each upgrade.**
