# Workflow 11: Align load_defaults

**Purpose:** Align `load_defaults` to the new Rails version, one config change at a time, after the version bump is complete.

**When to use:** THIS STEP HAPPENS AFTER THE UPGRADE IS COMPLETE. In a multi-hop upgrade, after each hop, align load_defaults to the new version before starting the next hop.

## Inputs

- App running on the target Rails version with tests green

## Outputs

- `load_defaults` aligned to the new version, consolidated into `config/application.rb`

## Gates (must be true before the next workflow that runs)

- Tests green after each config change

## Step 1: Delegate to the rails-load-defaults skill

DELEGATE to the rails-load-defaults skill

## Step 2: Walk through each config change

That skill walks through each config change one at a time, grouped by risk tier

## Step 3: Re-run tests between each change

## Step 4: Consolidate

Consolidates into config/application.rb when done
