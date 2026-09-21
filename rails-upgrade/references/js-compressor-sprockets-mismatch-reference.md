# JS Compressor vs Sprockets During a Dual-Boot Upgrade

**When to read this:** the `JS_COMPRESSOR_GEM_MISMATCH` detection pattern fired, i.e. the
Gemfile has `gem "terser"` (or `closure-compiler`) and you are dual-booting across a Rails
version that locks Sprockets to the 2.x line (Rails 4.0 via `sprockets-rails`).

If the app uses plain `uglifier`, you do not need this file. The standard
`config.assets.js_compressor = :uglifier` fix is enough.

---

## The problem in one paragraph

Modern JS-compressor gems (terser, closure-compiler) `require "sprockets/digest_utils"` from
their railtie. That file exists only in **Sprockets >= 3**. Rails 4.0 pins Sprockets to **2.x**.
The next bundle *resolves* fine (so `railsbump` / `next_rails` report nothing), but at **boot**
Bundler auto-requires the gem, the railtie runs, and you get:

```
LoadError: cannot load such file -- sprockets/digest_utils
```

The failure is require-time, not resolve-time, which is why dependency checkers miss it.

## Why not just use uglifier on the next side?

Because apps add terser on purpose. Uglifier's last release (4.2.0, Sep 2019) is abandoned and
cannot compile modern JS:

- ES2020 optional chaining `?.` and nullish coalescing `??` — not parsed at all, even with
  `harmony: true`.
- UTF-8 source files — uglifier defaults to US-ASCII and errors on smart quotes, em-dashes, etc.

Swapping terser for uglifier on the next side would drop exactly the assets that motivated
terser. The goal is to keep terser working on **both** sides.

---

## The recipe

### Gemfile

```ruby
group :assets do
  if next?
    gem "uglifier", ">= 1.3.0"   # ONLY so the :uglifier symbol resolves in env configs
    gem "terser", require: false  # the real compressor; require: false is MANDATORY (see below)
  else
    gem "terser"                  # current side: railtie is harmless on Sprockets 2.x there
  end
end
```

**Why `require: false` on the next side is mandatory.** Without it, Bundler auto-requires
terser at boot, the railtie runs `config.assets.configure { ... }`, that block references
`Terser::Compressor`, which autoloads and `require "sprockets/digest_utils"` — and boot dies.
With `require: false`, the railtie never runs; you load terser yourself at compile time.

**Why uglifier is still present on the next side.** Env configs set
`config.assets.js_compressor = :uglifier` (see below). Sprockets 2.x resolves `:uglifier` to its
built-in `UglifierCompressor`. The gem must be installed for the symbol to resolve, even though
its JS engine never actually runs in production — the rake task replaces it with Terser first.

### Environment configs (production / staging / etc.)

```ruby
config.assets.js_compressor = :uglifier
```

Unconditional is fine: `:uglifier` resolves on both Sprockets 2.x (next) and the current side.

### Rake task: swap in Terser at compile time

Hook on `assets:environment` (runs before compilation) and replace the registered `:uglifier`
processor with Terser:

```ruby
# lib/tasks/assets.rake
Rake::Task["assets:environment"].enhance do
  require "terser"
  env = Rails.application.assets
  env = env.instance_variable_get(:@environment) if env.is_a?(Sprockets::Index)

  terser = Terser.new(output: { ecma: 2015 })
  env.js_compressor = nil  # unregisters the :uglifier bundle processor set in env configs
  env.register_bundle_processor("application/javascript", :js_compressor) do |context, data|
    if context.pathname.to_s.include?("/webpack/") || context.pathname.basename.to_s.include?(".min.")
      data            # already minified — skip
    else
      terser.compile(data)
    end
  end
  Rails.application.assets = env.index if Rails.application.assets.is_a?(Sprockets::Index)
end
```

On a current Rails 3.2 side the equivalent uses `Sprockets::LazyCompressor` (defined in
ActionPack 3.2, not the Sprockets gem) wrapping a `Terser.new`, gated on `config.assets.compress`
so it only runs in production-like environments.

---

## Cleanup on the next hop (when Sprockets reaches 3/4)

Once the app is fully on a Rails version that ships Sprockets 3/4, unwind the workaround:

1. Drop `uglifier` — it was only a symbol shim.
2. Drop `require: false` on terser — Sprockets 3/4 integrates `Terser::Compressor` natively via
   the railtie.
3. Delete the rake-task swap — terser registers itself.
4. Remove the `:uglifier` assignment / any `NextRails.next?` guards in env configs.

---

## Notes

- Use `NextRails.next?` for any runtime branching, never `respond_to?` or `Gem::Version`
  comparisons.
- The exact hop where this bites is wherever Sprockets is still pinned to 2.x — for the
  3.2 → 4.0 upgrade that is the 4.0 side. An app that already has Sprockets 3/4 will not hit it.
