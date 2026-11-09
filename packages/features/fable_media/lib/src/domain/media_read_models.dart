/// Public media-read value types are independent of Fable, HTTP, JSON,
/// credentials, signed URLs, Flutter and storage drivers' internal keys.
enum MediaStorageDriver { local, s3, r2, hybrid }
enum MediaAssetKind { image, video, audio, document }
enum MediaAssetVisibility { public, private }
// RC127 policy: public APIs may expose metadata, never direct media bytes.
enum MediaAssetAccessMode { protected }

/// RC136 media content-encryption tiers, independent of authorization.
/// NONE still requires Backend playback grants and private storage.
/// LOCAL uses Backend-only AES-256-GCM at rest. The Flutter app NEVER sees keys.
/// DRM uses licensed Widevine/FairPlay KSM/CDM and must never fall back to clear.
enum MediaEncryptionTier { none, local, drm }

extension MediaEncryptionTierDeveloperLabels on MediaEncryptionTier {
  String get labelAr => switch (this) {
    MediaEncryptionTier.none => 'بدون تشفير محتوى',
    MediaEncryptionTier.local => 'تشفير محلي دون أي اشتراك',
    MediaEncryptionTier.drm => 'DRM عبر Widevine / FairPlay',
  };
  String get explanationAr => switch (this) {
    MediaEncryptionTier.none =>
      'جلسات وصلاحيات محمية؛ الملفات نفسها غير مشفرة بتشفير التطبيق.',
    MediaEncryptionTier.local =>
      'AES-256-GCM على السيرفر فقط؛ لا مفتاح في Flutter ولا حماية DRM ضد نسخ المحتوى بعد فكّه.',
    MediaEncryptionTier.drm =>
      'يتطلب خادم تراخيص مرخصًا ومشغل DRM؛ لا بديل تلقائي غير مشفر.',
  };
  bool get requiresExternalLicense => this == MediaEncryptionTier.drm;
  bool get clientReceivesEncryptionKey => false;
}

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
    this.encryptionTier = MediaEncryptionTier.none,
    this.encryptionTierVerified = false,
  }) : acceptedMimeTypes = List<String>.unmodifiable(acceptedMimeTypes);
  final int schemaVersion, maxUploadBytes, maxParallelParts;
  final MediaStorageDriver driver;
  /// The Backend is the only authority for the selected tier.
  final MediaEncryptionTier encryptionTier;
  /// false for older runtime contracts which predate RC136; do not infer LOCAL.
  final bool encryptionTierVerified;
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
