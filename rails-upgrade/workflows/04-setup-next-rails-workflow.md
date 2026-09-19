# Workflow 04: Set Up next_rails Dual-Boot

**Purpose:** Set up dual-boot with next_rails early, right after tests pass, so both Rails versions run during the entire transition.

**When to use:** EARLY SETUP, after Workflow 03 has confirmed the hop and the Ruby. Everything from here on runs on both sides of the dual-boot.

## Inputs

- Green test baseline (or accepted partial smoke baseline) with the current-version deprecations resolved (Workflow 02)
- Result of the deprecation-behavior sweep from `workflows/00-run-test-suite-workflow.md` Step 2
- Hand that result to the delegate skill: its setup workflow opens with a sweep that covers the same ground

## Outputs

- `Gemfile` carrying the `if next?` conditionals (`Gemfile.next` is the symlink `next_rails --init` creates; the branch lives in `Gemfile`)
- Dependencies installed for both Rails versions

## Gates (must be true before the next workflow that runs)

- Dual-boot set up by the `dual-boot` skill
- Both sides boot after the Gemfile change: `bin/rails runner 'puts Rails.version'` prints the current version, and `BUNDLE_GEMFILE=Gemfile.next bin/rails runner 'puts Rails.version'` prints the target version

## Step 1: Delegate to the dual-boot skill

DELEGATE to the dual-boot skill for setup and initialization.
That skill handles:
- Checking if Gemfile.next already exists (to avoid duplicate `next?` method)
- Adding next_rails gem and running next_rails --init
- Installing dependencies for both Rails versions
- Configuring the Gemfile with `if next?` conditionals
