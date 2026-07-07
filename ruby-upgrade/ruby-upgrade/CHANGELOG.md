# Changelog

## Unreleased
- Initial version of the skill. Sequential, one-Ruby-minor-at-a-time methodology mirroring `rails-upgrade`, plus a Step 2 (mandatory) deprecation-warning sweep using `RUBYOPT="-W:deprecated"` before bumping. `references/known-gotchas.md` seeded with confirmed real findings from a live Ruby 2.7 → 3.2.11 upgrade (fastruby/audit): `Proc.new`-with-no-block removal (aws-sdk v2), `URI.escape` removal (paperclip → kt-paperclip fork), re-adding `spring` after a Ruby floor is met still needing `Spring.dangerously_allow_disabling_reloading`, Docker base-image OS moves invalidating old workarounds, host-platform `bundle lock` pollution, and default gems losing implicit availability.
