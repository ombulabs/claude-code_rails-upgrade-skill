# Ruby 2.7 → 3.0

**Difficulty:** Hard. The single largest breaking-change surface in recent Ruby history — 3.0 was explicitly designed as the payoff for 2.7's deprecation-warning campaign.

## Headline Change: Keyword Argument / Positional Hash Separation

Before 3.0, a method defined with keyword arguments could still be called with a trailing positional hash, and Ruby would implicitly convert it. 3.0 removes the implicit conversion entirely.

```ruby
# Method definition
def connect(host, port: 80); end

# 2.7: works, with a deprecation warning
connect("example.com", { port: 443 })

# 3.0: raises ArgumentError (wrong number of arguments)
connect("example.com", { port: 443 })

# Fix: use double-splat to make the keyword intent explicit
connect("example.com", **{ port: 443 })
# or, more commonly, just pass keywords directly:
connect("example.com", port: 443)
```

This is usually the largest single volume of warnings/failures on any codebase that hasn't been swept — see `references/deprecation-warnings.md` for how to surface every call site before bumping.

## `Proc.new` With No Block Removed

```ruby
# 2.7: implicitly captures the block passed to the enclosing method
def make_proc
  Proc.new
end

# 3.0: raises ArgumentError: tried to create Proc object without a block
```

**Fix:** pass the block explicitly.

```ruby
def make_proc(&block)
  Proc.new(&block)
end
```

Real-world impact: this shows up inside gems, not just app code — see `references/known-gotchas.md`'s `aws-sdk` v2 entry. The gem's own `required_ruby_version` won't flag it; only a boot smoke test will.

## `$SAFE` and Related Taint/Trust APIs Removed

`$SAFE`, `Object#taint`, `Object#trust`, and related methods are removed. Rare in modern app code, more common in old gems that predate Ruby's move away from the tainting model.

## `URI.escape` / `URI.unescape` Removed

Deprecated for years, fully removed in 3.0. Very common in old, unmaintained gems doing manual URL construction.

```ruby
# 2.x: worked with a deprecation warning (not always emitted via -W:deprecated, see below)
URI.escape("some string")

# 3.0: NoMethodError
```

**Fix:** use `URI::RFC2396_Parser` / `ERB::Util.url_encode`, or find a maintained fork of whatever gem calls it — see `references/known-gotchas.md`'s `paperclip` → `kt-paperclip` example. **Detection note:** this specific removal did not consistently emit a `-W:deprecated`-category warning across all 2.7 patches — grep gem source directly (`grep -rn "URI.escape\|URI.unescape"` across `vendor/bundle` or the gem install path) rather than relying solely on the deprecation sweep.

## Bundled Gems Begin Splitting From "Always Loaded"

Ruby starts the multi-release process of moving some stdlib libraries from implicitly-available to "bundled gem, needs an explicit `require`." This accelerates further in 3.1+ — see `references/known-gotchas.md`'s "default/bundled gems" entry for a confirmed real example (`OpenStruct`) and check each Ruby version's own release notes for the current list, since it keeps growing.

## `Hash#each` Argument Yielding

Minor behavior tightening around how `Hash#each` yields entries to a block with a single, non-destructured parameter. Rare in practice, but worth a quick grep if the app does unusual `Hash#each { |x| ... }` patterns (single param, not `|k, v|`) combined with array-like access on `x`.

## Pattern Matching Stabilizes

`case/in` pattern matching, experimental in 2.7 (with a warning on every use), is no longer experimental in 3.0 — the warning goes away, no code changes needed, but worth knowing the syntax is now considered stable if the app adopted it early.

## What to Check Before Bumping

1. Run the deprecation sweep (`references/deprecation-warnings.md`) — this hop has by far the highest warning-to-fix ratio of any Ruby hop in recent history; budget real time.
2. Grep gem sources directly for `URI.escape`/`URI.unescape` (the detection gap noted above).
3. Audit the Gemfile for `aws-sdk` v2 (`gem "aws-sdk", "~> 2"`) and any similarly old, single-maintainer gems doing low-level metaprogramming — these are the most likely to hit `Proc.new` or similar removed-API issues at boot.
