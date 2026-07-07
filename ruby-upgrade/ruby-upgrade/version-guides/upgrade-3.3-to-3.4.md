# Ruby 3.3 → 3.4

**Difficulty:** Medium. The Prism parser becomes the default, which is a real behavior-surface change even though it's framed as an internal implementation detail — most code is unaffected, but parser-adjacent tooling and any code relying on old-parser-specific quirks needs checking.

## Prism Becomes the Default Parser

Ruby's default parser switches from the legacy `parse.y`-generated parser to Prism. For the overwhelming majority of application code, this is invisible — Prism parses standard Ruby syntax identically. The real exposure is:

1. **Gems or internal tools that introspect Ruby source directly** (via `Ripper`, `RubyVM::AbstractSyntaxTree`, or similar) may see different AST shapes under Prism than they did under the legacy parser. Check any such gem's changelog for explicit Prism-compatibility notes.
2. **Extremely obscure syntax edge cases** that the legacy parser accepted somewhat by accident (undocumented, ambiguous-but-tolerated constructs) may now raise a `SyntaxError` under Prism's stricter parsing. Rare in well-formed application code; more likely in old metaprogramming-heavy gems.

**How to check:** the boot smoke test (Step 5) and a full test-suite run are the practical way to catch this — there is no useful static grep for "syntax the old parser tolerated that the new one won't," since by definition it's whatever the old parser happened to accept.

## Continuing Stdlib-to-Bundled-Gem Migrations

Same ongoing process as every prior hop — check the specific patch's release notes for what moved this time.

## What to Check Before Bumping

1. Run the deprecation sweep as usual.
2. If any gem in the dependency tree does source introspection (linters, code-generation gems, documentation generators run as part of the build), check its changelog for Prism-related notes before assuming it's a no-op.
3. Lean more heavily on the boot smoke test and full suite run for this hop than on any static check — Prism's behavior differences are, by nature, not something you can reliably grep for in advance.
