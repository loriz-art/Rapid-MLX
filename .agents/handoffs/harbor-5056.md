# Composer loading coverage continuation — PR #5056

Receiving roles: Pixel and Atlas; Harbor owns validation and release integration.
Branch: `pixel/composer-model-loading`; PR: #5056.

## Verified facts

- Compared current main history, release notes, and related merged composer PRs:
  the loading slot and managed download ownership remain unique work.
- The earlier 426/517 result was a manual Swift LLVM/LCOV intersection, not a
  failed GitHub coverage job. GitHub's changed-lines-coverage job skipped this
  Swift-only diff. The prior validator never acquired its lock.
- Added native regression checks for the 30-view development capture matrix,
  global-strip subprocess retry, empty status rendering, silent decision-state
  transitions, repeated blocked Return, acceleration badge layout, and the
  reduced-motion segment. The capture matrix and segment renderer now have
  internal test seams; the application renders the same views and motion policy.
- 307 targeted Swift tests passed in 27 suites with coverage enabled.
- Verified the validator's tooltip finding against the source: Resume inherited
  Stop help text. Added localized Resume help and mounted accessibility
  assertions for both states; the 307-test rerun passed.
- LLVM/LCOV intersection with added Swift source lines measures 530/547 (96.89%).
  No exclusions or waiver were applied. No existing Swift coverage exclusion
  convention was found. All 17 remaining mapped lines are listed below.

## Remaining mapped lines

- `apps/rapid-mac/Sources/Rapid/DevSnapshot.swift`: 819, 820, 823, 824, 884, 885, 886, 887, 888.
- `apps/rapid-mac/Sources/Rapid/UI/ChatView.swift`: 294, 947, 948.
- `apps/rapid-mac/Sources/Rapid/UI/ContentView.swift`: 778, 779, 780, 781, 1452.

The snapshot-session lines include comments assigned LCOV line records and the
call from the full capture session into the tested matrix. ChatView includes a
SwiftUI state-wrapper initializer that remains zero-count despite the blocked
Return test exercising both attention assignments, and the native diagnostics
save-panel callback. ContentView lines require the complete application shell
and its startup/environment dependencies; isolated ChatView tests do not execute
them. The segment's read-only system environment is still used by the app; the
test supplies the same decision to the renderer without changing system settings.

## Reproduction

From `apps/rapid-mac`, run:

```sh
swift test --enable-code-coverage --filter 'Composer|CoreWorkspaceVisualFoundation|Localization|DownloadManager|DownloadProgress|ModelReadiness|ReadinessModelStart|MountedRecoverySurfaces|ReadinessRecoveryActionWiring|StartAndSendIntent|ConversationDraft|ChatAttachmentDraft|ChatSlowStreamStopGolden|ChatMessageActionsGolden'
xcrun llvm-cov export -format=lcov \
  -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata \
  .build/arm64-apple-macosx/debug/RapidPackageTests.xctest/Contents/MacOS/RapidPackageTests
```

Intersect LCOV `DA` line records with new-side ranges in
`git diff --unified=0 origin/main -- apps/rapid-mac/Sources`, retaining all mapped
lines, including zero-count records, without exclusions. Count positive records
as covered. The denominator changed because the existing capture matrix moved
into a callable helper and gained its explicit rendering callback.

## Risk and next action

The strict 100% requirement is unmet. Do not merge under the release sweep until
it is satisfied. Pixel/Atlas should provide isolated full-shell/snapshot-session
and save-panel evidence and resolve the generated state-initializer mapping, or
obtain a human decision on a documented exclusion policy. No new exclusion
policy, product behavior changes, or architectural expansion is authorized by
this continuation. Harbor must retain an exact-head serialized validator verdict
and green build/desktop-tests evidence before any eventual merge.
