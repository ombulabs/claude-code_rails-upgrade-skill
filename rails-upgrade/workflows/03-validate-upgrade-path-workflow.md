# Workflow 03: Validate Upgrade Path

**Purpose:** Confirm the requested upgrade is a single hop or a planned sequence of hops. Version skipping is not allowed.

**When to use:** After dual-boot is set up, before detection.

## Inputs

- Exact current Rails version (from Workflow 00)
- Target Rails version (from the user)

## Outputs

- Single-hop or multi-hop decision
- The list of individual hops, in order

## Gates (must be true before the next workflow that runs)

- Every hop is one adjacent minor/major step

## Step 1: Check if upgrade is single-hop or multi-hop

## Step 2: If multi-hop, explain sequential requirement

## Step 3: Plan individual hops

Reference: `references/sequential-strategy-reference.md` and `references/multi-hop-strategy-reference.md`
