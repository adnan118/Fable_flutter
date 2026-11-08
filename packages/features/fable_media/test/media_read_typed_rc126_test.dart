import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '123e4567-e89b-42d3-a456-426614174000';
const _child = '123e4567-e89b-42d3-a456-426614174001';

FableOperation _op(String id, String method, String path, {
  bool requiresAuth = true,
  bool enforceAuth = true,
}) => FableOperation(
  id, method, path, List.filled(64, 'b').join(),
  requiresAuth: requiresAuth, enforceAuth: enforceAuth,
);

FableContract _catalog({
  String runtimeId = 'media.client-contract',
  String metadataId = 'media.get',
  String runtimeMethod = 'GET',
  String metadataMethod = 'GET',
  String metadataPath = '/media/:id',
  bool metadataAuth = true,
  bool metadataEnforced = true,
}) => FableContract(
  contractHash: List.filled(64, 'a').join(),
  operations: {
    runtimeId: _op(runtimeId, runtimeMethod, '/media/client-contract'),
    metadataId: _op(metadataId, metadataMethod, metadataPath,
      requiresAuth: metadataAuth, enforceAuth: metadataEnforced),
  },
  featureIds: const {'media'}, projectName: 'rc126-audited-source',
  selectionMode: 'explicit',
);

Map<String, Object?> get _runtime => {
  'schemaVersion': 12,
  'driver': 'r2',
  'storagePolicy': 'OPTIMIZED_PRIMARY',
  'limits': {'maxUploadBytes': 60000000, 'maxParallelParts': 4},
  'features': {
    'resumableLargeUpload': true,
    'directPresignedMultipart': true,
    'serverAuthoritativeProgress': true,
  },
  'acceptedMimeTypes': ['image/jpeg', 'video/mp4'],
};

Map<String, Object?> _asset(String id, {
  String type = 'signed',
  String? parent,
  List<Object?> variants = const [],
}) => {
  'id': id, 'kind': 'VIDEO', 'visibility': 'PRIVATE',
  'originalName': 'travel.mp4', 'mimeType': 'video/mp4',
  'sizeBytes': 4040, 'width': 1920, 'height': 1080,
  'durationMs': 9000,
  'parentAssetId': parent, 'variant': parent == null ? null : 'SMALL',
  'access': {
    'type': type,
    // These are transient credentials, MUST NEVER enter public read models.
    'url': type == 'protected' ? null :
        'https://private.r2.cloudflarestorage.com?X-Amz-Signature=SECRET_TOKEN',
    'expiresAt': '2026-11-08T20:00:00Z',
    'playbackEndpoint': type == 'protected' ? '/media/$id/playback' : null,
  },
  // Backend assetView lists variants only on the root, not each child.
  if (parent == null) 'variants': variants,
};

class _Gateway implements BackendApiGateway {
  final calls = <String>[];
  final responses = <String, Object?>{};
  Completer<Response<dynamic>>? delayed;
  @override
  Future<Response<dynamic>> execute(String id, {
    Map<String, dynamic>? path,
    Map<String, dynamic>? query,
    Object? body,
    CancelToken? cancelToken,
    String? ifMatch,
  }) async {
    calls.add(id);
    if (delayed != null) return delayed!.future;
    return Response<dynamic>(
      data: responses[id], requestOptions: RequestOptions(path: '/test'));
  }
  @override void dispose() {}
}

class _Context {
  final _Gateway gateway = _Gateway();
  int revision = 1;
  bool authenticated = true;
  late final FableMediaReadSource source = FableMediaReadSource(
    gateway: gateway, catalog: _catalog(),
    identityRevision: () => revision,
    isSessionCurrent: () => authenticated,
  );
}

