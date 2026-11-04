import 'dart:async';
import 'media_byte_source.dart';

/// Session invalidation is a transport-agnostic capability: no Fable account,
/// media token, URL, HTTP exception or native player type reaches Domain.
enum MediaSessionInvalidation {
  accountChanged,
  credentialsRotated,
  playbackEnded,
  sourceClosed,
}

/// Optional contract for protected playback byte sources. Any player bridge
/// that consumes a source MUST subscribe to invalidations and stop/discard
/// buffered bytes on an event; do not treat a successful old range as proof
/// that playback remains authorized.
abstract interface class SessionBoundMediaByteSource implements MediaByteSource {
  /// Must deliver revocations synchronously if the implementation owns a
  /// synchronous identity-event source (to avoid A->B playback races).
  Stream<MediaSessionInvalidation> get invalidations;

  /// Returns false once the associated source or credentials become stale.
  bool get isActive;

  /// Cancels pending reads without ending the backend's playback session.
  void cancelPendingReads();

  /// Releases listeners and stops this source; it does not revoke the server
  /// session. The owner must separately issue server-authoritative end().
  Future<void> close();
}
