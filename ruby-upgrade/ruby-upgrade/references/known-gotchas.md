# Known Gotchas

Real issues hit during actual Ruby upgrades, not generic advice. Add to this list as new ones surface — mirrors `rails-upgrade`'s `references/gem-compatibility.md` → "Known Gotchas" section in spirit.

## `Proc.new` with no block (removed in Ruby 3.0)

**Symptom:** `ArgumentError: tried to create Proc object without a block`, raised from inside a gem, often at `require` time (boot fails before any app code runs).

**Cause:** Ruby < 3.0 let `Proc.new` inside a method implicitly capture the block passed to the *enclosing* method call, with no explicit `&block` forwarding. This was deprecated for years and fully removed in Ruby 3.0.

**Confirmed real example (fastruby/audit, Ruby 2.7 → 3.2.11):** `aws-sdk-core` 2.3.23 (part of the `aws-sdk` v2 umbrella gem) calls `Proc.new` this way in `service_added`, raising on the very first `require "aws-sdk"`. The gem's own declared `required_ruby_version` did not flag this — it's a runtime code issue, not a declared-constraint issue, so `bundle install` succeeds and only actually booting the app catches it. This is the Ruby-upgrade equivalent of the class of bug `rails-upgrade`'s boot-smoke-test workflow exists to catch for Rails hops.

**Fix:** `aws-sdk` v2 is effectively dead for Ruby 3.0+; there is no patch-level fix. Move to the modern per-service SDK (`aws-sdk-s3`, `aws-sdk-sqs`, etc. — same `Aws::` namespace, actively maintained). If a library in your stack (e.g. an attachment gem) already documents `aws-sdk-s3` as its expected storage backend, this is usually a pure Gemfile swap with zero application code changes.

**How to catch this before it bites in production:** the boot smoke test (`rails runner "puts RUBY_VERSION"` under the target Ruby) — see `SKILL.md` Step 5. Static analysis and `bundle install` cannot see this class of bug.

## `URI.escape` / `URI.unescape` (removed in Ruby 3.0)

**Symptom:** `NoMethodError: undefined method 'escape' for URI:Module`, typically inside a gem generating a URL.

**Cause:** `URI.escape`/`URI.unescape` were deprecated for years (with a runtime warning on every call) and fully removed in Ruby 3.0.

**Confirmed real example (fastruby/audit):** `paperclip` (unmaintained since 2018) calls `URI.escape` in `lib/paperclip/url_generator.rb` on every single attachment URL it generates. Checked paperclip's own *last* release (6.1.0, also 2018) — never fixed, because the gem has had no maintenance since Active Storage replaced it in the Rails ecosystem.

**Fix:** `kt-paperclip` is a maintained, actively-released fork that fixes this (uses `URI::RFC2396_Parser` instead) and stays drop-in compatible — same `Paperclip::` module, same require path, just a different gem name (`gem "kt-paperclip", require: "paperclip"`). General pattern: before assuming an abandoned gem forces a full migration to its replacement, check for an actively-maintained fork first — see `rails-upgrade`'s `references/gem-compatibility.md` → "Playbook: gem has no compatible version" for the fork/replace/vendor decision tree, which applies identically here.

**Detection tip:** grep the gem's source for `URI.escape` / `URI.unescape` before upgrading, if you suspect an old gem in your dependency tree does file/URL handling — this specific method is a well-known Ruby 3.0 casualty and shows up in more old gems than just paperclip.

## Dev-only gems with a Ruby floor *above* your current Ruby, not just below

The mirror image of the situation in `rails-upgrade`'s gem-compatibility reference (a gem needing a *newer* Ruby than the current Rails hop targets, so it gets dropped until Ruby catches up): once Ruby *does* catch up, re-adding the gem can introduce a **new runtime requirement** you didn't have before, not just a version bump.

**Confirmed real example (fastruby/audit, re-adding `spring` after Ruby reached 3.1):** `spring` 4.x requires `config.enable_reloading = true` in whatever environment it preloads — including the test environment, if you use spring for `bin/rails test`. Raises a hard `RuntimeError` at boot (`Spring reloads, and therefore needs the application to have reloading enabled`) if your test environment intentionally runs with `enable_reloading = false` (typical, for test-suite performance/determinism).

