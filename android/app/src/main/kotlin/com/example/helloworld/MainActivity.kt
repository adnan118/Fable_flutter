package com.example.helloworld

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nativeMedia: FableProtectedMediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeMedia = FableProtectedMediaBridge(
            flutterEngine.dartExecutor.binaryMessenger
        ).also { it.register(flutterEngine.platformViewsController.registry, this) }
    }

    override fun onPause() {
        // Fail closed when UI is no longer foreground; do not silently resume
        // an older credential-bound decoder after identity/session rotation.
        nativeMedia?.stopAll()
        super.onPause()
    }

    override fun onDestroy() {
        nativeMedia?.disposeAll()
        nativeMedia = null
        super.onDestroy()
    }
}
