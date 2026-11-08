import 'package:fable_core/fable_core.dart';
import 'data/fable_media_read_source.dart';
import 'domain/media_read_models.dart';

/// Source-compatible constructor boundary for older generated clients.
/// A bare gateway is intentionally INERT: it no longer guesses operation IDs
/// or publishes raw backend response maps. Supply the selected project's
/// verified OperationCatalog to enable authenticated typed reads.
///
/// New generated features should inject ReadMediaMetadataUseCase with a
/// MediaMetadataReadPort at their application composition root instead.
@Deprecated('Use ReadMediaMetadataUseCase / FableMediaReadSource with catalog')
final class FableMediaReadRepository implements MediaMetadataReadPort {
  FableMediaReadRepository(this.gateway, {
    OperationCatalog? catalog,
    FableMediaReadBindings bindings = const FableMediaReadBindings.verified(),
    int Function()? identityRevision,
    bool Function()? isSessionCurrent,
  }) : _verified = catalog == null ? null : FableMediaReadSource(
    gateway: gateway,
    catalog: catalog,
    bindings: bindings,
    identityRevision: identityRevision,
    isSessionCurrent: isSessionCurrent,
  );

  final BackendApiGateway gateway;
  final FableMediaReadSource? _verified;

  FableMediaReadSource _source() {
    final source = _verified;
    if (source == null) {
      throw StateError(
        'Media read disabled: import the exact verified project OperationCatalog');
    }
    return source;
  }

  @override
  Future<MediaRuntimeCapabilities> runtimeContract() =>
      _source().runtimeContract();

  @override
  Future<MediaAssetMetadata> metadata(String id) =>
      _source().metadata(id);
}
