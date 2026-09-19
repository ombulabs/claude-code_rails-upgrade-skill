# Workflow 03: Validate Upgrade Path

**Purpose:** Confirm the requested upgrade is a single hop or a planned sequence of hops. Version skipping is not allowed.

**When to use:** After Workflow 02, before dual-boot setup (Workflow 04), so the hop is settled before `Gemfile.next` pins anything.

## Inputs

- Exact current Rails version (from Workflow 00)
- Target Rails version (from the user)

## Outputs

- Single-hop or multi-hop decision
- The list of individual hops, in order

## Gates (must be true before the next workflow that runs)

- Every hop is one adjacent minor/major step

## Step 1: Check if upgrade is single-hop or multi-hop

Compare the exact current version (Workflow 00) with the target the user named. One adjacent minor or major step (7.0 to 7.1, 7.2 to 8.0) is a single hop. Anything further (5.2 to 8.1) is multi-hop. Read `references/sequential-strategy-reference.md` for the supported paths table and the Ruby requirement of each hop.

## Step 2: If multi-hop, explain sequential requirement

Tell the user that Rails upgrades MUST follow a sequential path and that version skipping is not allowed, with the examples from `references/sequential-strategy-reference.md` (5.2 to 6.1 skips 6.0; 7.0 to 8.0 skips 7.1 and 7.2). Then: break it into individual hops, generate separate reports for each hop, and recommend completing each hop fully before moving to the next.

## Step 3: Plan individual hops

List the hops in order (e.g. 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1). For each hop note the Ruby requirement from the supported paths table. For the hop-by-hop plan, milestones and time budget, read `references/multi-hop-strategy-reference.md`, section "Planning a Multi-Hop Upgrade". Workflows 04 to 12 then run once per hop; Workflows 01 and 02 run again at the start of every hop.
