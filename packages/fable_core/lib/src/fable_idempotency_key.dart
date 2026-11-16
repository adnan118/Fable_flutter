import 'dart:math';

/// RC304 — unpredictable request key, generated once for each intentional
/// authenticated write. The verified Fable gateway refuses unsigned usage.
///
/// Deliberately no persistence, logging, deterministic seed or auto retry.
/// Ambiguous network outcomes require a fresh server-state check by the user.
abstract final class FableIdempotencyKey {
  static String generate() {
    final secure=Random.secure();
    return List<int>.generate(32,(_)=>secure.nextInt(256))
      .map((part)=>part.toRadixString(16).padLeft(2,'0')).join();
  }
}
