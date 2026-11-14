# RC226 — W6 Messaging: enforce client-send authentication and exclude webhooks

Date: 2026-11-14. Built on Flutter RC225 `136bd9396760baa5b9e756c3da014ff8cd281d35`; private Backend RC209 unchanged.

The existing `FableMessageOperations.fromContract` accepted a `POST` with `requiresAuth=true` even when the contract did **not** enforce bearer authentication (`enforceAuth=false`). Its webhook rejection was also case-sensitive. An imported `/api/WEBHOOKS/receive` or `phone.WebHook.Receive` could therefore be misclassified as a client-send operation.

RC226 now requires a real `POST` with `requiresAuth && enforceAuth`, refuses external credential headers and fragment/query/dynamic routes, and blocks webhook path/operation identifiers case-insensitively. It does **not** infer an SMS/WhatsApp provider or add any sending API. A client-send operation still must be declared in an imported verified Backend contract. `FableMessagingRepository.send()` keeps its single `gateway.execute` and **no automatic retries** because a timed-out message might already have been sent.

Regression evidence: four Dart contract tests (valid send, server webhook, weak/anonymous auth, mixed-case webhook/fragment) and five Node source guards. All are included under the same one-command `pnpm fable:all`. **12/12 isolated V8 source/wiring assertions passed** against candidate GitHub blobs. Full Dart/Flutter tests, real SMS provider, Android/iOS and production W6/W7/W8 were not run in the model environment. Original W0 82 evidence items remain outstanding. Source-level fix only; production **NO_GO**. No existing history or feature code discarded.
