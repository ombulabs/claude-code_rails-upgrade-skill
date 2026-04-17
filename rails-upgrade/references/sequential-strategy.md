# Sequential Upgrade Strategy

Read this when planning any upgrade, especially multi-hop. Explains why version-skipping is forbidden and lists supported hops with difficulty and Ruby requirements.

## Rule: No Version Skipping

Rails upgrades MUST follow a sequential path, one minor/major at a time.

**For Rails 5.x → 8.x:**
```
5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1
```

**Forbidden:**
- 5.2 → 6.1 (skips 6.0)
- 6.0 → 7.0 (skips 6.1)
- 7.0 → 8.0 (skips 7.1, 7.2)

**Allowed:**
- 5.2 → 6.0
- 7.0 → 7.1
- 7.2 → 8.0

When a user requests a multi-hop upgrade:
1. Explain the sequential requirement
2. Break into individual hops
3. Generate separate reports per hop
4. Recommend completing each hop fully (ship to prod) before starting the next

See `reference/multi-hop-strategy.md` for per-series details (latest patches, EOL status, Ruby constraints).

---

## Supported Upgrade Paths

### Legacy Rails (2.3 – 4.2)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 2.3.x | 3.0.x | Very Hard | XSS protection, routes syntax | 1.8.7 – 1.9.3 |
| 3.0.x | 3.1.x | Medium | Asset pipeline, jQuery | 1.8.7 – 1.9.3 |
| 3.1.x | 3.2.x | Easy | Ruby 1.9.3 support | 1.8.7 – 2.0 |
| 3.2.x | 4.0.x | Hard | Strong Parameters, Turbolinks | 1.9.3+ |
| 4.0.x | 4.1.x | Medium | Spring, secrets.yml | 1.9.3+ |
| 4.1.x | 4.2.x | Medium | ActiveJob, Web Console | 1.9.3+ |
| 4.2.x | 5.0.x | Hard | ActionCable, API mode, ApplicationRecord | 2.2.2+ |

### Modern Rails (5.0 – 8.1)

| From | To | Difficulty | Key Changes | Ruby Required |
|------|-----|-----------|-------------|---------------|
| 5.0.x | 5.1.x | Easy | Encrypted secrets, yarn default | 2.2.2+ |
| 5.1.x | 5.2.x | Medium | Active Storage, credentials | 2.2.2+ |
| 5.2.x | 6.0.x | Hard | Zeitwerk, Action Mailbox/Text | 2.5.0+ |
| 6.0.x | 6.1.x | Medium | Horizontal sharding, strict loading | 2.5.0+ |
| 6.1.x | 7.0.x | Hard | Hotwire/Turbo, Import Maps | 2.7.0+ |
| 7.0.x | 7.1.x | Medium | Composite keys, async queries | 2.7.0+ |
| 7.1.x | 7.2.x | Medium | Transaction-aware jobs, DevContainers | 3.1.0+ |
| 7.2.x | 8.0.x | Very Hard | Propshaft, Solid gems, Kamal | 3.2.0+ |
| 8.0.x | 8.1.x | Easy | Bundler-audit, max_connections | 3.2.0+ |