void main() {
  test('RC126 verifies exact protected Backend GET routes; no guessed IDs', () {
    expect(() => const FableMediaReadBindings.verified().verify(_catalog()),
      returnsNormally);
    // OpenAPI exports {id}; some validated contracts retain :id.
    expect(() => const FableMediaReadBindings.verified().verify(
      _catalog(metadataPath: '/media/{id}')), returnsNormally);
    for (final bad in <FableContract>[
      _catalog(runtimeId: 'media.clientContract'),
      _catalog(metadataId: 'media.metadata'),
      _catalog(metadataPath: '/media/unsafe/:id'),
      _catalog(runtimeMethod: 'POST'),
      _catalog(metadataMethod: 'POST'),
      _catalog(metadataAuth: false),
      _catalog(metadataEnforced: false),
    ]) {
      expect(
        () => const FableMediaReadBindings.verified().verify(bad),
        throwsA(anyOf(isA<StateError>(), isA<Exception>())),
      );
    }
  });

  test('RC126 source uses verified runtime DTO and immutable MIME list', () async {
    final context = _Context();
    context.gateway.responses['media.client-contract'] = _runtime;
    final value = await context.source.runtimeContract();
    expect(value.schemaVersion, 12);
    expect(value.driver, MediaStorageDriver.r2);
    expect(value.maxUploadBytes, 60000000);
    expect(value.maxParallelParts, 4);
    expect(value.resumableLargeUpload, isTrue);
    expect(value.directPresignedMultipart, isTrue);
    expect(value.serverAuthoritativeProgress, isTrue);
    expect(value.acceptedMimeTypes, ['image/jpeg', 'video/mp4']);
    expect(() => value.acceptedMimeTypes.add('application/x-secret'),
      throwsUnsupportedError);
    expect(context.gateway.calls, ['media.client-contract']);
  });

  test('RC126 typed media metadata never exposes signed URL or storage keys',
      () async {
    final context = _Context();
    final raw = _asset(_id, variants: [_asset(_child, parent: _id)]);
    raw['storageKey'] = 'PRIVATE_STORAGE_KEY';
    context.gateway.responses['media.get'] = {
      'success': true, 'code': 'MEDIA_FOUND', 'data': raw,
    };
    final value = await context.source.metadata(_id);
    expect(value.id, _id);
    expect(value.kind, MediaAssetKind.video);
    expect(value.visibility, MediaAssetVisibility.private);
    expect(value.accessMode, MediaAssetAccessMode.signed);
    expect(value.mimeType, 'video/mp4');
    expect(value.sizeBytes, 4040);
    expect(value.variants.single.parentAssetId, _id);
    expect(value.variants.single.id, _child);
    expect(() => value.variants.clear(), throwsUnsupportedError);
    expect(value.toString(), isNot(contains('SECRET_TOKEN')));
    expect(value.toString(), isNot(contains('PRIVATE_STORAGE_KEY')));
    expect(context.gateway.calls, ['media.get']);
  });

  test('RC126 refuses malformed schema, unknown enum and inconsistent assets', () {
    expect(
      () => decodeFableRuntimeCapabilities({..._runtime, 'schemaVersion': 13}),
      throwsFormatException);
    expect(
      () => decodeFableRuntimeCapabilities({..._runtime,
        'limits': {'maxUploadBytes': 10, 'maxParallelParts': '4'}}),
      throwsFormatException);
    expect(
      () => decodeFableRuntimeCapabilities({..._runtime,
        'features': {'serverAuthoritativeProgress': 'yes'}}),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset(_asset(_child), requestedId: _id),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset({..._asset(_id), 'sizeBytes': -1},
        requestedId: _id),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset({..._asset(_id),
        'access': {'type': 'protected', 'url': 'https://leak.test/secret'}},
        requestedId: _id),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset({..._asset(_id), 'variants': [
        _asset(_child, parent: '222e4567-e89b-42d3-a456-426614174000'),
      ]}, requestedId: _id),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset({..._asset(_id)}..remove('variants'),
        requestedId: _id),
      throwsFormatException);
    expect(
      () => decodeFableMediaAsset('secret', requestedId: _id),
      throwsFormatException);
  });

  test('RC126 rejects identity switch while GET response is outstanding', () async {
    final context = _Context();
    context.gateway.delayed = Completer<Response<dynamic>>();
    final pending = context.source.metadata(_id);
    await Future<void>.delayed(Duration.zero);
    expect(context.gateway.calls, ['media.get']);
    context.revision++;
    context.gateway.delayed!.complete(Response<dynamic>(
      data: {'success': true, 'data': _asset(_id)},
      requestOptions: RequestOptions(path: '/media/:id')));
    await expectLater(pending, throwsStateError);
  });

  test('RC126 fails closed on inactive session or missing identity gate', () async {
    final context = _Context()..authenticated = false;
    await expectLater(context.source.metadata(_id), throwsStateError);
    expect(context.gateway.calls, isEmpty);
    expect(() => FableMediaReadSource(
      gateway: _Gateway(), catalog: _catalog()),
      throwsArgumentError);
  });

  test('RC126 legacy reader remains source-compatible but never guesses IDs',
      () async {
    final gateway = _Gateway();
    final legacy = FableMediaReadRepository(gateway);
    expect(() => legacy.metadata(_id), throwsStateError);
    expect(() => legacy.runtimeContract(), throwsStateError);
    expect(gateway.calls, isEmpty);
    final trusted = FableMediaReadRepository(gateway,
      catalog: _catalog(), identityRevision: () => 1,
      isSessionCurrent: () => true);
    gateway.responses['media.client-contract'] = _runtime;
    expect((await trusted.runtimeContract()).schemaVersion, 12);
  });

  test('RC126 Application supports Other Backend independent port only',
      () async {
    final read = ReadMediaMetadataUseCase(_OtherBackendPort());
    expect((await read.metadata(_id)).id, _id);
    expect(() => read.metadata('traversal/../../'), throwsArgumentError);
  });
}

final class _OtherBackendPort implements MediaMetadataReadPort {
  @override Future<MediaAssetMetadata> metadata(String assetId) async =>
      MediaAssetMetadata(
        id: assetId, kind: MediaAssetKind.image,
        visibility: MediaAssetVisibility.public,
        originalName: 'photo.jpg', mimeType: 'image/jpeg',
        sizeBytes: 123, accessMode: MediaAssetAccessMode.public,
        variants: const []);
  @override Future<MediaRuntimeCapabilities> runtimeContract() async =>
      MediaRuntimeCapabilities(
        schemaVersion: 1, driver: MediaStorageDriver.local,
        maxUploadBytes: 123, maxParallelParts: 1,
        acceptedMimeTypes: ['image/jpeg'], resumableLargeUpload: false,
        directPresignedMultipart: false, serverAuthoritativeProgress: true);
}
