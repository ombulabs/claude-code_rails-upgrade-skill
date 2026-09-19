# Request Patterns Reference

**When to read this:** At the start of a session, to classify the user's request and decide which workflows run. Every row is a workflow from the index in `SKILL.md`; every column is a request shape.

| Pattern | User says |
|---------|-----------|
| **Full Upgrade Request** | "Upgrade my Rails app to 8.1" |
| **Multi-Hop Request** | "Help me upgrade from Rails 5.2 to 8.1" |
| **Breaking Changes Analysis Only** | "What breaking changes affect my app for Rails 8.0?" |
| **Reports Only** | "Upgrade my app to 7.1 but stop once you have presented both reports, I will implement myself" |

| Workflow | Full Upgrade | Multi-Hop | Analysis Only | Reports Only |
|----------|--------------|-----------|---------------|--------------|
| 00 Verify latest patch | run, MANDATORY | run, MANDATORY. This check applies at the START and again after each hop | run. Check if on latest patch — warn if not, recommend patching first | run, MANDATORY |
| 01 Run test suite | run, MANDATORY. If tests FAIL → STOP and help fix tests first | run, MANDATORY. Run test suite BEFORE planning any upgrade work | run, MANDATORY. If tests fail → Warn user and recommend fixing first. If tests pass → Proceed with analysis | run, MANDATORY |
| 02 Resolve deprecation warnings | run | run, per hop | run: collect and report the warnings, apply fixes only if the user agrees | run: collect and inventory; the user said no fixes, so Step 4 is recorded in the report as the first implementation task |
| 03 Validate upgrade path | run | run. Explain sequential requirement, calculate hops (e.g. 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1), see `references/multi-hop-strategy-reference.md` | skip | run |
| 04 Set up next_rails | run | run (if not already set up). Dual-boot stays active throughout the multi-hop process | skip | run. Adding `next_rails` and the `if next?` branch is not the bump the user declined |
| 05 Detect breaking changes | run | run, per hop | run. Present findings summary, offer to generate full upgrade report | run |
| 06 Check gem compatibility | run | run, per hop | skip | run |
| 07 Boot smoke test and models suite | run | run, per hop | skip | run the boot; if it fails, record the required gem bumps in the report instead of editing the Gemfile, since the user will implement |
| 08 Generate upgrade report | run | run, per hop | only if the user accepts the offer. 06 and 07 did not run, so generate the report without the gem compatibility and boot smoke sections and say so in the report | run |
| 09 Generate app:update preview | run | run, per hop | skip | run, then stop. Do not offer to implement; the user already said they will |
| 10 Implement and upgrade | run | run, per hop. After first hop complete, repeat for next hops | skip | skip |
| 11 Sync CI config | run | run, per hop | skip | skip |
| 12 Align load_defaults | run, FINAL | run, per hop. **IMPORTANT:** After each hop, align load_defaults to the new version before starting the next hop | skip | skip |
| 13 Mention cleanup | run | run, after the last hop | skip | skip |

Analysis Only intentionally skips Workflow 04 (Dual-Boot setup) and Workflow 03 (Validate Upgrade Path) because the user is not yet committing to an upgrade. Reports Only is a Full Upgrade that stops after Workflow 09: the user wants both deliverables and will do the implementation, CI sync and load_defaults work themselves.
