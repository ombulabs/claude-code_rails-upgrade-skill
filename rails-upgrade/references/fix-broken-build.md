# Fix Broken Build: Order & Triage

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

Companion to Core Workflow Step 7. After Step 6 detection and the version bump, the suite on `Gemfile.next` will fail. This reference covers *order of attack* and *common failure categories*, so Claude does not flail by fixing whatever the test runner reports first.

---

## The two rules

### 1. Errors before failures

An **error** (Ruby exception, load error, uninitialized constant) halts the example before the assertion runs. A **failure** is an assertion that produced the wrong answer.

Fix errors first because:

- An error on a shared require path or autoloading change cascades into dozens of apparent failures. Fix the load problem and most of the "failures" disappear.
- A failing example provides real information (actual vs expected). An errored example provides no information until the error is removed.

In RSpec output, errors are reported separately at the top of the summary. In Minitest, errors appear with `E` and failures with `F`. Sort the output before picking the first to fix.

### 2. Unit → integration → system

Fix in dependency order:

1. **Models / services / mailers / helpers**. Pure Ruby, isolated. Fixing these removes noise from higher layers.
2. **Controllers / integration tests**. Depend on models being correct.
3. **System / feature / browser**. Depend on the full stack; the noisiest to run, the slowest to iterate. Fix last.

### Per-framework order

**RSpec:**
```
spec/models       →  spec/services  →  spec/mailers
  →  spec/helpers →  spec/controllers
  →  spec/requests (integration)
  →  spec/system (feature)
```

**Minitest:**
```
test/models   →  test/mailers   →  test/helpers
  →  test/controllers
  →  test/integration
  →  test/system
```

Run one layer at a time with `bundle exec rspec spec/models` (or the Minitest equivalent) until green, then move up.

---

## Common failure categories in a Rails hop

Use these as a triage checklist when reading errors. Most broken-build pain on a Rails hop falls into one of the following:

### Autoloading / Zeitwerk (5.2 → 6.0 and later)

- `NameError: uninitialized constant`, `Zeitwerk::NameError`
- Usually a file that violates the `camelize` ↔ `constantize` contract (e.g., `app/models/csv_parser.rb` defines `CSVParser` instead of `CsvParser`).
- Run `bin/rails zeitwerk:check` to surface these before the suite.

### Callback / filter rename (legacy hops)

- `before_filter` → `before_action`, `skip_before_filter` → `skip_before_action`, etc. Usually a regex-safe rename; see `references/deprecation-resolution/deprecation-strategies.md`.

### Strong Parameters & mass assignment (4.x hops)

- `ActiveModel::ForbiddenAttributesError` or `ActiveModel::MassAssignmentSecurity::Error`. Wrap params in `params.require(...).permit(...)`.

### Keyword arguments (2.7 → 3.0 Ruby)

- `ArgumentError: wrong number of arguments` with a hash-vs-kwargs signature. Add `**` at call sites. Often surfaces simultaneously with a Rails hop that tightens Ruby requirements.

### Frozen string / mutated constant

- `FrozenError` after frozen-string defaults tighten. Fix by duping the string at the mutation site, not by removing the frozen magic comment.

### Signed cookies / encrypted credentials (5.1+ hops)

- `ActiveSupport::MessageEncryptor::InvalidMessage`, secrets readable but credentials not, etc. Usually a config-defaults gap; may indicate `load_defaults` work that should be deferred to Step 10.

### Asset pipeline (Sprockets ↔ Propshaft, 7.x → 8.0)

- Manifest missing, asset helper returns nil. Usually a pipeline choice the user has to make explicitly; flag for Step 8 smoke test, not Step 7 fixing.

---

## When to reach for `NextRails.next?`

Default: fix forward so the code works on both current and target Rails without branching. Only introduce `NextRails.next?` when:

- An API is genuinely removed on target and no shared call form exists.
- A method signature changed incompatibly and the change cannot be back-ported to the current version.

If you introduce `NextRails.next?`, it becomes cleanup in Step 9 (DELEGATE to the `dual-boot` cleanup contract). Budget for it.

DELEGATE to the `dual-boot` skill for the exact pattern and examples.

---

## Iteration rhythm

1. Run the next-smallest failing layer (unit first).
2. Read the first error (not failure).
3. Categorize using the list above.
4. Apply the fix forward; avoid `NextRails.next?` unless unavoidable.
5. Rerun just that file, then the layer, then the layer above only when this one is green.
6. Commit per logical fix, not per batch. Smaller commits make regressions bisectable.

Do not fix deprecations printed by the *next* Rails here. Those belong in the next hop's Step 3.
