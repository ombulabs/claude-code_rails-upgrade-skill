# Workflow 13: Mention Cleanup

**Purpose:** Tell the user the cleanup option exists once the upgrade has shipped. Cleanup ends the campaign; between hops the user usually wants to keep dual-boot in place.

**When to use:** USER-TRIGGERED. DO NOT AUTO-RUN. Mention it; let the user decide.

## Inputs

- Upgrade shipped, `load_defaults` aligned

## Outputs

- User informed of the cleanup option
- Delegation to the `upgrade-cleanup` plugin only if the user explicitly asks

## Gates (must be true before the next workflow that runs)

- None. This is the last workflow.

## Step 1: Tell the user the cleanup option exists

**Sample wording the agent can crib from when prompting the user:**

> Rails X.Y is in. When you're ready to remove dual-boot scaffolding (drop `NextRails.next?` / `NextRails.current?` branches, retire `Gemfile.next`), ask me to clean up. If you're heading straight to the next hop, keeping dual-boot in place is also fine.

## Step 2: Delegate only on explicit request

Delegate to the upgrade-cleanup plugin only when the user explicitly asks ("finish the upgrade", "clean up dual-boot", "drop the NextRails branches")

## Step 3: What cleanup covers

The cleanup plugin removes NextRails.next? / NextRails.current? branches and retires dual-boot scaffolding. Deprecation triage stays with this skill for the next hop, not with cleanup.
