# Ruby 3.0 → 3.1

**Difficulty:** Medium. Much smaller surface than 2.7→3.0 — mostly stdlib packaging changes and edge-case behavior tightening, not a headline syntax break.

## More Stdlib Libraries Become "Bundled" Gems

Continuing the process started around 3.0, several `net-*` libraries (`net-smtp`, `net-pop`, `net-imap`, and others) move from implicitly available to bundled gems that need an explicit `Gemfile` entry and `require` if used directly (not just transitively via something like `ActionMailer`, which already requires what it needs).

**Symptom:** `LoadError: cannot load such file -- net/smtp` (or similar) in code that calls these libraries directly without an explicit `require`, if nothing else in the dependency chain happened to require it first.

**Fix:** add the explicit `require` (and a `Gemfile` entry if the library isn't already pulled in transitively by something you depend on).

## `Struct.new` Keyword-Init Inference

`Struct.new` with a `keyword_init:` option gets stricter/more predictable inference in some edge cases around mixed positional/keyword member definitions. Rare in practice — check any `Struct.new(..., keyword_init: true)` call sites if the app uses this pattern heavily.

## `Time#+` / `Time#-` Fractional-Second Precision

Arithmetic on `Time` objects with sub-second precision gets more consistent rounding behavior. Very unlikely to affect typical Rails app code (which mostly goes through `ActiveSupport::TimeWithZone`), more relevant to gems doing raw `Time` math directly.

## Onigmo Regexp Engine Update

The bundled regex engine updates, which can very rarely change edge-case matching behavior for unusual patterns (particularly around Unicode property escapes). Not something to proactively hunt for — only relevant if the test suite surfaces an unexpected regex-matching change after the bump.

## What to Check Before Bumping

1. Run the deprecation sweep — smaller volume than 2.7→3.0, but still worth doing every hop, not just the big ones.
2. Grep for direct `require "net/smtp"`-style usage (or the equivalent for other moved libraries) that may have been relying on implicit availability.
3. This is generally a low-drama hop; most of the real risk on a typical Rails app comes from *gem* compatibility with 3.1 rather than app code itself — lean on the boot smoke test (Step 5) more than an exhaustive code grep here.
