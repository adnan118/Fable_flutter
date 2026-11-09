#!/usr/bin/env python3
"""Fail-closed Xcode 27 UIScene smoke test on both iPhone + iPad simulators.

Boot, install, launch, verify process survives, and clean up. Each simctl
operation is bounded; a nonresponsive CoreSimulator is a FAILED gate, not a
reason to claim successful launch based only on a compiled Info.plist.
"""
from __future__ import annotations

import json
import pathlib
import plistlib
import subprocess
import sys
import time


def run(*arguments: str, timeout: int = 45) -> str:
    print("+", " ".join(arguments), f"[timeout {timeout}s]", flush=True)
    try:
        result = subprocess.run(
            list(arguments), check=True, text=True, capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"Timed out: {arguments[0]} {arguments[1:]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stdout or "") + "\n" + (exc.stderr or "")
        print(detail[-4000:], flush=True)
        raise
    output = (result.stdout or "").strip()
    if output:
        print(output[-4000:], flush=True)
    return output


def simctl(*arguments: str, timeout: int = 45) -> str:
    return run("xcrun", "simctl", *arguments, timeout=timeout)


def available_pair(runtime: str) -> list[tuple[str, str, bool]]:
    devices = json.loads(simctl("list", "-j", "devices", "available", timeout=60))
    entries = devices.get("devices", {}).get(runtime, [])
    selected = {}
    # Preinstalled light profiles avoid cold-booting a heavy iPad Pro or
    # iPhone 18 Pro when a compatible iOS 27 iPad mini/iPhone 17e exists.
    def existing_rank(item: dict) -> int:
        name = item.get("name", "")
        preferred = (
            100 if name.startswith("iPhone 17e") else
            95 if name.startswith("iPad mini") else
            80 if name.startswith("iPhone 17") else
            75 if name.startswith("iPad (") else
            60 if name.startswith("iPhone") else
            50 if name.startswith("iPad") else 0
        )
        return preferred + (5 if item.get("state") == "Booted" else 0)

    for item in sorted(entries, key=existing_rank, reverse=True):
        if not item.get("isAvailable", False):
            continue
        name = item.get("name", "")
        kind = "iPhone" if name.startswith("iPhone") else (
            "iPad" if name.startswith("iPad") else None
        )
        if kind and kind not in selected:
            selected[kind] = (kind, item["udid"], item.get("state") == "Booted")

    if len(selected) != 2:
        device_types = json.loads(simctl("list", "-j", "devicetypes", timeout=60))
        types = device_types.get("devicetypes", [])
        for kind in ("iPhone", "iPad"):
            if kind in selected:
                continue
            candidates = [
                x for x in types if x.get("name", "").startswith(kind)
            ]
            if not candidates:
                raise RuntimeError(f"Xcode 27 iOS Simulator missing {kind} device type")
            # Prefer a current hardware profile; old simulator types (e.g.
            # iPhone 4s) may be incompatible with the iOS 27 runtime.
            def rank(item: dict) -> int:
                name = item.get("name", "")
                if kind == "iPhone":
                    return 100 if "iPhone 18" in name else (
                        90 if "iPhone 17" in name else (
                        80 if "iPhone 16" in name else 0))
                return 100 if "iPad Pro" in name else (
                    90 if "iPad Air" in name else 0)
            candidates.sort(key=rank, reverse=True)
            for candidate in candidates:
                try:
                    udid = simctl(
                        "create", f"Fable-RC120-{kind}",
                        candidate["identifier"], runtime, timeout=120,
                    ).strip()
                except subprocess.CalledProcessError:
                    # Incompatible simulated hardware type; try next. A
                    # timeout, however, remains fatal rather than skipped.
                    continue
                selected[kind] = (kind, udid, False)
                break
            if kind not in selected:
                raise RuntimeError(f"No {kind} device type supports iOS 27")
    if set(selected) != {"iPhone", "iPad"}:
        raise RuntimeError("Both iPhone and iPad must be verified")
    return [selected["iPhone"], selected["iPad"]]


def main(app: pathlib.Path) -> None:
    if not app.is_dir():
        raise RuntimeError(f"Compiled iOS app not found: {app}")
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    bundle = info.get("CFBundleIdentifier")
    assert isinstance(bundle, str) and bundle, "Missing bundle identifier"
    manifest = info.get("UIApplicationSceneManifest")
    assert isinstance(manifest, dict), "Built app has no UIScene manifest"
    scene = manifest["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"][0]
    assert scene["UISceneDelegateClassName"] == "FlutterSceneDelegate"

    version = run("xcodebuild", "-version").splitlines()[0]
    if not version.startswith("Xcode 27"):
        raise RuntimeError(f"Expected Xcode 27, found {version}")
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version").strip()
    if not sdk.startswith("27."):
        raise RuntimeError(f"Expected iOS Simulator SDK 27, found {sdk}")

    # Xcode 27 runner images may lazily mount simulator cryptex runtimes.
    # Enumerate runtime registration before booting devices; never ignore
    # failures or incorrectly treat a compiled plist as launch success.
    simctl("runtime", "list", timeout=120)
    runtimes = json.loads(simctl("list", "-j", "runtimes", timeout=60))
    compatible = [
        x for x in runtimes.get("runtimes", [])
        if x.get("isAvailable", False)
        and x.get("version", "").startswith("27.")
        and "iOS" in x.get("name", "")
    ]
    if not compatible:
        raise RuntimeError("Missing bootable iOS 27 simulator runtime")
    runtime = compatible[0]["identifier"]
    print(f"RC120 runtime={runtime} bundle={bundle}", flush=True)

    for kind, udid, is_booted in available_pair(runtime):
        print(f"::group::RC120 {kind} iOS 27 UIScene launch", flush=True)
        try:
            if not is_booted:
                simctl("boot", udid, timeout=120)
            simctl("bootstatus", udid, "-b", timeout=480)
            # GitHub's virtualized Xcode 27 CoreSimulator can take several
            # minutes for first install; the previous 120s limit was too low.
            # This remains fail-closed and bounded to 10 minutes per device.
            simctl("install", udid, str(app.resolve()), timeout=600)
            launch_result = simctl("launch", udid, bundle, timeout=180)
            if not launch_result or ":" not in launch_result:
                raise RuntimeError(f"{kind} simctl did not return a process id")
            time.sleep(7)
            # GitHub Xcode 27 may stall during the first simctl terminate while
            # the simulator is under first-boot pressure. Never count a timeout
            # as success: require a confirmed zero-exit terminate, with one
            # bounded retry, or fail the native acceptance gate.
            for attempt in range(2):
                try:
                    simctl("terminate", udid, bundle, timeout=90)
                    break
                except RuntimeError as error:
                    if attempt != 0 or "Timed out: xcrun" not in str(error):
                        raise
                    print("RC153 iOS: simulator terminate stalled; retrying once", flush=True)
                    time.sleep(5)
            print(f"PASS: {kind} iOS 27 UIScene process stayed alive", flush=True)
        finally:
            try:
                simctl("shutdown", udid, timeout=90)
            except (RuntimeError, subprocess.CalledProcessError):
                print(f"WARNING: could not cleanly shut down {kind}", flush=True)
            print("::endgroup::", flush=True)

    print("RC120 iPhone + iPad iOS/iPadOS 27 UIScene smoke PASS", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: rc120_uiscene_simulator_smoke.py Runner.app")
    main(pathlib.Path(sys.argv[1]))
