#!/usr/bin/env python3
"""RC120 fail-closed source/built-plist gate for Xcode 27 UIScene adoption."""
from __future__ import annotations
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ios/Runner/Info.plist"
APP_DELEGATE = ROOT / "ios/Runner/AppDelegate.swift"

def check(path: pathlib.Path) -> None:
    with path.open("rb") as handle:
        info = plistlib.load(handle)
    assert "UIApplicationSceneManifest" in info, "UIScene manifest absent"
    m = info["UIApplicationSceneManifest"]
    assert isinstance(m, dict)
    assert m.get("UIApplicationSupportsMultipleScenes") is False, "Unverified multi-scene mode"
    scenes = m.get("UISceneConfigurations", {}).get("UIWindowSceneSessionRoleApplication")
    assert isinstance(scenes, list) and len(scenes) == 1, "Exactly one application scene required"
    scene = scenes[0]
    assert scene.get("UISceneClassName") == "UIWindowScene"
    assert scene.get("UISceneDelegateClassName") == "FlutterSceneDelegate", "Missing Flutter UIScene plugin lifecycle"
    assert scene.get("UISceneConfigurationName") == "flutter"
    assert scene.get("UISceneStoryboardFile") == "Main"
    assert info.get("UIMainStoryboardFile") == "Main"
    print(f"RC120 UIScene manifest PASS: {path}")

def check_app_delegate() -> None:
    source = APP_DELEGATE.read_text()
    assert "FlutterAppDelegate, FlutterImplicitEngineDelegate" in source
    assert "func didInitializeImplicitFlutterEngine(" in source
    implicit = source.split("func didInitializeImplicitFlutterEngine(", 1)[1]
    assert "GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)" in implicit
    before = source.split("func didInitializeImplicitFlutterEngine(", 1)[0]
    assert "GeneratedPluginRegistrant.register(with: self)" not in before
    assert "window?.rootViewController" not in source
    assert "WorkmanagerPlugin.registerLaunchHandlers()" in before
    assert "WorkmanagerPlugin.setPluginRegistrantCallback" in before
    print("RC120 Flutter implicit-engine and Workmanager lifecycle PASS")

if __name__ == "__main__":
    check(SOURCE)
    check_app_delegate()
    for compiled in sys.argv[1:]:
        check(pathlib.Path(compiled))
