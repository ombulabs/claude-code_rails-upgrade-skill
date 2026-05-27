# Runtime Detection Workflow

**When to run:** Step 4.7 of the upgrade workflow, after the boot smoke test (Step 4.6) passes and before report generation (Step 5).

**Why this step exists:** The boot smoke test (Step 4.6) boots Rails in the **development** environment with **lazy autoloading**. It only catches failures that surface at `Bundler.require` time — a gem requiring a removed file, or calling a removed Rails internal during its own load. Almost none of the application's own classes load, so app-code breakage and app-code deprecations stay invisible.

For apps with a strong test suite, the missing signal is recovered later: Step 6 runs the full suite, and the dual-boot skill's `references/deprecation-tracking.md` (DeprecationTracker shitlist) captures every deprecation the tests exercise. **But on apps with little or no test coverage, that capture yields almost nothing** — the tests never run the code, so the warnings never fire. Those apps fall back to static patterns (Step 4) and the shallow lazy boot (Step 4.6), and miss everything in between.

This step closes that gap by **eager-loading every class in the app** and capturing what breaks or warns at load time — no test coverage required.

---

## What eager-load catches (and what it does not)

Eager-load `require`s every file under the eager-load paths, which runs each **class body**. That executes load-time code: associations, `default_scope`, `before_action` / `before_filter` macros, `serialize`, `enum`, scopes, class-level config, and constant references.

| Failure class | Static patterns (Step 4) | Lazy boot (Step 4.6) | Eager-load (this step) |
|---|---|---|---|
| Gem requires removed file at `Bundler.require` | ✗ | ✓ | ✓ |
| App constant / class-body calls removed API | only if a regex exists for it | ✗ (never loaded) | ✓ |
| Autoload / Zeitwerk naming violation | ✗ | ✗ | ✓ (via `zeitwerk:check`) |
| Deprecation fired at **class-definition time** | ✗ | ✗ | ✓ |
| Deprecation fired inside a **method body** | ✗ | ✗ | ✗ (needs the method to run) |

**The limit:** eager-load does not execute method bodies. A deprecated call buried inside an instance method only fires when that method runs — which still needs tests (Step 6 + DeprecationTracker) or real traffic. Eager-load gives you the **load-time** layer, not the full runtime layer. State this honestly in the report; do not claim a clean eager-load means "no deprecations."

**Autoloader-agnostic:** eager-load works on both the classic autoloader (pre-6.0 apps) and Zeitwerk (default 6.0+, mandatory 7.0+). Only the `zeitwerk:check` sub-step (Tier B) is conditional on the app running Zeitwerk.

---

## Precondition: deprecations must be visible

If deprecation behavior is silenced, this step's eager-load will run clean-looking while warnings vanish. Before Tier C, confirm deprecations are not silenced using the sweep in the dual-boot skill's `references/deprecation-tracking.md` ("Step 1: Detect If Deprecations Are Silenced"). Do not duplicate that sweep here — run it from there. If `:silence` or `report_deprecations = false` is set, the warnings you want are being thrown away.

Substitute the project's own runner throughout (detect `bin/rails`, `bin/test`, `bundle exec`, etc., as the dual-boot skill's Key Principle 4 describes). Prefix every command with `BUNDLE_GEMFILE=Gemfile.next` so it runs against the target Rails version.

---

## Procedure

### Tier A: Eager-load boot

Force every app class to load, in one command:

```bash
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner "Rails.application.eager_load!; puts 'EAGER OK'"
```

- Use the **development** environment (the default) with an explicit `eager_load!` rather than `RAILS_ENV=production`, so the load does not demand production credentials, a production database, or asset compilation.
- A clean `EAGER OK` means every eager-loadable class loaded without raising under the target Rails version.
- A failure means an app class (or an engine/initializer it pulls in) calls something removed at the target version. Capture the trace and diagnose as in the "Diagnose a failure" section below.

### Tier B: Zeitwerk check (Zeitwerk apps only — skip on classic autoloader)

```bash
BUNDLE_GEMFILE=Gemfile.next bundle exec rails zeitwerk:check
```

This catches files whose constant name does not match the path Zeitwerk expects — a class of breakage that neither static patterns nor a plain eager-load surfaces cleanly. Skip entirely on pre-6.0 apps and on apps explicitly set to `config.autoloader = :classic`; there is no `zeitwerk:check` rake task and eager-load (Tier A) is the autoload-correctness check instead.

### Tier C: Deprecation collector boot

A plain `grep "DEPRECATION WARNING"` over the boot output tells you *what* is deprecated but not *where* — and without the call site you cannot fix it in this hop. Instead, install a deprecation **behavior lambda** that records each message together with its callstack, eager-load, then print each unique message mapped to the app frames that triggered it:

