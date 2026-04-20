# Deprecation Resolution Strategies

**Based on "The Complete Guide to Upgrade Rails" by FastRuby.io (OmbuLabs)**

The toolbox for actually fixing deprecation warnings. See `workflows/deprecation-resolution-workflow.md` for the loop; this file is the *how*. For Rails config + where warnings surface, see `deprecation-warnings.md`.

---

## Strategy Selection

Pick the smallest tool that fits the warning:

| Warning shape | Strategy |
|---|---|
| Method rename, signature unchanged (`update_attributes` → `update`) | **Regex / grep-replace** |
| Callsite refactor, same semantics, crosses syntax (`before_filter` → `before_action`, `redirect_to :back` → `redirect_back`) | **Regex** if the receiver/args are consistent, else **synvert-ruby** |
| Structural AST change (wrapping args, block-to-keyword, conditionals inside definitions) | **synvert-ruby** |
| API genuinely removed or signature incompatible on target Rails, no backward-compatible form exists | **`NextRails.next?` conditional** (last resort) |
| Comes from a gem, not app code | **Gem upgrade**, then repeat |

Two rules override the table:

1. **Prefer backward-compatible fixes** over `NextRails.next?`.
2. **Don't fix warnings the *next* Rails prints during dual-boot** here, those belong in the next hop's Step 3.

---

## Backward-Compatible Fix Preference

Default. Why:

- Ships today on the current Rails, no dual-boot coupling required.
- No `NextRails.next?` conditional to collapse later (Step 9 work).
- Smaller diff at the actual version bump.
- Survives a rollback.

Example: `update_attributes(x)` → `update(x)` works on Rails 4.2+, fix ships standalone, no version gate.

Use `NextRails.next?` only when the API is *removed* on the target and no shared call form exists. DELEGATE to the `dual-boot` skill for the `NextRails.next?` pattern itself.

---

## Regex / grep-replace

Fast for mechanical renames. Workflow:

```bash
# Find callsites
grep -rn "update_attributes" app/ lib/ spec/ test/ --include="*.rb"

# Batch replace (inspect diff before committing!)
grep -rl "update_attributes" app/ lib/ spec/ test/ --include="*.rb" \
  | xargs sed -i '' 's/update_attributes/update/g'    # macOS
  # GNU sed: sed -i 's/update_attributes/update/g'
```

Caveats:
- False positives in strings, comments, YAML fixtures, method names that legitimately contain the token. Always diff before commit.
- Word-boundary it: `\bupdate_attributes\b` (ripgrep/GNU grep) to skip `update_attributes_if_present`.
- Run the focused suite after each batch, not once at the end.

---

## `next_rails` Deprecation Tooling

The `next_rails` gem ships commands for deprecation hunting in dual-boot setups. DELEGATE to the `dual-boot` skill for installation and full command reference. Relevant here:

- Running the suite against `Gemfile.next` surfaces *next-version* deprecations (useful diagnostic, but fix those in the *next* hop, not this one).
- Use the current-Gemfile run for this step's list.

---

## synvert-ruby

AST-based refactor tool. Use when regex would false-positive too often or the fix reshapes the syntax tree (wraps args, moves blocks, adds keyword args).

- Install: `gem install synvert`
- Snippet catalog: https://github.com/xinminlabs/synvert-snippets-ruby (community snippets for common Rails deprecations)
- Custom snippets: write a Ruby DSL file, run `synvert-ruby -r path/to/snippet.rb`.

Rule of thumb: if a regex needs more than two lookbehinds to be safe, reach for synvert.

---

## Gem-Origin Deprecations

Warnings with a non-app-code backtrace usually come from a gem:

1. `bundle outdated`, see if a newer version of the offending gem exists.
2. `bundle update <gem>`, upgrade it; rerun the suite; check if the warning is gone.
3. If the latest release still emits it, the gem itself hasn't updated for the target Rails. Options:
   - Open an issue / PR upstream.
   - Pin and carry a patch.
   - Swap for an actively maintained alternative.
4. If the gem is abandoned, add it to the gem-compat backlog (see `references/gem-compatibility.md`).

Don't wrap gem-emitted warnings in `NextRails.next?` in your own code, fix the gem.

---

## Regression Prevention

Once a deprecation is resolved, lock it down so it cannot reappear:

### Rails 6.1+: `disallowed_warnings`

See `deprecation-warnings.md` for the config. Add the fixed pattern to the list; reintroduction fails tests.

### Rails < 6.1: Custom Rubocop Cop

```ruby
# lib/rubocop/cop/custom/no_update_attributes.rb

module RuboCop
  module Cop
    module Custom
      class NoUpdateAttributes < Base
        MSG = 'Use `update` instead of `update_attributes`.'

        def_node_matcher :update_attributes?, <<~PATTERN
          (send _ {:update_attributes :update_attributes!} ...)
        PATTERN

        def on_send(node)
          return unless update_attributes?(node)
          add_offense(node)
        end
      end
    end
  end
end
```

Wire it into `.rubocop.yml` and run in CI. See [Lint/DeprecatedClassMethods](https://github.com/rubocop-hq/rubocop/blob/master/lib/rubocop/cop/lint/deprecated_class_methods.rb) for a reference implementation.

---

## Worked Example: `update_attributes` → `update`

Warning:

```
DEPRECATION WARNING: update_attributes is deprecated and will be removed
from Rails 6.1 (please, use update instead)
```

Strategy: regex (rename, signature unchanged). Backward-compatible fix available (works on all Rails ≥ 4.2).

```bash
# Confirm scope
grep -rn "\bupdate_attributes\b" app/ lib/ spec/ --include="*.rb" | wc -l

# Replace
grep -rl "\bupdate_attributes\b" app/ lib/ spec/ --include="*.rb" \
  | xargs sed -i '' 's/\bupdate_attributes\b/update/g'

# Verify
bundle exec rspec spec/models  # focused run
git diff --stat
```

Then, if on Rails 6.1+, add to `disallowed_warnings`:

```ruby
ActiveSupport::Deprecation.disallowed_warnings << /update_attributes/
```

Commit. Move to next warning.
