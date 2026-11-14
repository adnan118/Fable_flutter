# RC215 — W6 Notifications identity and refresh races

Date: 2026-11-14. Based directly on merged Flutter RC214 `b7e68843f93f5258f4ddb3007e00379d0cf193ff`.

## Concrete corrections
1. `FableInboxPage._read()` previously queued refresh events when mark-read was busy, but unlike `_load()` it never drained `_refreshQueued` on completion. An identity change or foreground push during the mutation could therefore leave the current user's inbox blank/unrefreshed until manual intervention. It now drains the queue once the busy slot clears and does not launch a duplicate normal reload.
2. `FableNotificationNavigation.openVerifiedInternalRoute()` previously returned the awaited handler result without checking whether the authenticated identity changed while a sensitive password route was open. It now captures the notification navigation revision and optional current Auth identity revision; obsolete confirmations return false. Password recovery remains available while signed out and remains restricted to a registered, verified app-local route — never an arbitrary URL.

## Tests
Added three Dart test cases to existing `notification_identity_navigation_rc108_test.dart`: late route result after identity switch, cancellation while pending, unchanged same-account route. Added five Node source guards in `test/rc215-w6-notification-races-source.test.mjs`. Reproduction:

```sh
npm run test:w6:notifications:source
npm run test:w6:notifications
flutter analyze
```

These tests are authored in GitHub; no native Flutter/Dart execution has been claimed in this environment. The origin and destination binding in the registered navigation callback remains the app's own responsibility. The code checks the epoch before and after the awaited callback; it cannot undo an already performed native navigation side-effect.

W6 is **not closed**: Auth and Notifications source fixes do not approve the other 15 feature families. Real Android/iOS, external provider, database and full 17-family acceptance remain independent blockers. W7/W8, 82 W0 evidence items and production remain open. Backend main RC209 unchanged. No GitHub Actions required.
