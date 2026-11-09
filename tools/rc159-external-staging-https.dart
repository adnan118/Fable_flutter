// RC159 — external Dart HTTPS read-only acceptance for the dedicated, disposable
// Render staging instance. This client runs OUTSIDE the Render container.
// Does not create accounts, send credentials, use mocks or alter server state.
import 'dart:async';
import 'dart:io';

const stagingOrigin =
    'https://fable-rc151-free-ephemeral-api.onrender.com';

Future<int> secureGet(HttpClient client, String path) async {
  final origin = Uri.parse(stagingOrigin);
  if (origin.scheme != 'https' ||
      origin.host != 'fable-rc151-free-ephemeral-api.onrender.com' ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      !path.startsWith('/') ||
      path.startsWith('//')) {
    throw StateError('RC159 unsafe staging destination');
  }
  final target = origin.resolve(path);
  if (target.origin != origin.origin) {
    throw StateError('RC159 unexpected cross-origin path');
  }
  final request =
      await client.getUrl(target).timeout(const Duration(seconds: 20));
  // Follow no redirects. Never forward authorization/cookies/installation IDs.
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'Fable-RC159-External-Dart-HTTPS-ReadOnly',
  );
  final response =
      await request.close().timeout(const Duration(seconds: 25));
  final status = response.statusCode;
  await response.drain<void>().timeout(const Duration(seconds: 15));
  return status;
}

Future<void> assertExternalStatus(
  HttpClient client,
  String path,
  int expected, {
  int attempts = 6,
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    int? status;
    try {
      status = await secureGet(client, path);
    } on HandshakeException {
      rethrow; // Never tolerate a bad certificate.
    } on SocketException {
      if (attempt == attempts) rethrow;
    } on TimeoutException {
      if (attempt == attempts) rethrow;
    }

    if (status == expected) {
      stdout.writeln(
        'RC159_EXTERNAL_HTTPS_OK: $path HTTP $status (attempt $attempt)',
      );
      return;
    }
    // Only transient cold-start failures or connection timeouts may retry;
    // never reinterpret a 401, 403, 302 or unexpected 200 as a success.
    if (attempt == attempts ||
        (status != null &&
            status != 429 &&
            status != 502 &&
            status != 503 &&
            status != 504)) {
      throw StateError(
        'RC159 status mismatch: $path expected $expected got $status',
      );
    }
    stdout.writeln(
      'RC159_FREE_COLD_START_RETRY: $path attempt $attempt, status $status',
    );
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}

Future<void> main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 3)
    ..maxConnectionsPerHost = 2;

  try {
    // Free Render may sleep between test runs. No authenticated requests.
    await assertExternalStatus(client, '/health', 200, attempts: 18);
    await assertExternalStatus(client, '/health/ready', 200, attempts: 8);
    await assertExternalStatus(client, '/auth/me/account', 401);
    await assertExternalStatus(client, '/permissions/me', 401);
    await assertExternalStatus(client, '/media/client-contract', 401);
    stdout.writeln(
      'RC159_EXTERNAL_DART_HTTPS_PASS: 5 real external HTTP statuses; '
      'system TLS validation, no redirect, no credentials or mutation.',
    );
  } finally {
    client.close(force: true);
  }
}
