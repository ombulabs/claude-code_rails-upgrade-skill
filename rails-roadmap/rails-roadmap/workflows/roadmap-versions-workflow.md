# Roadmap Versions Workflow

**Purpose:** Establish where the app is, where it is going, and the exact ordered chain of hops
between the two — with Ruby bumps interleaved where a hop's floor demands one.

**When to use:** Step 3 of `workflows/roadmap-orchestration-workflow.md`, before any surveying.
Everything downstream is keyed off the hop chain this produces.

---

## Step 1: Read the current state

All four reads are read-only and independent — batch them.

| What | Where | How |
|---|---|---|
| Exact Rails version | `Gemfile.lock` | The `rails (X.Y.Z)` line under `specs:`. Grep `^    rails \(` |
| Ruby version | `.ruby-version`, then `Gemfile` (`ruby "X.Y.Z"`), then `.tool-versions` (`ruby X.Y.Z`) | First one that exists wins; note which |
| `load_defaults` | `config/application.rb` | `config.load_defaults X.Y` |
| Project name | `config/application.rb` module name, else the directory name | |

**Use `Gemfile.lock`, not `Gemfile`, for the Rails version.** The Gemfile usually holds a
constraint (`~> 7.0`); the lockfile holds the resolved truth. A roadmap built off `~> 7.0` when
the app actually runs 7.0.4 will compute the wrong first step.

If there is no `Gemfile.lock`, say so and stop. Without it there is no reliable current version
and no gem compatibility check — a roadmap would be guesswork.

**Record a `load_defaults` gap if one exists.** An app on Rails 7.0 with `load_defaults 5.2` is
carrying configuration debt that is invisible to the version hop and has to be paid down
separately. It becomes its own section in the document, and the roadmap should point at the
`rails-load-defaults` plugin rather than trying to plan that work here.

---

## Step 2: Resolve the destination

If the user passed a target version as an argument, that is the destination — skip to Step 3.

Otherwise resolve the latest stable Rails from the RubyGems API. This is the same technique the
`rails-upgrade` skill already uses for latest-patch lookup; reuse it rather than inventing
another:

```bash
curl -s https://rubygems.org/api/v1/versions/rails.json | \
  ruby -rjson -e '
    versions = JSON.parse(STDIN.read)
      .map { |v| v["number"] }
      .reject { |v| v =~ /[a-z]/ }        # drop rc / beta / alpha
      .sort_by { |v| Gem::Version.new(v) }
    puts versions.last
  '
```

Dropping any version containing a letter is what keeps a release candidate from becoming the
roadmap's destination.

If the network is unavailable, fall back to the highest version for which a pattern file exists
in the resolved catalog, and **say in the document that the destination was resolved offline**
and may not be the true latest.

---

## Step 3: Get on the latest patch of the current series first

Before the first hop, the app should be on the latest patch of the series it is already on.
This is step zero of every FastRuby upgrade and it belongs at the top of the roadmap.

For end-of-life series the latest patch is frozen; the static table lives in the `rails-upgrade`
skill's multi-hop strategy reference. For active series, resolve at runtime with the same
RubyGems query as Step 2, filtered to the series prefix:

```bash
curl -s https://rubygems.org/api/v1/versions/rails.json | \
  ruby -rjson -e '
    series = ARGV[0]
    versions = JSON.parse(STDIN.read)
      .map { |v| v["number"] }
      .reject { |v| v =~ /[a-z]/ }
      .select { |v| v.start_with?(series) }
      .sort_by { |v| Gem::Version.new(v) }
    puts versions.last
  ' "7.0."
```

If the app is already on the latest patch, emit nothing — do not pad the roadmap with a
satisfied step.

---

## Step 4: Compute the hop chain

Rails upgrades are sequential; no skipping. Enumerate every minor between current and
destination in order. From 6.1 to 8.1 that is:

```
6.1 → 7.0 → 7.1 → 7.2 → 8.0 → 8.1     (5 hops)
```

For each hop record the pattern file basename (`rails-<MAJORMINOR>-patterns.yml`, no dot —
`rails-72-patterns.yml` for the 7.2 hop) and the Ruby floor from
`references/external-guides.md`.

Mark any hop whose pattern file is absent from the resolved catalog as
`NOT SURVEYED — pattern file missing`. Never let a missing file read as a clean hop.

---

## Step 5: Resolve the Ruby target and interleave bumps

Two separate questions. Do not conflate them.

**What Ruby does the destination Rails require?** Ask RubyGems for the release's own declared
constraint:

```bash
curl -s https://rubygems.org/api/v2/rubygems/rails/versions/8.1.0.json | \
  ruby -rjson -e 'puts JSON.parse(STDIN.read)["ruby_version"]'
```

**What Ruby should the app actually land on?** The latest stable patch of a currently supported
Ruby line — higher than the floor, so the same work isn't repeated at the next hop that raises
it. Resolve this at runtime.

> **Verify whichever endpoint you use before relying on it.** `endoflife.date/api/ruby.json` is
> the obvious candidate but was not reachable during development, so it is unconfirmed. If the
> lookup fails, fall back to the destination Rails' declared floor, round up to the next stable
> minor, and **say in the document that the Ruby target is a floor-derived estimate** rather
> than a verified latest.

> **Do not use `bundle_report ruby_check`.** It is broken in `next_rails` 1.4.8: the CLI passes
> a String to `compatible_ruby_version`, which indexes it with a Symbol, raising
> `TypeError: no implicit conversion of Symbol into Integer`. The method's entire body is the
> RubyGems v2 call shown above — call that directly instead.

Then walk the hop chain in order, carrying the app's current Ruby. When a hop's floor exceeds
the Ruby carried, emit a **Ruby bump step immediately before that hop** and update the carried
version. An app already above every floor in its chain gets no Ruby steps; say that explicitly
rather than emitting a no-op.

---

## Step 6: Emit the chain

Hand the orchestration workflow an ordered list. Each entry is either a Rails hop (from, to,
pattern file, Ruby floor, guide links, `ACTIONABLE` for the first hop and `INDICATIVE` after)
or a Ruby bump (from, to, the hop that forced it).

Worked example — Rails 6.1.7.10 on Ruby 3.0.6, destination 8.1:

```
0. Patch     Rails 6.1.7.10 -> 6.1.7.12      (latest patch of current series)
1. Hop       Rails 6.1 -> 7.0    ACTIONABLE   floor 2.7.0   ok
2. Hop       Rails 7.0 -> 7.1    INDICATIVE   floor 2.7.0   ok
3. Ruby      3.0.6 -> 3.3.x                   required by hop 4
4. Hop       Rails 7.1 -> 7.2    INDICATIVE   floor 3.1.0
5. Hop       Rails 7.2 -> 8.0    INDICATIVE   floor 3.2.0   ok
6. Hop       Rails 8.0 -> 8.1    INDICATIVE   floor 3.2.0   ok
```

One Ruby step, placed where the floor first bites, sized to clear every later floor too.
