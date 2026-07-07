# Ruby 3.1 → 3.2

**Difficulty:** Easy-Medium. Mostly additive (new features), with a continuing trickle of stdlib-to-bundled-gem migrations rather than hard removals.

## `Data.define` Added (Additive, No Migration Required)

A new, simpler immutable value-object primitive alongside `Struct`. Nothing existing breaks; only relevant if the team wants to start using it for new code.

```ruby
Point = Data.define(:x, :y)
p = Point.new(x: 1, y: 2)
```

## Further Stdlib-to-Bundled-Gem Migrations

Same ongoing process as 3.0→3.1 — check the specific patch's release notes for what moved this time. Same fix pattern: explicit `require` (and Gemfile entry if used directly rather than transitively).

## `WeakMap` / `WeakRef` Behavior Refinements

Minor internal changes to weak-reference handling. Extremely unlikely to affect typical application code; relevant mainly to gems implementing their own caching layers with weak references.

## Hash-Literal Shorthand (`{x:, y:}`) Introduced Later in the 3.2 Series

Ruby 3.1 already introduced this shorthand for hash literals and method calls (`{x:}` as shorthand for `{x: x}`); 3.2 doesn't change it further, but it's worth knowing it's available and stable by this point if the codebase hasn't adopted it yet.

## Improved Error Messages (`did_you_mean` Enhancements)

`NoMethodError`/`NameError` messages get more detailed "did you mean?" suggestions. Purely cosmetic — no code changes needed, but can change error message *text* in a way that breaks tests asserting on exact error message strings (rare, but check if any exist: `grep -rn "assert.*message.*==" test/ spec/` for exact-match assertions on error text).

## What to Check Before Bumping

1. Run the deprecation sweep — this hop's warning volume is typically small.
2. Check for exact-string assertions on error messages in the test suite, if `did_you_mean` message changes are a concern.
3. Boot smoke test coverage matters more than a code grep here — this hop's real risk on a typical app is gem-level compatibility (native extension rebuilds, C-extension gems needing a release that supports 3.2's ABI) rather than app-code breakage.
