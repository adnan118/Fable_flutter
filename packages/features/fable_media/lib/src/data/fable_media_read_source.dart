import 'package:fable_core/fable_core.dart';
import '../domain/media_read_models.dart';

/// RC126 source-verified operation IDs: Fable Backend RC66 media manifest,
/// controller and service. These are NOT inferred from UI labels.
final class FableMediaReadBindings {
  const FableMediaReadBindings({
    required this.runtimeContract,
    required this.metadata,
  });
  const FableMediaReadBindings.verified()
      : runtimeContract = 'media.client-contract',
        metadata = 'media.get';

  final String runtimeContract, metadata;

  void verify(OperationCatalog catalog) {
    if (runtimeContract == metadata) {
      throw StateError('Media read operations cannot alias each other');
    }
    final runtime = catalog.require(runtimeContract);
    final asset = catalog.require(metadata);
    // Even a matching ID is insufficient without the imported, enforced
    // route/method/auth policy from this particular generated Fable project.
    if (runtimeContract != 'media.client-contract' ||
        runtime.method.toUpperCase() != 'GET' ||
        runtime.path != '/media/client-contract' ||
        !runtime.requiresAuth || !runtime.enforceAuth) {
      throw StateError('Unverified protected media runtime operation');
    }
    if (metadata != 'media.get' ||
        asset.method.toUpperCase() != 'GET' ||
        !const {'/media/:id', '/media/{id}'}.contains(asset.path) ||
        !asset.requiresAuth || !asset.enforceAuth) {
      throw StateError('Unverified protected media metadata operation');
    }
  }
}

/// Data-only Fable adapter. Other Backend requires an independently verified
/// MediaMetadataReadPort with its own transport, identity and response schema.
/// The old map-shaped runtime responses never leave this file.
final class FableMediaReadSource implements MediaMetadataReadPort {
  FableMediaReadSource({
    required this.gateway,
    required OperationCatalog catalog,
    FableMediaReadBindings bindings = const FableMediaReadBindings.verified(),
    int Function()? identityRevision,
    bool Function()? isSessionCurrent,
  }) : _bindings = bindings {
    bindings.verify(catalog);
    if (gateway is FableAuthGateway) {
      if (identityRevision != null || isSessionCurrent != null) {
        throw ArgumentError('Fable media must use its own secure session identity');
      }
      final fable = gateway as FableAuthGateway;
      _identityRevision = () => fable.session.identityRevision;
      _isSessionCurrent = () => true;
    } else {
      // Explicit simulation adapter can be used with a fake gateway. Never
      // reuse Fable's global session for an external implementation.
      if (identityRevision == null || isSessionCurrent == null) {
        throw ArgumentError('Media reads require verified identity revision and session status');
      }
      _identityRevision = identityRevision;
      _isSessionCurrent = isSessionCurrent;
    }
  }

  final BackendApiGateway gateway;
  final FableMediaReadBindings _bindings;
  late final int Function() _identityRevision;
  late final bool Function() _isSessionCurrent;

  Future<Object?> _execute(String operationId, {Map<String, dynamic>? path}) async {
    final revision = _identityRevision();
    if (!_isSessionCurrent()) {
      throw StateError('Media read session is not active');
    }
    final response = await gateway.execute(operationId, path: path);
    if (!_isSessionCurrent() || _identityRevision() != revision) {
      // Never publish an account A response after switching to B.
      throw StateError('Media read identity changed; discard response');
    }
    return response.data;
  }

  @override
  Future<MediaRuntimeCapabilities> runtimeContract() async =>
      decodeFableRuntimeCapabilities(await _execute(_bindings.runtimeContract));

  @override
  Future<MediaAssetMetadata> metadata(String assetId) async {
    _validId(assetId);
    return decodeFableMediaAsset(
      await _execute(_bindings.metadata, path: {'id': assetId}),
      requestedId: assetId);
  }
}

final _uuidV4 = RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$');
void _validId(String id) {
  if (!_uuidV4.hasMatch(id)) throw ArgumentError('Invalid media asset id');
}

Map<String, Object?> _record(Object? input) {
  if (input is! Map) throw const FormatException('Invalid media read response');
  try {
    return Map<String, Object?>.from(input);
  } catch (_) {
    throw const FormatException('Invalid media response object');
  }
}

String _string(Object? value) {
  if (value is! String || value.isEmpty || value.length > 1024) {
    throw const FormatException('Invalid media text field');
  }
  return value;
}

int _positive(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Invalid media size/limit');
  }
  return value;
}

int? _optionalPositive(Object? value) =>
    value == null ? null : _positive(value);

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Invalid media capability flag');
  return value;
}

