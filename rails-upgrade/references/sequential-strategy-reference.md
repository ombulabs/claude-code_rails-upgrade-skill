# Sequential Strategy Reference

**When to read this:** `workflows/03-validate-upgrade-path-workflow.md`, when confirming the upgrade path and planning hops.

## Sequential Upgrade Strategy

### ⚠️ Version Skipping is NOT Allowed

Rails upgrades MUST follow a sequential path. Examples:

**For Rails 5.x to 8.x:**
```
5.0.x → 5.1.x → 5.2.x → 6.0.x → 6.1.x → 7.0.x → 7.1.x → 7.2.x → 8.0.x → 8.1.x
```

**You CANNOT skip versions.** Examples:
- ❌ 5.2 → 6.1 (skips 6.0)
- ❌ 6.0 → 7.0 (skips 6.1)
- ❌ 7.0 → 8.0 (skips 7.1 and 7.2)
- ✅ 5.2 → 6.0 (correct)
- ✅ 7.0 → 7.1 (correct)
- ✅ 7.2 → 8.0 (correct)

If user requests a multi-hop upgrade (e.g., 5.2 → 8.1):
1. Explain the sequential requirement
2. Break it into individual hops
3. Generate separate reports for each hop
4. Recommend completing each hop fully before moving to next

---

## Supported Upgrade Paths

### Legacy Rails (2.3 - 4.2)

| From | To | Key Changes | Ruby Required |
|------|-----|-------------|---------------|
| 2.3.x | 3.0.x | XSS protection, routes syntax | 1.8.7 - 1.9.3 |
| 3.0.x | 3.1.x | Asset pipeline, jQuery | 1.8.7 - 1.9.3 |
| 3.1.x | 3.2.x | Ruby 1.9.3 support | 1.8.7 - 2.0 |
| 3.2.x | 4.0.x | Strong Parameters, Turbolinks | 1.9.3+ |
| 4.0.x | 4.1.x | Spring, secrets.yml | 1.9.3+ |
| 4.1.x | 4.2.x | ActiveJob, Web Console | 1.9.3+ |
| 4.2.x | 5.0.x | ActionCable, API mode, ApplicationRecord | 2.2.2+ |

### Modern Rails (5.0 - 8.1)

| From | To | Key Changes | Ruby Required |
|------|-----|-------------|---------------|
| 5.0.x | 5.1.x | Encrypted secrets, yarn default | 2.2.2+ |
| 5.1.x | 5.2.x | Active Storage, credentials | 2.2.2+ |
| 5.2.x | 6.0.x | Zeitwerk, Action Mailbox/Text | 2.5.0+ |
| 6.0.x | 6.1.x | Horizontal sharding, strict loading | 2.5.0+ |
| 6.1.x | 7.0.x | Hotwire/Turbo, Import Maps | 2.7.0+ |
| 7.0.x | 7.1.x | Composite keys, async queries | 2.7.0+ |
| 7.1.x | 7.2.x | Transaction-aware jobs, DevContainers | 3.1.0+ |
| 7.2.x | 8.0.x | Propshaft, Solid gems, Kamal | 3.2.0+ |
| 8.0.x | 8.1.x | Bundler-audit, max_connections | 3.2.0+ |
