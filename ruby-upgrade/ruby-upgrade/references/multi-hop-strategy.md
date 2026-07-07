# Multi-Hop Ruby Upgrade Strategy

Planning a Ruby upgrade that spans more than one minor version, and why the default is to not do that in a single hop.

---

## Default: One Minor at a Time

```
2.7 → 3.0 → 3.1 → 3.2 → 3.3 → 3.4
```

Each hop's own deprecation-warning sweep (Step 2 of `SKILL.md`) is what surfaces the *next* hop's removals ahead of time, on a Ruby that still runs the old code path so the fix can be verified incrementally. Collapsing several hops into one means several minors' worth of removals surface simultaneously, with no way to tell which removal caused which failure without bisecting the bump itself.

## When Multi-Hop Is the Right Call

Only when the user explicitly asks for it, and typically for one of:

- A small application with a thin dependency surface, where the risk of compound breakage is genuinely low.
- A spike, exercise, or throwaway environment, not a production system with real users.
- An app the user has already audited by other means (e.g. a very recent, thorough test-suite pass and manual review) and is knowingly accepting the risk to save time.

## How to Run a Multi-Hop Upgrade

1. **State the sequential default and what's being traded away.** Don't silently comply with a multi-hop request — confirm the user understands skipped hops mean skipped deprecation-warning coverage for the skipped minors.
2. **Plan the full hop sequence anyway**, even though you're executing it as one Gemfile change. Read every intermediate version's `version-guides/upgrade-X.Y-to-X.Z.md` file, not just the final target's — a removal from an intermediate minor is just as real as one from the final hop, and won't have its own guide once you skip past it.
3. **Run Step 2's deprecation sweep before bumping at all**, same as a single hop — it only catches what the *current* Ruby already warns about, which is a subset of everything that will actually break, but it's still real signal and costs nothing extra to run first.
4. **Bump straight to the final target version** (Gemfile, `.ruby-version`, Dockerfile), not through each intermediate version's Gemfile state — there's no benefit to briefly pinning an intermediate version you're not going to commit.
5. **Run Step 5's boot smoke test and expect compound failures.** A single stack trace may only reveal the *first* thing that broke; fixing it and re-running may reveal a second, third, and fourth issue in sequence, each hiding behind the previous one. Budget for several fix-and-retry cycles, not one.
6. **Run the full test suite and treat every new failure as potentially having a distinct root cause** — resist the urge to assume "it's probably the same issue as before" once multiple minors' worth of removals are in play at once.
7. **Land it and document the compound findings** — see `SKILL.md` Step 7, and add anything new to `references/known-gotchas.md` for the next multi-hop or single-hop project that hits the same thing.

## What Doesn't Change

Everything else in `SKILL.md`'s workflow still applies — latest-patch-first (Step 0), a green test suite before starting (Step 1), the Gemfile audit (Step 3), and landing verification in a deploy-shaped environment (Step 7). Multi-hop changes *how much surfaces at once* in Steps 2 and 5, not whether the surrounding steps are still required.
