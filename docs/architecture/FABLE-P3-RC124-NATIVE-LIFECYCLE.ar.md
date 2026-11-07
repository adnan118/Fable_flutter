# RC124 — Native protected player pause/resume/seek and identity invalidation

**Owner/track:** Fable Track A (P3), continuing RC123 merged Flutter/main
`1dd02f19336d728b17a020b860529cdb18a12348`. This branch is isolated;
no Backend changes, no changes to original 17-family acceptance, and no local
working tree overwrite.

## Actual code changes

- The Dart native port exposes additional typed `playing`, `paused`,
  and `seeked` events, checked against current nonsecret lease ID and seek
  generation exactly like the existing decoder status. They are observations
  from native players, not method-channel ACKs or permission grants.
- Android Media3 listens to `Player.Listener.onIsPlayingChanged` and
  `onPositionDiscontinuity(...SEEK)` with the existing session/generation
  fences. Native teardown idempotence from RC123 remains intact.
- iOS AVPlayer observes `timeControlStatus` via owned KVO, invalidates
  observation on stop, and reports a seek completion callback only when
  the decoder still owns the lease/epoch. UIScene/Xcode27 is preserved.
- An original deterministic **8-second 64×64 5fps H.264 Baseline, silent MP4**
  is generated locally by ffmpeg for stable real-time pause and 5s seek
  testing (no third-party media). Fixture binary is audited for size, Git blob `027ed85648fe724dcc77a89aea493e6ef67daeb9` and SHA256 `b53078768a0c1c322805863ecb522da359b0f3fce86f258d62d02218fd81c1ff`.
- Cross-platform `integration_test/rc124_native_player_lifecycle_test.dart`
  uses the actual protected Dart→Native decoder bridge, requiring native
  readiness, native playing, native paused, seek completion, native resumption,
  native ended; it also holds the real native byte request while simulating
  account revocation and deliberately releases a stale response later.
  No bearer token, JWT, remote URL, or Backend credentials are used.

## Acceptance rules (fail closed)

`rc122-codec-simulator.yml` runs BOTH the RC122 original codec test and
RC124 native lifecycle on **Xcode27 iOS27 simulator**. `rc123-media3-emulator.yml`
runs both on **Android API35 hardware-accelerated emulator**. Baseline three
jobs (Flutter/analyze/all packages; Android debug APK; Xcode27 iPhone+iPad
UIScene build+launch) remain mandatory for any PR. Do not merge if ANY test
fails. Log the failed step, correct the actual player, and repeat on same
exact head. Independently verify `main` after merging.

## Limits

Real simulator decoder events are *not* physical devices, real Backend/MySQL/R2,
auth 401/403/token rotation or asset-version checks. Native invalidation uses a
controlled in-memory source, not a deployed revocation event. AAC/audio and
HLS/DASH/DRM are not covered. Source tests do not move `#15`
`liveE2EVerified` from false. Track B architectural debts and P0 complete
private Backend+Flutter ZIP remain separate.
