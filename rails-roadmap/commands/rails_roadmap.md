---
description: Survey a Rails app and write RAILS_ROADMAP.md — every action step needed to reach the latest Ruby and Rails, hop by hop. Read-only; changes no application code.
argument-hint: "[target-rails-version]"
allowed-tools: Read, Grep, Glob, WebFetch, Write, Bash(bundle_report:*), Bash(bundle:*), Bash(curl:*), Bash(git status:*), Bash(git rev-parse:*), Bash(ls:*), Bash(cat:*)
---

The user wants a roadmap: what it would take to bring this application to the latest
Ruby and Rails, without starting the work.

Follow `workflows/roadmap-orchestration-workflow.md` end to end. It sequences the other
workflows and assembles the document.

If the user passed a target version (e.g. `/rails-roadmap 8.0`), treat it as the
destination instead of "latest". Otherwise resolve the latest stable Rails and Ruby at
runtime.

## The one rule that matters

**This command is read-only with respect to the application.** It surveys; it does not
upgrade. It must never:

- edit, create, or delete any application file
- run `bundle install`, `bundle update`, or anything else that rewrites `Gemfile.lock`
- set up dual-boot, apply a fix, or bump a version

The single exception is the deliverable itself: `RAILS_ROADMAP.md` in the project root.
That is the only path this command may write, and only under the rules in Step 8 of the
orchestration workflow (which require diffing against an existing file rather than
overwriting it).

`allowed-tools` above withholds `Edit` and constrains Bash, but it cannot express "Write
exactly one path". That constraint is yours to honour.

If the user actually wants to *perform* an upgrade rather than plan one, stop and point
them at the `rails-upgrade` plugin instead.