```bash
BUNDLE_GEMFILE=Gemfile.next bundle exec rails runner '
  seen = Hash.new { |h, k| h[k] = [] }

  # behavior is called once per deprecation. Signature widened over time
  # (message, callstack, [horizon], [gem]); the splat absorbs the extras.
  collector = ->(message, callstack, *) {
    # first frame inside the app (not a gem, not Rails core) = the fixable site
    frame = Array(callstack).map(&:to_s).find { |f|
      f.include?(Rails.root.to_s) && !f.include?("/gems/")
    }
    site = frame ? frame.sub("#{Rails.root}/", "").split(":in ").first : "(no app frame — gem or framework origin)"
    seen[message] << site
  }

  if Rails.application.respond_to?(:deprecators)   # Rails 7.1+
    Rails.application.deprecators.behavior = collector
  else
    ActiveSupport::Deprecation.behavior = collector
  end

  Rails.application.eager_load!

  seen.each do |message, sites|
    puts message
    sites.uniq.first(10).each { |s| puts "  -> #{s}" }
  end
'
```

- **How the tracking works:** the collector closure owns the `seen` hash. Each time Rails fires a deprecation during `eager_load!`, the lambda runs, walks the callstack to the first frame under `Rails.root` that is not in a gem, and files the message under that app `file:line`. After eager-load finishes, `seen` is the full inventory — message -> the exact app sites you edit in this hop.
- **Cross-version:** Rails 7.1+ moved to a registry of deprecators (`Rails.application.deprecators`); setting only `ActiveSupport::Deprecation.behavior` there would miss the framework deprecators. The `respond_to?(:deprecators)` branch covers both eras. The behavior signature widened from `(message, callstack)` to `(message, callstack, horizon, gem_name)` across versions — the trailing `*` absorbs whichever extra args this Rails passes.
- **Routing:** entries with an app frame and `kind: deprecation` for this hop go into the **fix-before-bump** bucket with their `file:line` — fixable now, exactly like Step 4's static-pattern findings. Entries marked `(no app frame ...)` originate in a gem or Rails itself; those are **not** in-hop app edits — track them as a gem bump (see `boot-smoke-test-workflow.md`) or an upstream wait, not a code change.
- These are **load-time** deprecations only (see the table above). Method-body deprecations still need the test suite / DeprecationTracker.

---

## Diagnose a failure

Tier A / Tier B failures look like:

- `NameError: uninitialized constant <X>` — a constant moved or was removed at the target version, or a Zeitwerk naming mismatch.
- `NoMethodError: undefined method '<x>'` at class-definition time — a class-level macro or config call was removed/renamed.
- `ArgumentError` from a Rails class load — a macro is passed args in a now-unsupported shape.

Locate the source: the trace's top app frame names the file and line. If the offending frame is inside a gem rather than `app/`, treat it like a Step 4.6 finding (bump the gem; see `boot-smoke-test-workflow.md`). If it is in `app/`, it is an app-code fix that belongs in the upgrade report.

---

## Output

A short report block to merge into Step 5's Comprehensive Upgrade Report:

```
Runtime detection (Step 4.7):

  - Eager-load (Tier A): PASS / FAIL
  - Zeitwerk check (Tier B): PASS / FAIL / N/A (classic autoloader)
  - Load-time deprecations (Tier C): N unique warnings

If Tier A / B FAIL → app-code fixes (added to fix-before-bump):
  - <file:line> — <error class> — <one-line cause>

Load-time deprecations (fix-before-bump where kind: deprecation):
  - <unique DEPRECATION WARNING message>
      -> app/path/to/file.rb:NN        # fixable in this hop
      -> app/path/to/other.rb:NN
  - <message with (no app frame …)>    # gem/framework origin → gem bump, not an app edit

Coverage note: eager-load exercises class bodies only. Method-body
deprecations still require the test suite (Step 6) or DeprecationTracker
to surface. A clean run here is NOT a guarantee of zero deprecations.
```

If every tier passes, record that explicitly — it is a positive signal, with the coverage caveat above attached so the user does not over-read it.

---

## Notes

- This step does **not** replace the post-bump test suite run in Step 6, nor the DeprecationTracker capture documented in the dual-boot skill. It is the **load-time** layer that runs even when test coverage is thin or absent. On a well-covered app it is fast and usually confirms what the suite already showed; on a poorly-covered app it is often the only signal between static patterns and production.
- Skip this step only if there is no `Gemfile.next` yet (very early in dual-boot setup). In all other cases, run it after Step 4.6.
- If Tier A fails on an initializer that genuinely requires production-only setup, note it and move on rather than forcing `RAILS_ENV=production`; the goal is class-load coverage, not a full production boot.
