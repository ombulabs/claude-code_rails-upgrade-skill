# Workflow 03: Validate Upgrade Path and Ruby Compatibility

**Purpose:** Confirm the requested upgrade is a single hop or a planned sequence of hops, and that the app's Ruby meets the target Rails version's minimum. Version skipping is not allowed, and a Ruby upgrade is its own project that comes before the Rails hop, not inside it.

**When to use:** After Workflow 02, before dual-boot setup (Workflow 04), so the hop and the Ruby are settled before `Gemfile.next` pins anything.

## Inputs

- Exact current Rails version (from Workflow 01)
- Target Rails version (from the user)
- The app's Ruby version (`.ruby-version`, `.tool-versions` or the `ruby` line in `Gemfile`)

## Outputs

- Single-hop or multi-hop decision
- The list of individual hops, in order
- Ruby verdict: current Ruby meets the target hop's minimum, or a Ruby upgrade is required first

## Gates (must be true before the next workflow that runs)

- Every hop is one adjacent minor/major step
- Current Ruby is at or above the target hop's minimum (Ruby Required column of the supported paths table). If it is not, STOP: recommend the Ruby upgrade first and do not start Workflow 04

## Step 1: Check if upgrade is single-hop or multi-hop

Compare the exact current version (Workflow 01) with the target the user named. One adjacent minor or major step (7.0 to 7.1, 7.2 to 8.0) is a single hop. Anything further (5.2 to 8.1) is multi-hop. Read `references/sequential-strategy-reference.md` for the supported paths table and the Ruby requirement of each hop.

## Step 2: If multi-hop, explain sequential requirement

Tell the user that Rails upgrades MUST follow a sequential path and that version skipping is not allowed, with the examples from `references/sequential-strategy-reference.md` (5.2 to 6.1 skips 6.0; 7.0 to 8.0 skips 7.1 and 7.2). Then: break it into individual hops, generate separate reports for each hop, and recommend completing each hop fully before moving to the next.

## Step 3: Plan individual hops

List the hops in order (e.g. 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1). For each hop note the Ruby requirement from the supported paths table. For the hop-by-hop plan, milestones and time budget, read `references/multi-hop-strategy-reference.md`, section "Planning a Multi-Hop Upgrade". Workflows 04 to 12 then run once per hop; Workflows 01 and 02 run again at the start of every hop.

## Step 4: Review Ruby compatibility

Read the app's Ruby version and compare it with the Ruby Required column for the target hop in `references/sequential-strategy-reference.md`. Three outcomes:

- Current Ruby meets the minimum: record it and continue.
- Current Ruby is below the minimum: STOP. Tell the user the Rails hop needs Ruby X.Y first, and that a Ruby upgrade is done and shipped on the current Rails version before this workflow resumes (one moving part at a time). Do not start Workflow 04.
- Current Ruby is newer than what the current Rails version was released against (for example Ruby 3.4 on Rails 7.0): note it. Stdlib gems that moved out of the default set may already be declared in the Gemfile; keep them through the hop.
