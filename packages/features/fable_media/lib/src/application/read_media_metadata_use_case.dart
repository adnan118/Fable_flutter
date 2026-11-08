import '../domain/media_read_models.dart';

/// Typed application entrypoint; no Backend route IDs, Dio, JSON or Flutter.
/// Data adapters enforce authenticated identity and declared operation policy.
final class ReadMediaMetadataUseCase {
  const ReadMediaMetadataUseCase(this.source);
  final MediaMetadataReadPort source;

  Future<MediaRuntimeCapabilities> runtimeContract() =>
      source.runtimeContract();

  Future<MediaAssetMetadata> metadata(String id) {
    if (!RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
    ).hasMatch(id)) {
      throw ArgumentError('Invalid media asset id');
    }
    return source.metadata(id);
  }
}
