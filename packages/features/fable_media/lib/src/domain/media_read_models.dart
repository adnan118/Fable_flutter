/// Public media-read value types are independent of Fable, HTTP, JSON,
/// credentials, signed URLs, Flutter and storage drivers' internal keys.
enum MediaStorageDriver { local, s3, r2, hybrid }
enum MediaAssetKind { image, video, audio, document }
enum MediaAssetVisibility { public, private }
enum MediaAssetAccessMode { protected, public, signed, authenticated }

/// Audited source fields from Backend media.service.clientContract() (RC66).
/// Additional Backend fields are deliberately not guessed/exposed.
final class MediaRuntimeCapabilities {
  MediaRuntimeCapabilities({
    required this.schemaVersion,
    required this.driver,
    required this.maxUploadBytes,
    required this.maxParallelParts,
    required List<String> acceptedMimeTypes,
    required this.resumableLargeUpload,
    required this.directPresignedMultipart,
    required this.serverAuthoritativeProgress,
  }) : acceptedMimeTypes = List<String>.unmodifiable(acceptedMimeTypes);
  final int schemaVersion, maxUploadBytes, maxParallelParts;
  final MediaStorageDriver driver;
  final List<String> acceptedMimeTypes;
  final bool resumableLargeUpload, directPresignedMultipart,
      serverAuthoritativeProgress;
}

/// Safe GET /media/:id projection: no storageKey, owner, metadata object,
/// signed URL, bearer token, private download URL or playback grant.
final class MediaAssetMetadata {
  MediaAssetMetadata({
    required this.id,
    required this.kind,
    required this.visibility,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.accessMode,
    required List<MediaAssetMetadata> variants,
    this.width,
    this.height,
    this.durationMs,
    this.parentAssetId,
    this.variant,
  }) : variants = List<MediaAssetMetadata>.unmodifiable(variants);

  final String id, originalName, mimeType;
  final MediaAssetKind kind;
  final MediaAssetVisibility visibility;
  final MediaAssetAccessMode accessMode;
  final int sizeBytes;
  final int? width, height, durationMs;
  final String? parentAssetId, variant;
  final List<MediaAssetMetadata> variants;

  /// Deliberately excludes transient access URLs and backend storage details.
  @override
  String toString() =>
      'MediaAssetMetadata(id: $id, kind: $kind, accessMode: $accessMode)';
}

/// Feature-owned port. External Backends MUST provide a separately verified
/// implementation: never inherit Fable route IDs or response decoders.
abstract interface class MediaMetadataReadPort {
  Future<MediaRuntimeCapabilities> runtimeContract();
  Future<MediaAssetMetadata> metadata(String assetId);
}
