#!/usr/bin/env python3
"""Run a real protected MP4 Flutter integration_test on an iOS 27 simulator."""
from __future__ import annotations
import json
import pathlib
import subprocess

from rc120_uiscene_simulator_smoke import available_pair, run, simctl

TARGET = "integration_test/rc122_protected_video_test.dart"
TARGET_RC124 = "integration_test/rc124_native_player_lifecycle_test.dart"

def ensure_booted(udid: str) -> None:
    """Flutter integration_test may shut down its simulator after each run.

    Re-check the device state *before each independent decoder test*; never
    silently treat a failed install, boot or launch as successful. Simulator
    provisioning may change the state between consecutive flutter commands.
    """
    devices = json.loads(simctl("list", "-j", "devices", timeout=90))
    matches = [device for entries in devices.get("devices", {}).values()
               for device in entries if device.get("udid") == udid]
    if len(matches) != 1:
        raise RuntimeError("Selected iOS 27 simulator is unavailable")
    state = matches[0].get("state")
    if state == "Shutdown":
        simctl("boot", udid, timeout=150)
    elif state != "Booted":
        raise RuntimeError(f"Simulator not ready to boot: {state}")
    simctl("bootstatus", udid, "-b", timeout=480)


def main() -> None:
    toolchain = run("xcodebuild", "-version", timeout=30)
    if not toolchain.startswith("Xcode 27"):
        raise RuntimeError("RC122 requires Xcode 27")
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version", timeout=30)
    if not sdk.startswith("27."):
        raise RuntimeError("RC122 requires iOS 27 Simulator SDK")
    for target in (TARGET, TARGET_RC124):
        if not pathlib.Path(target).is_file():
            raise RuntimeError(f"Missing protected video integration target: {target}")
    runtimes = json.loads(simctl("list", "-j", "runtimes", timeout=90))
    supported = [x for x in runtimes.get("runtimes", [])
                 if x.get("isAvailable", False)
                 and x.get("version", "").startswith("27.")
                 and "iOS" in x.get("name", "")]
    if not supported:
        raise RuntimeError("Missing iOS 27 simulator runtime")
    kind, udid, is_booted = available_pair(supported[0]["identifier"])[0]
    if kind != "iPhone":
        raise RuntimeError("Missing iPhone simulator")
    print(f"RC122 selected iOS27 {kind} {udid}", flush=True)
    try:
        # First flutter test may terminate the simulator at test shutdown.
        # Reboot and wait for bootstatus before the second installation.
        # Both decoder tests remain required and fail-closed.
        ensure_booted(udid)
        # Actual Flutter integration test waits for native decoder events,
        # not a successful MethodChannel prepare or standalone scene launch.
        run("flutter", "test", TARGET, "-d", udid,
            "--reporter=expanded", timeout=1800)
        ensure_booted(udid)
        # RC124 is NOT a fake-channel test: native playback state changes,
        # native seek completion and a deliberately late source read must pass.
        run("flutter", "test", TARGET_RC124, "-d", udid,
            "--reporter=expanded", timeout=1800)
        print("RC122 decoded MP4 over protected native bridge PASS", flush=True)
    finally:
        try:
            simctl("shutdown", udid, timeout=90)
        except (subprocess.CalledProcessError, RuntimeError):
            print("WARNING: simulator cleanup failed", flush=True)

if __name__ == "__main__":
    main()
