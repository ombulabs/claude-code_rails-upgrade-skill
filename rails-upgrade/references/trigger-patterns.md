# Trigger Patterns

When to activate the `rails-upgrade` skill, and which request pattern applies. Read this when classifying a user request at the start of a session.

## Activation Triggers

**Upgrade requests:**
- "Upgrade my Rails app to [version]"
- "Help me upgrade from Rails [x] to [y]"
- "Plan my upgrade from [x] to [y]"
- "What Rails version am I using?"
- "Analyze my Rails app for upgrade"
- "Check my app for Rails [version] compatibility"

**Analysis-only requests:**
- "What breaking changes are in Rails [version]?"
- "Find breaking changes in my code"
- "Show me the app:update changes"
- "Preview configuration changes for Rails [version]"
- "Generate the upgrade report"
- "What will change if I upgrade?"

---

## Request Pattern → Workflow Mapping

### Pattern 1: Full Upgrade (single hop)

**Trigger:** "Upgrade my Rails app to X.Y"

**Steps:** Full 7-step workflow (Step 0 → Step 6). No shortcuts.

### Pattern 2: Multi-Hop Upgrade

**Trigger:** "Upgrade from 5.2 to 8.1" (spans 2+ minor/major versions)

**Steps:**
1. Run Step 0 (latest patch check) and Step 1 (tests) ONCE at the start
2. Run Step 2 (dual-boot setup) ONCE at the start — stays active across all hops
3. For each hop (e.g., 5.2→6.0, 6.0→6.1, ...):
   - Steps 3–6 in full
   - Re-verify latest patch of the new series before the next hop
4. Reference: `reference/sequential-strategy.md` for hop calculation
5. Reference: `reference/multi-hop-strategy.md` for per-series strategy

### Pattern 3: Breaking Changes Analysis Only

**Trigger:** "What breaking changes affect my app for Rails X.Y?" (no actual upgrade requested)

**Steps:** Step 0 (warn only if not on latest patch) → Step 1 (warn only if tests fail) → Step 3 (detection) → present findings. Skip Steps 2, 4–6.

Offer at the end: "Want the full upgrade report and `app:update` preview?"

### Pattern 4: Version Identification

**Trigger:** "What Rails version am I using?"

**Steps:** Read `Gemfile.lock`, report exact version + latest patch of that series. Recommend Step 0 action if behind.
