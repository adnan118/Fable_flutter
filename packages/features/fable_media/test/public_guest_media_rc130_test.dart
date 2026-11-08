import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

const id = '123e4567-e89b-42d3-a456-426614174000';
const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const cookie = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String? header(RequestOptions request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

Dio fakeGuestDio(List<RequestOptions> requests, {bool denied=false,
  bool invalidLease=false}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requests.add(options);
    if (options.path.endsWith('/session') && options.method == 'POST') {
      handler.resolve(Response<Object?>(
        requestOptions: options, statusCode: 201,
        headers: Headers.fromMap({
          'set-cookie': [
            '__Host-fable-media-guest=$cookie; Path=/; Secure; HttpOnly; SameSite=Strict',
          ],
        }),
        data: {
          'assetId': id, 'token': token,
          'expiresAt': DateTime.now().toUtc()
              .add(Duration(seconds: invalidLease ? -1 : 120))
              .toIso8601String(),
          'contentEndpoint': '/media/guest/$id/content',
        },
      ));
      return;
    }
    if (options.path.endsWith('/content') && options.method == 'GET') {
      if (denied) {
        handler.reject(DioException(
          requestOptions: options, type: DioExceptionType.badResponse,
          response: Response<Object?>(requestOptions: options,statusCode:403)));
        return;
      }
      handler.resolve(Response<Object?>(
        requestOptions: options, statusCode: 206,
        headers: Headers.fromMap({
          'content-range':['bytes 0-2/10'],
          'content-length':['3'],
          'content-type':['image/png'],
          'cache-control':['private, no-store, max-age=0'],
        }),
        data: <int>[1,2,3],
      ));
      return;
    }
    if (options.path.endsWith('/session') && options.method == 'DELETE') {
      handler.resolve(Response<Object?>(requestOptions: options,statusCode:200));
      return;
    }
    handler.reject(DioException(requestOptions: options,
      type: DioExceptionType.unknown));
  }));
  return dio;
}

void main() {
  test('RC130 rejects non-HTTPS and query-bearing origins', () {
    final dio = Dio();
    for (final invalid in [
      'http://example.com/',
      'https://example.com/a',
      'https://u:pass@example.com/',
      'https://example.com/?token=bad',
    ]) {
      expect(() => FablePublicGuestByteSource(
        client: dio, origin: Uri.parse(invalid), assetId: id),
        throwsArgumentError);
    }
  });

  test('RC130 public guest reads safe byte ranges with BOTH secrets in headers',
      () async {
    final reqs = <RequestOptions>[];
    final source = FablePublicGuestByteSource(
      client: fakeGuestDio(reqs), origin: Uri.parse('https://portal.example'),
      assetId: id,
    );
    expect(source.isActive,isFalse);
    await source.open();
    expect(source.isActive,isTrue);
    final chunk = await source.readChunk(
      const MediaByteRange(start:0,length:3));
    expect(chunk.start,0);
    expect(chunk.totalLength,10);
    expect(chunk.mimeType,'image/png');
    expect(chunk.bytes,Uint8List.fromList([1,2,3]));
    final get = reqs.where((r)=>r.method=='GET').single;
    expect(get.uri.scheme,'https');
    expect(get.uri.path,'/media/guest/$id/content');
    expect(get.uri.query,isEmpty);
    expect(header(get,'cookie'),'__Host-fable-media-guest=$cookie');
    expect(header(get,'x-fable-guest-media-token'),token);
    expect(header(get,'range'),'bytes=0-2');
    expect(get.followRedirects,isFalse);
    expect(get.uri.toString(),isNot(contains(token)));
    expect(get.uri.toString(),isNot(contains(cookie)));
    await source.close();
    expect(source.isActive,isFalse);
    final delete=reqs.where((r)=>r.method=='DELETE').single;
    expect(header(delete,'x-fable-guest-media-token'),token);
    await expectLater(source.read(const MediaByteRange(start:0,length:3)),
      throwsA(isA<MediaReadFailure>()));
  });

  test('RC130 fails closed on expired guest lease', () async {
    final reqs = <RequestOptions>[];
    final source = FablePublicGuestByteSource(
      client: fakeGuestDio(reqs,invalidLease:true),
      origin:Uri.parse('https://portal.example'),assetId:id);
    await expectLater(source.open(),throwsFormatException);
    expect(source.isActive,isFalse);
    expect(reqs.where((x)=>x.method=='GET'),isEmpty);
    await source.close();
  });

  test('RC130 revokes client read capability on 403 from Backend', () async {
    final reqs = <RequestOptions>[];
    final source = FablePublicGuestByteSource(
      client: fakeGuestDio(reqs,denied:true),
      origin:Uri.parse('https://portal.example'),assetId:id);
    await source.open();
    await expectLater(source.read(const MediaByteRange(start:0,length:3)),
      throwsA(isA<MediaReadFailure>()));
    expect(source.isActive,isFalse);
    await source.close();
  });
}
