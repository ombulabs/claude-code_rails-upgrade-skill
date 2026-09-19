# Workflow 01: Verify Latest Patch

**Purpose:** Ensure the app is on the latest patch of its current Rails series before any minor/major hop. Patch releases contain security fixes, bug fixes, and additional deprecation warnings. Starting the version hop on the latest patch is safer (the security fixes are already in production) and easier to debug (the new deprecation warnings surface issues that would otherwise show up mid-upgrade).

**When to use:** MANDATORY PRE-STEP. THIS STEP IS REQUIRED BEFORE ANY OTHER WORK. For multi-hop upgrades this check applies at the START and again after each hop.

## Inputs

- `Gemfile.lock`

## Outputs

- Exact current Rails version (e.g., 3.2.19)
- Latest patch for that series

## Gates (must be true before the next workflow that runs)

- Current version == latest patch of its series. Do NOT proceed to next minor/major until on latest patch.

## Step 1: Read the exact current version

Read Gemfile.lock to find exact current Rails version (e.g., 3.2.19)

## Step 2: Compare against the latest patch for that series

- Series listed in the End-of-Life table of `references/multi-hop-strategy-reference.md`: use that table
- Any other series: query RubyGems API (see `references/multi-hop-strategy-reference.md` for commands)

## Step 3: If current version < latest patch

- INFORM user: "Your app is on Rails X.Y.Z but the latest patch is X.Y.W"
- Guide through Gemfile update and bundle update rails
- Run test suite after patch upgrade
- Deploy patch upgrade before proceeding
- Do NOT proceed to next minor/major until on latest patch

## Step 4: If current version == latest patch

Proceed to Workflow 00 (`workflows/00-run-test-suite-workflow.md`)
