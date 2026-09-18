# Workflow 00: Verify Latest Patch

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

- EOL series (≤ 7.1): use static table in `references/multi-hop-strategy-reference.md`
- Active series (≥ 7.2): query RubyGems API (see `references/multi-hop-strategy-reference.md` for commands)

## Step 3: If current version < latest patch

- INFORM user: "Your app is on Rails X.Y.Z but the latest patch is X.Y.W"
- Guide through Gemfile update and bundle update rails
- Run test suite after patch upgrade
- Deploy patch upgrade before proceeding
- Do NOT proceed to next minor/major until on latest patch

## Step 4: If current version == latest patch

Proceed to Step 1
