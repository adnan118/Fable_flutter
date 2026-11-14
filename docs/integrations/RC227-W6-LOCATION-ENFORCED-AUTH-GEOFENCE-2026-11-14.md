# RC227 — W6 Location: enforced Auth contracts and valid finite Geofence distances

Date: 2026-11-14. Direct base Flutter RC226 `cd217230e8d06536f1c7af3541b83354b56e2439`; private Backend RC209 unchanged.

Previously `FableLocationOperations._checked` accepted GET/POST roles where `requiresAuth=true` even when the imported operation had `enforceAuth=false` (the FableOperation default). It also allowed URL fragments. RC227 now requires both **declared and enforced** authenticated operations and rejects credential-header, dynamic path, query and fragment operations. Existing explicit operation IDs, exact GET/POST methods, provider restrictions and payload validation remain intact.

`FableGeofenceDecision.fromFable` previously accepted negative, NaN or infinite numeric `distanceMeters` from Backend, potentially passing malformed distance data into the UI. RC227 rejects any nonnumeric/nonfinite/negative distance; `null`, valid zero and finite nonnegative distance remain supported. `inside` must still be boolean. This is a decoder guard, not proof the backend geofence calculation is geographically accurate.

Added 3 new Dart location regression cases (8 total) to `location_repository_test.dart`, plus six Node source guards in `test/rc227-location-contract-geofence-source.test.mjs`, automatically selected by the existing developer command `pnpm fable:all`. **11/11 isolated V8 source/wiring assertions PASS** on candidate GitHub blobs. Full Node suite/Dart/Flutter, actual Maps provider, location permissions, physical devices and W7/W8 release signoff have **not** run here. Original W0 82 acceptance evidence items remain open; production **NO_GO**. No prior historical source or contracts removed, no GitHub Actions.
