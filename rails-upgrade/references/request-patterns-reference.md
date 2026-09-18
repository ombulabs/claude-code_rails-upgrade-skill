# Request Patterns Reference

**When to read this:** At the start of a session, to classify the user's request and decide which workflows run. Every row is a workflow from the index in `SKILL.md`; every column is a request shape.

| Pattern | User says |
|---------|-----------|
| **Full Upgrade Request** | "Upgrade my Rails app to 8.1" |
| **Multi-Hop Request** | "Help me upgrade from Rails 5.2 to 8.1" |
| **Breaking Changes Analysis Only** | "What breaking changes affect my app for Rails 8.0?" |

| Workflow | Full Upgrade | Multi-Hop | Analysis Only |
|----------|--------------|-----------|---------------|
| 00 Verify latest patch | run, MANDATORY | run, MANDATORY. This check applies at the START and again after each hop | run. Check if on latest patch — warn if not, recommend patching first |
| 01 Run test suite | run, MANDATORY. If tests FAIL → STOP and help fix tests first | run, MANDATORY. Run test suite BEFORE planning any upgrade work | run, MANDATORY. If tests fail → Warn user and recommend fixing first. If tests pass → Proceed with analysis |
| 02 Set up next_rails | run | run (if not already set up). Dual-boot stays active throughout the multi-hop process | skip |
| 03 Validate upgrade path | run | run. Explain sequential requirement, calculate hops (e.g. 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1), see `references/multi-hop-strategy-reference.md` | skip |
| 04 Detect breaking changes | run | run, per hop | run. Present findings summary, offer to generate full upgrade report |
| 05 Check gem compatibility | run | run, per hop | skip |
| 06 Boot smoke test | run | run, per hop | skip |
| 07 Generate upgrade report | run | run, per hop | only if the user accepts the offer |
| 08 Generate app:update preview | run | run, per hop | skip |
| 09 Implement and upgrade | run | run, per hop. After first hop complete, repeat for next hops | skip |
| 10 Sync CI config | run | run, per hop | skip |
| 11 Align load_defaults | run, FINAL | run, per hop. **IMPORTANT:** After each hop, align load_defaults to the new version before starting the next hop | skip |
| 12 Mention cleanup | run | run, after the last hop | skip |

Analysis Only intentionally skips Step 2 (Dual-Boot setup) and Step 3 (Validate Upgrade Path) because the user is not yet committing to an upgrade.