T _enum<T extends Enum>(Iterable<T> values, Object? value) {
  final text = _string(value).toLowerCase();
  for (final item in values) {
    if (item.name.toLowerCase() == text) return item;
  }
  throw const FormatException('Unknown media enum value');
}

/// Exact audited RC66 runtime fields. Any schema revision requires an explicit
/// source review; unrecognized data is not interpreted optimistically.
MediaRuntimeCapabilities decodeFableRuntimeCapabilities(Object? input) {
  final data = _record(input);
  if (data['schemaVersion'] != 12 ||
      data['storagePolicy'] != 'OPTIMIZED_PRIMARY') {
    throw const FormatException('Unsupported media runtime contract version');
  }
  final limits = _record(data['limits']);
  final features = _record(data['features']);
  final types = data['acceptedMimeTypes'];
  if (types is! List || types.isEmpty || types.length > 256 ||
      types.any((e) => e is! String ||
        e.length > 160 || !e.contains('/') || e.trim() != e)) {
    throw const FormatException('Invalid accepted media MIME types');
  }
  final maxParallel = _positive(limits['maxParallelParts']);
  if (maxParallel > 100) {
    throw const FormatException('Excessive media parallel upload limit');
  }
  return MediaRuntimeCapabilities(
    schemaVersion: 12,
    driver: _enum(MediaStorageDriver.values, data['driver']),
    maxUploadBytes: _positive(limits['maxUploadBytes']),
    maxParallelParts: maxParallel,
    acceptedMimeTypes: types.cast<String>(),
    resumableLargeUpload: _bool(features['resumableLargeUpload']),
    directPresignedMultipart: _bool(features['directPresignedMultipart']),
    serverAuthoritativeProgress: _bool(features['serverAuthoritativeProgress']),
  );
}

/// Exact media.service.assetView() projection. Never return its access.url,
/// backend storageKey, uploadedByUserId, technical metadata or grant secrets.
MediaAssetMetadata decodeFableMediaAsset(Object? input,
    {required String requestedId}) {
  _validId(requestedId);
  final envelope = _record(input);
  if (envelope['success'] == false) {
    throw const FormatException('Media metadata operation was not successful');
  }
  final data = envelope.containsKey('data')
      ? _record(envelope['data']) : envelope;
  return _asset(data, requestedId, depth: 0);
}

MediaAssetMetadata _asset(Map<String, Object?> data, String expectedId,
    {required int depth}) {
  final id = _string(data['id']);
  _validId(id);
  if (id.toLowerCase() != expectedId.toLowerCase()) {
    throw const FormatException('Media response asset identifier mismatch');
  }
  final access = _record(data['access']);
  final accessMode = _enum(MediaAssetAccessMode.values, access['type']);
  if (accessMode == MediaAssetAccessMode.protected &&
      access['url'] != null) {
    throw const FormatException('Protected asset cannot expose a direct URL');
  }

  final variantId = data['variant'];
  if (variantId != null && (variantId is! String || variantId.length > 40)) {
    throw const FormatException('Invalid media variant');
  }
  final parent = data['parentAssetId'];
  if (parent != null) {
    if (parent is! String) throw const FormatException('Invalid parent asset id');
    _validId(parent);
  }
  final variants = <MediaAssetMetadata>[];
  final inputVariants = data['variants'];
  if (depth == 0 && inputVariants is! List) {
    throw const FormatException('Media asset variant list is missing');
  }
  if (inputVariants != null) {
    if (inputVariants is! List || depth >= 1 || inputVariants.length > 32) {
      throw const FormatException('Invalid media variant list');
    }
    for (final entry in inputVariants) {
      final row = _record(entry);
      final childId = _string(row['id']);
      if (row['parentAssetId'] != expectedId) {
        throw const FormatException('Media variant parent mismatch');
      }
      variants.add(_asset(row, childId, depth: depth + 1));
    }
  }
  final bytes = _positive(data['sizeBytes']);
  final mime = _string(data['mimeType']);
  if (!mime.contains('/') || mime.length > 160) {
    throw const FormatException('Invalid asset MIME type');
  }
  return MediaAssetMetadata(
    id: id,
    kind: _enum(MediaAssetKind.values, data['kind']),
    visibility: _enum(MediaAssetVisibility.values, data['visibility']),
    originalName: _string(data['originalName']),
    mimeType: mime,
    sizeBytes: bytes,
    accessMode: accessMode,
    width: _optionalPositive(data['width']),
    height: _optionalPositive(data['height']),
    durationMs: _optionalPositive(data['durationMs']),
    parentAssetId: parent is String ? parent : null,
    variant: variantId is String ? variantId : null,
    variants: variants,
  );
}
