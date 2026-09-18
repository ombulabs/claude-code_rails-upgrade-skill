# Workflow 02: Set Up next_rails Dual-Boot

**Purpose:** Set up dual-boot with next_rails early, right after tests pass, so both Rails versions run during the entire transition.

**When to use:** EARLY SETUP, after the test suite passes.

## Inputs

- Green test baseline (or accepted partial smoke baseline)
- Result of the deprecation-behavior sweep from `workflows/01-run-test-suite-workflow.md` Step 2. Hand it to the dual-boot skill so it does not repeat its own sweep.

## Outputs

- `Gemfile` carrying the `if next?` conditionals (`Gemfile.next` is the symlink `next_rails --init` creates; the branch lives in `Gemfile`)
- Dependencies installed for both Rails versions

## Gates (must be true before the next workflow that runs)

- Dual-boot set up by the `dual-boot` skill

## Step 1: Delegate to the dual-boot skill

DELEGATE to the dual-boot skill for setup and initialization.
That skill handles:
- Checking if Gemfile.next already exists (to avoid duplicate `next?` method)
- Adding next_rails gem and running next_rails --init
- Installing dependencies for both Rails versions
- Configuring the Gemfile with `if next?` conditionals
