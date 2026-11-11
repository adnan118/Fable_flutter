import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Keep the MethodChannel owner alive for the lifetime of the UIScene engine.
  // FableDpopNativeBridge captures self weakly in its handler.
  private var nativeDpopBridge: FableDpopNativeBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UIScene apps must register pending BGTaskScheduler handlers on launch.
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // UIScene: register native UI/platform channels with the implicit engine,
    // NOT during application didFinishLaunchingWithOptions.
    // Native DPoP hardware key must be registered with the UIScene engine,
    // not with the former launch-time Flutter view controller.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FableNativeDpop") {
      nativeDpopBridge = FableDpopNativeBridge(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FableProtectedMedia") {
      let bridge = FableProtectedMediaBridge(messenger: registrar.messenger())
      registrar.register(
        FableProtectedMediaViewFactory(bridge: bridge),
        withId: "fable/protected_media_surface"
      )
    }
  }
}
