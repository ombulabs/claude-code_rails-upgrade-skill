# Known Gotchas

Real issues hit during actual Ruby upgrades, not generic advice. Add to this list as new ones surface.

## `Proc.new` with no block (removed in Ruby 3.0)

**Symptom:** `ArgumentError: tried to create Proc object without a block`, raised from inside a gem, often at `require` time (boot fails before any app code runs).

**Cause:** Ruby < 3.0 let `Proc.new` inside a method implicitly capture the block passed to the *enclosing* method call, with no explicit `&block` forwarding. This was deprecated for years and fully removed in Ruby 3.0.

**Confirmed real example (a Rails app upgraded 2.7 → 3.2.11):** `aws-sdk-core` 2.3.23 (part of the `aws-sdk` v2 umbrella gem) calls `Proc.new` this way in `service_added`, raising on the very first `require "aws-sdk"`. The gem's own declared `required_ruby_version` did not flag this — it's a runtime code issue, not a declared-constraint issue, so `bundle install` succeeds and only actually booting the app catches it.

**Fix:** `aws-sdk` v2 is effectively dead for Ruby 3.0+; there is no patch-level fix. Move to the modern per-service SDK (`aws-sdk-s3`, `aws-sdk-sqs`, etc. — same `Aws::` namespace, actively maintained). If a library in your stack (e.g. an attachment gem) already documents `aws-sdk-s3` as its expected storage backend, this is usually a pure Gemfile swap with zero application code changes.

**How to catch this before it bites in production:** the boot smoke test (`rails runner "puts RUBY_VERSION"` under the target Ruby, or the equivalent boot command for a non-Rails app) — see `SKILL.md` Step 5. Static analysis and `bundle install` cannot see this class of bug.

## `URI.escape` / `URI.unescape` (removed in Ruby 3.0)

**Symptom:** `NoMethodError: undefined method 'escape' for URI:Module`, typically inside a gem generating a URL.

**Cause:** `URI.escape`/`URI.unescape` were deprecated for years (with a runtime warning on every call) and fully removed in Ruby 3.0.

**Confirmed real example:** `paperclip` (unmaintained since 2018) calls `URI.escape` in `lib/paperclip/url_generator.rb` on every single attachment URL it generates. Checked paperclip's own *last* release (6.1.0, also 2018) — never fixed, because the gem has had no maintenance since Active Storage replaced it in the Rails ecosystem.

**Fix:** `kt-paperclip` is a maintained, actively-released fork that fixes this (uses `URI::RFC2396_Parser` instead) and stays drop-in compatible — same `Paperclip::` module, same require path, just a different gem name (`gem "kt-paperclip", require: "paperclip"`). General pattern: before assuming an abandoned gem forces a full migration to its replacement, check for an actively-maintained fork first.

**Detection tip:** grep the gem's source for `URI.escape` / `URI.unescape` before upgrading, if you suspect an old gem in your dependency tree does file/URL handling — this specific method is a well-known Ruby 3.0 casualty and shows up in more old gems than just paperclip.

## Dev-only gems with a Ruby floor *above* your current Ruby, not just below

It's common to drop a gem during an earlier hop because it needs a *newer* Ruby than the current target. The less obvious mirror image: once Ruby *does* catch up and you re-add the gem, its own version may have moved forward significantly in the meantime and picked up a **new runtime requirement** that has nothing to do with the original reason it was dropped.

**Confirmed real example (re-adding `spring` after Ruby reached 3.1):** `spring` 4.x requires `config.enable_reloading = true` in whatever environment it preloads — including the test environment, if you use spring for `bin/rails test`. Raises a hard `RuntimeError` at boot (`Spring reloads, and therefore needs the application to have reloading enabled`) if your test environment intentionally runs with `enable_reloading = false` (typical, for test-suite performance/determinism).

**Fix:** `config/spring.rb` (a real, spring-documented escape hatch, not a hack): `Spring.dangerously_allow_disabling_reloading = true`. Despite the name, this is the normal, widely-used setting for apps that don't need Spring to hot-reload code mid-test-run within a single preloaded process — which is the common case.

**Lesson:** when a gem was dropped for a "needs newer Ruby" reason and Ruby later catches up, don't just re-add it and assume the story is the same as before it was dropped — re-verify via the boot smoke test.

## Moving the Docker base image's OS, not just the Ruby version

Official `ruby:X.Y.Z` Docker images track a specific Debian release, and that Debian release can lag or lead your app's actual Ruby bump. Two concrete failure classes seen from this:

1. **An old base image's glibc is too old for a gem's precompiled native extension.** (Not Ruby-version-specific — this is a Debian-version problem living on the *old* Ruby's image.) Symptom: `Could not open '/lib/ld-linux.so.2'`-style errors, or a native gem simply failing to load. Workaround while stuck on the old base: `bundle config set --global force_ruby_platform true` (forces building from source instead of using the precompiled native gem).
2. **Bumping the Ruby version also bumps the Debian base**, which can *remove the need* for workarounds tied to the old base — don't carry them forward blindly. Confirmed real example: moving from `ruby:2.7.2` (Debian 10 "buster", EOL, glibc too old for a modern `nokogiri` precompiled gem) to `ruby:3.2.11` (Debian 13 "trixie", current, modern glibc) meant `force_ruby_platform` was no longer needed, an EOL-apt-repo `sources.list` patch (`archive.debian.org`) was no longer needed, and Node.js became installable as a plain `apt` package again (the old base needed a manual tarball install since NodeSource had dropped support for that base's Node major version).