**Fix:** `config/spring.rb` (a real, spring-documented escape hatch, not a hack): `Spring.dangerously_allow_disabling_reloading = true`. Despite the name, this is the normal, widely-used setting for apps that don't need Spring to hot-reload code mid-test-run within a single preloaded process — which is the common case.

**Lesson:** when a gem was dropped for a "needs newer Ruby" reason and Ruby later catches up, don't just re-add it and assume the story is the same as before it was dropped — re-verify via the boot smoke test. The gem's *own* version may have moved forward significantly in the meantime and picked up new runtime requirements unrelated to the original reason it was dropped.

## Moving the Docker base image's OS, not just the Ruby version

Official `ruby:X.Y.Z` Docker images track a specific Debian release, and that Debian release can lag or lead your app's actual Ruby bump. Two concrete failure classes seen from this:

1. **An old base image's glibc is too old for a gem's precompiled native extension.** (Not Ruby-version-specific — this is a Debian-version problem living on the *old* Ruby's image.) Symptom: `Could not open '/lib/ld-linux.so.2'`-style errors, or a native gem simply failing to load. Workaround while stuck on the old base: `bundle config set --global force_ruby_platform true` (forces building from source instead of using the precompiled native gem).
2. **Bumping the Ruby version also bumps the Debian base**, which can *remove the need* for workarounds tied to the old base — don't carry them forward blindly. Confirmed real example (fastruby/audit): moving from `ruby:2.7.2` (Debian 10 "buster", EOL, glibc too old for a modern `nokogiri` precompiled gem) to `ruby:3.2.11` (Debian 13 "trixie", current, modern glibc) meant `force_ruby_platform` was no longer needed, an EOL-apt-repo `sources.list` patch (`archive.debian.org`) was no longer needed, and Node.js became installable as a plain `apt` package again (the old base needed a manual tarball install since NodeSource had dropped support for that base's Node major version).

**Check when landing a Ruby hop:** `docker run --rm ruby:<new-version> cat /etc/os-release` to see what Debian release the new base actually is, and re-evaluate every OS-version-specific workaround in the Dockerfile against it — don't assume they're still needed, and don't assume they're safe to blanket-remove without testing either.

## `bundle lock` run on a different host platform than the deploy target pollutes `Gemfile.lock`

Not Ruby-version-specific, but very likely to happen *during* Ruby upgrade work specifically, since re-locking for a Ruby bump is exactly when you'd run `bundle lock` locally (e.g. on an Apple Silicon Mac) while the actual deploy target is Linux.

**Symptom:** after a local `bundle lock`, `Gemfile.lock`'s `PLATFORMS` section shows only a host-specific platform (e.g. `arm64-darwin-25`) instead of the generic `ruby`, and a gem with precompiled native variants (e.g. `nokogiri`) gets pinned to a platform-specific gem (`nokogiri-1.15.7-arm64-darwin`) that a Linux container can't load (`LoadError: cannot load such file -- nokogiri/nokogiri`).

**Fix:** force ruby-platform resolution on the host too, matching whatever the deploy image already does: `bundle config set --local force_ruby_platform true` before running `bundle lock`, then `bundle lock --add-platform ruby --remove-platform <the-polluting-platform>` if it already got added. Re-check `Gemfile.lock`'s `PLATFORMS` section reads `ruby` only before committing.

## Default/bundled gems that stop being implicitly available

Ruby has been steadily moving stdlib libraries from "always loaded" to "bundled gem, needs an explicit `require`" across the 3.x series (`net-smtp`, `net-pop`, `net-imap`, and others made this move around Ruby 3.1; more libraries continue to move this direction in later releases — check the specific Ruby version's release notes rather than assuming a library seen here is still safe).

**Confirmed real example (fastruby/audit):** a re-lock during this Ruby upgrade (unrelated gem version bumps, not the Ruby bump itself) caused `OpenStruct` to no longer be implicitly available in a file that used it directly (`NameError: uninitialized constant OpenStruct`) — something else in the dependency chain had previously pulled in `require "ostruct"` as a side effect, and a version bump removed that transitive path.

**Fix:** add the explicit `require` for whatever stdlib class your code uses directly, rather than relying on some other gem to have required it first. Cheap, safe regardless of Ruby version, and exactly the kind of thing that should be true regardless of whether this specific instance was actually caused by the Ruby bump or a coincident gem bump.
