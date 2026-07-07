# Ruby 3.2 → 3.3

**Difficulty:** Easy-Medium. Groundwork release for the Prism parser transition (finished in 3.4) plus YJIT maturing toward broader production use — most changes are internal/performance-oriented rather than removals.

## `it` Implicit Block Parameter Stabilizes

Introduced experimentally around this era, `it` as an implicit reference to a block's sole argument becomes a stable, documented feature by 3.3 (exact availability depends on the specific patch — check release notes if relying on it):

```ruby
# Instead of:
[1, 2, 3].map { |x| x * 2 }

# Can write:
[1, 2, 3].map { it * 2 }
```

Purely additive — nothing breaks, only relevant to teams wanting to adopt the new syntax.

## Prism Parser Groundwork (Not Yet Default)

Ruby ships the new Prism parser as an available option in 3.3, but the *default* parser doesn't switch until 3.4. This mostly matters to tooling authors (linters, LSP servers) rather than application code — no action needed for a typical app upgrade, but if the app has custom Ripper-based tooling or a gem that parses Ruby source directly, check whether that gem has a 3.3-compatible release.

## YJIT Becomes More Broadly Production-Viable

Performance-oriented change, not a breaking one. Worth evaluating enabling YJIT (`RUBYOPT="--yjit"` or `RUBY_YJIT_ENABLE=1` depending on how the app is deployed) as a follow-up optimization after the version bump lands, not as part of the bump itself — keep the two changes (version bump vs. JIT enablement) in separate deploys so a regression can be attributed to the right cause.

## Continuing Stdlib-to-Bundled-Gem Migrations

Same ongoing process as every hop since 3.0 — check the specific patch's release notes.

## What to Check Before Bumping

1. Run the deprecation sweep — typically light for this hop.
2. If the app has any gem or internal tool that parses Ruby source directly (not just runs it), check its compatibility with 3.3 specifically, ahead of the 3.4 default-parser switch.
3. As with 3.1→3.2, gem-level native-extension compatibility is usually the bigger practical risk than app-code breakage for this hop.
