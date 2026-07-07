# Ruby Upgrade Report Template

```markdown
# Ruby Upgrade Report: X.Y.Z → A.B.C

## Summary
- Current version: X.Y.Z (patch check: <latest / behind, see Step 0>)
- Target version: A.B.C
- Hop type: single-minor / multi-hop (explicit exception, confirmed by user on <date>)

## Step 0: Latest Patch Check
- Current: X.Y.Z
- Latest patch of X.Y series: X.Y.W
- Action: <none needed / bumped to X.Y.W first, deployed separately>

## Step 1: Test Suite Baseline
- Framework: RSpec / Minitest / none found
- Result: N tests, N passing, 0 failing
- (If no suite: link to the no-test-suite smoke baseline result instead)

## Step 2: Deprecation Warning Sweep
- Command: RUBYOPT="-W:deprecated" <test command>
- Result: N unique warnings (M app-code, K gem-code)

### App-code warnings (fixed)
- <file>:<line> — <description> — <fix applied>

### Gem-code warnings (tracked)
- <gem> <version> — <description> — <newer release available? fork? deferred to next hop?>

## Step 3: Gemfile Ruby-Floor Audit
| Gem | Current version | Declared Ruby floor | Blocker? | Resolution |
|-----|-----------------|---------------------|----------|------------|
| ... | ... | ... | ... | ... |

## Step 4: Version Bump
- Gemfile: `ruby "A.B.C"` (was `"X.Y.Z"`)
- `bundle lock` result: clean / conflicts resolved (list below)

## Step 5: Boot Smoke Test
- Command: <actual boot command>
- Result: PASS (after N fix-and-retry cycles)
- Fixes applied: <gem> <old> -> <new> — <what broke>

## Step 6: Fix/Test Loop
- Final test suite result: N tests, N passing, 0 failing

## Step 7: Landing Checklist
- [ ] .ruby-version
- [ ] Gemfile `ruby` directive
- [ ] Dockerfile base image (if applicable)
- [ ] CI config
- [ ] Verified in deploy-shaped environment (Docker/CI run: <link>)

## Deferred to Next Hop
- <any warning/finding explicitly not fixed this hop, and why>

## Risk Assessment
- Overall confidence: High / Medium / Low
- Notes: <anything unusual — multi-hop compound risk, no-test-suite partial baseline, etc.>
```
