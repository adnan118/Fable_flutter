import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const ios = readFileSync('ios/Runner/FableProtectedMediaBridge.swift', 'utf8');
const android = readFileSync('android/app/src/main/kotlin/com/example/helloworld/FableProtectedMediaBridge.kt', 'utf8');
const dart = readFileSync('packages/features/fable_media/lib/src/presentation/fable_native_protected_player.dart', 'utf8');
const mainActivity = readFileSync('android/app/src/main/kotlin/com/example/helloworld/MainActivity.kt', 'utf8');
const appDelegate = readFileSync('ios/Runner/AppDelegate.swift', 'utf8');

test('RC120 Android has real Media3 progressive DataSource and bounded Dart bytes', () => {
  for(const required of ['ExoPlayer.Builder','ProgressiveMediaSource.Factory',
      'DataSource.Factory','FableProtectedRangeDataSource','override fun read(',
      'CountDownLatch','length > 524288','channel.invokeMethod("readRange"',
      'player?.clearMediaItems()','player?.release()']) {
    assert.ok(android.includes(required), required);
  }
  assert.ok(mainActivity.includes('configureFlutterEngine'));
  assert.ok(mainActivity.includes('onPause'));
});

test('RC120 iOS has UIScene-safe Flutter implicit registration and actual AVFoundation loader', () => {
  for(const required of ['AVPlayer(','AVURLAsset(','AVAssetResourceLoaderDelegate',
     'FableProtectedAssetLoader','info.contentLength = total',
     'info.isByteRangeAccessSupported = true','finishLoading(with:',
     'didCancel loadingRequest','UIScene.didEnterBackgroundNotification']) {
    assert.ok(ios.includes(required), required);
  }
  assert.match(appDelegate, /func didInitializeImplicitFlutterEngine/);
  assert.match(appDelegate, /registrar.register\(/);
  assert.ok(!appDelegate.split('func didInitializeImplicitFlutterEngine(')[0]
    .includes('registerViewFactory'));
});

test('RC120 native bridge never publishes credentials, URLs, DRM or general HTTP', () => {
  for(const source of [ios,android,dart]) {
    for(const prohibited of ['X-Fable-Media-Token','Authorization: Bearer',
       'http://', 'https://', 'grantToken', 'accessToken',
       'DefaultHttpDataSource', 'URLSession.shared']) {
      assert.ok(!source.includes(prohibited), prohibited);
    }
  }
  assert.match(dart, /implements ProtectedPlayerPlatformPort/);
  assert.match(dart, /_generation != generation/);
  assert.match(dart, /AppLifecycleState.paused/);
});