**Check when landing a Ruby hop:** `docker run --rm ruby:<new-version> cat /etc/os-release` to see what Debian release the new base actually is, and re-evaluate every OS-version-specific workaround in the Dockerfile against it — don't assume they're still needed, and don't assume they're safe to blanket-remove without testing either.

## `bundle lock` run on a different host platform than the deploy target pollutes `Gemfile.lock`

Not Ruby-version-specific, but very likely to happen *during* Ruby upgrade work specifically, since re-locking for a Ruby bump is exactly when you'd run `bundle lock` locally (e.g. on an Apple Silicon Mac) while the actual deploy target is Linux.

**Symptom:** after a local `bundle lock`, `Gemfile.lock`'s `PLATFORMS` section shows only a host-specific platform (e.g. `arm64-darwin-25`) instead of the generic `ruby`, and a gem with precompiled native variants (e.g. `nokogiri`) gets pinned to a platform-specific gem (`nokogiri-1.15.7-arm64-darwin`) that a Linux container can't load (`LoadError: cannot load such file -- nokogiri/nokogiri`).

**Fix:** force ruby-platform resolution on the host too, matching whatever the deploy image already does: `bundle config set --local force_ruby_platform true` before running `bundle lock`, then `bundle lock --add-platform ruby --remove-platform <the-polluting-platform>` if it already got added. Re-check `Gemfile.lock`'s `PLATFORMS` section reads `ruby` only before committing.

## `Kernel#open` on a URL (open-uri's monkeypatch) — behavior silently changes across Ruby/open-uri versions

**Symptom:** varies by Ruby/open-uri version, which is the trap — grepping for one exact error message from an old bug report will miss this on a different Ruby. Confirmed variants:
- Ruby 3.2.11 (open-uri 0.3.0): `Errno::ENOENT (No such file or directory @ rb_sysopen - https://...)` — `Kernel#open` falls all the way through to a literal file open on the URL string.
- Older Ruby/open-uri (seen in the wild on this same codebase, 2022 and 2023): `ArgumentError (bad argument (expected URI object or URI string))`, raised one frame further in, from open-uri's own deprecation-warning shim.

**Cause:** `open-uri` has, for years, monkeypatched `Kernel#open` so that `open("https://...")` transparently fetches the URL instead of opening a local file — a very old, once-idiomatic Ruby pattern. That monkeypatch has been progressively weakened and eventually removed across Ruby's stdlib open-uri releases (0.3.0, bundled with Ruby 3.2 in this case, no longer patches `Kernel#open` for URL strings at all). `URI.open` (the explicit, always-supported form) keeps working the whole time — only the implicit `Kernel#open` shortcut degrades.

**Confirmed real example (a live upgrade, Ruby 2.7.2 → 3.2.11):** an app model called `open(uri).read` to fetch a user-uploaded file from S3. This exact line had already been reported broken twice before, in 2022 and again in 2023 (two separate GitHub issues, both showing the identical `ArgumentError` above, both apparently closed without a real fix landing) — then the Ruby 2.7 → 3.2 bump changed the symptom to `Errno::ENOENT` and it was reported a third time. Three bug reports, one un-fixed root cause, across four years.

**Why the test suite and boot smoke test both missed it, three times:** two independent reasons stacked here, not just one — worth checking both when a bug like this survives an upgrade's verification steps:
1. The boot smoke test only boots the app; it never invokes this controller action at all.
2. Less obvious: the *feature's own test suite was green* the whole time because the test environment's file-attachment storage backend is local filesystem, not S3 — and the method containing the `open(uri)` call has an early return specifically for non-remote (non-`//`-prefixed) URLs. The buggy line is **structurally unreachable** under the test environment's config, regardless of how thorough the tests around it look. A green suite only proves the code paths it actually reaches were fine.

**Fix:** use `URI.open(uri)` explicitly — never bare `open(url_string)`. This works across all Ruby/open-uri versions, past and future.

**Detection tip:** grep for bare `open(` (not `File.open`, not `URI.open`, not `.open`) with a URL-shaped argument (a variable literally named `uri`/`url`, or a string starting with `http`). This pattern is a holdover from pre-2015-era Rails tutorials and shows up more often in older codebases than you'd expect. If the app has any history of "mysterious 500s on file download/upload that seem to fix themselves," this is worth checking even outside of an active version-upgrade — it can lie dormant for years and resurface on totally unrelated deploys.

## Default/bundled gems that stop being implicitly available

Ruby has been steadily moving stdlib libraries from "always loaded" to "bundled gem, needs an explicit `require`" across the 3.x series (`net-smtp`, `net-pop`, `net-imap`, and others made this move around Ruby 3.1; more libraries continue to move this direction in later releases — check the specific Ruby version's release notes rather than assuming a library seen here is still safe).

**Confirmed real example:** a re-lock during a Ruby upgrade (unrelated gem version bumps, not the Ruby bump itself) caused `OpenStruct` to no longer be implicitly available in a file that used it directly (`NameError: uninitialized constant OpenStruct`) — something else in the dependency chain had previously pulled in `require "ostruct"` as a side effect, and a version bump removed that transitive path.

**Fix:** add the explicit `require` for whatever stdlib class your code uses directly, rather than relying on some other gem to have required it first. Cheap, safe regardless of Ruby version, and exactly the kind of thing that should be true regardless of whether this specific instance was actually caused by the Ruby bump or a coincident gem bump.

**Confirmed real example — `ostruct` at Ruby 4.0 (a live upgrade, 3.4.9 → 4.0.4):** `ostruct` *leaves the default gems* in Ruby 4.0 (becomes a bundled gem). Under Bundler that means `require "ostruct"` is no longer satisfied unless the gem is in the Gemfile — and it's not app code that requires it here, it's **Rails' own boot path** (`zeitwerk` requires `ostruct`), so the app fails to *boot* on 4.0, not just at some app call site. Two things worth noting about how it was caught and fixed:
- **The pre-bump sweep on 3.4.9 caught it** as a warning (`ostruct ... will no longer be part of the default gems starting from Ruby 4.0.0`), emitted from inside zeitwerk. This is the payoff of Step 2's sweep running on the *current* minor: the removal is announced one minor ahead.
- **Fix is `gem "ostruct"` in the Gemfile** (not an app-code `require`), because the consumer is a dependency, not your own code. Harmless on the current Ruby, required on the target — so add it unconditionally, no `NextRails.next?` needed. This generalizes: when the thing that needs the now-bundled gem is a *gem* (especially a framework), the fix is a Gemfile entry, not a `require` in your app.

## A pinned linter/analyzer rejects the *new* Ruby as an unknown target (RuboCop)

**Symptom:** the app boots fine and the whole test suite is green, but the CI **lint** job dies with `RuboCop found unknown Ruby version: 3.4` (substitute whatever version you just bumped to), typically from `rubocop/runner.rb`.

**Cause:** a distinct failure mode from the two in the Gemfile-floor audit — the gem *installs and runs fine*; it just refuses to *analyze* against a Ruby it's too old to know about. RuboCop derives `TargetRubyVersion` (from `.ruby-version` / the Gemfile `ruby` directive when not set explicitly in `.rubocop.yml`), and a version of RuboCop released before your target Ruby existed has no entry for it and aborts rather than guessing. Confirmed real example (Ruby 3.3 → 3.4, a live upgrade): `rubocop 1.59.0` (Dec 2023) predates Ruby 3.4 and failed exactly this way; `bundle update rubocop rubocop-ast rubocop-rails rubocop-rails-omakase` (→ rubocop 1.88.1) fixed it, and the newer cops flagged no existing code.

**Why boot smoke and the suite both miss it:** neither runs the linter — this is *static analysis of your source against a version table*, orthogonal to whether the code runs. Only the lint step catches it, so on a project with a CI lint job, treat "bump the analyzer that pins TargetRubyVersion" as part of the hop, not an afterthought.

**Generalizes beyond RuboCop:** any tool that keys off a Ruby-version table — `rubocop` and its plugins, `standard`, `steep`/RBS tooling, some `brakeman`/`reek` versions — can reject a just-bumped Ruby as unknown. When bumping Ruby, bump the analyzers in the same hop and run each one once. The fix is always "move the tool forward," never "pin the Ruby back."

## Bundler 4 deprecates the per-OS windows platform symbols (`:mingw` / `:mswin` / `:x64_mingw`)

**Not a Ruby-version issue** — it fires on adopting **Bundler 4**, which frequently rides along with Ruby-upgrade work (a new Ruby ships a newer default bundler, or you bump bundler while you're in the lockfile anyway). Called out here because that's when people hit it.

**Symptom:** `bundle install` under Bundler 4 prints `[DEPRECATED] Platform :mingw, :mswin, :x64_mingw will be removed in the future. Please use platform :windows instead.` The usual trigger is the generated `tzinfo-data` line: `gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]`.

**Cause:** Bundler consolidated the three separate Windows platform symbols into a single `:windows` umbrella. The old symbols still work but are deprecated as of Bundler 4.

**Fix:** `gem "tzinfo-data", platforms: [:windows, :jruby]`. `:windows` covers mingw/mswin/x64_mingw; behavior-preserving, and clears the warning. (`:windows` has been accepted since Bundler 2.x, so it's safe even if some environment still runs an older bundler.)

**Reminder on scope:** Bundler-major mechanics like this belong to a *Bundler* upgrade, not a *Ruby* one — captured here only because the two commonly travel together. A Bundler-major bump deserves its own PR (see `workflows/landing-workflow.md` on why a Bundler major is independent of the Ruby major).
