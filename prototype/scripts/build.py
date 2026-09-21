#!/usr/bin/env python3
"""Build a development app, or a portable app with --release."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

VERSION = "0.0.1"
PYTHON_URL = ("https://github.com/astral-sh/python-build-standalone/releases/download/20260901/"
              "cpython-3.12.14%2B20260901-aarch64-apple-darwin-install_only_stripped.tar.gz")
PYTHON_SHA256 = "81a359f1cfadd4da11766534c5913791cea55f26e1bb902cacd2a531bb1e4b2b"
ROOT = Path(__file__).resolve().parents[1]


def build_icon():
    assets = ROOT / "assets"
    assets.mkdir(exist_ok=True)
    icon = assets / "AppIcon.icns"
    source = ROOT / "scripts/draw_icon.swift"
    if icon.exists() and icon.stat().st_mtime_ns >= source.stat().st_mtime_ns:
        return icon
    cache = ROOT / "build/module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    renderer = ROOT / "build/draw-icon"
    subprocess.run(["swiftc", "-module-cache-path", str(cache), "-framework", "AppKit",
                    str(source), "-o", str(renderer)], check=True)
    subprocess.run([str(renderer), str(assets)], check=True)
    subprocess.run(["/usr/bin/iconutil", "--convert", "icns", str(assets / "AppIcon.iconset"),
                    "--output", str(icon)], check=True)
    return icon


def bundle_python(resources):
    archive = ROOT / "build/downloads/cpython-3.12.14-20260901-arm64.tar.gz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        pending = archive.with_suffix(".download")
        subprocess.run(["/usr/bin/curl", "-fL", "--retry", "2", "--max-time", "180",
                        PYTHON_URL, "-o", str(pending)], check=True)
        if hashlib.sha256(pending.read_bytes()).hexdigest() != PYTHON_SHA256:
            raise RuntimeError("Downloaded Python archive failed its SHA-256 check")
        pending.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != PYTHON_SHA256:
        raise RuntimeError("Cached Python archive failed its SHA-256 check")
    subprocess.run(["/usr/bin/tar", "-xzf", str(archive), "-C", str(resources)], check=True)
    # Disable bytecode writes before Python startup, including imports by site.py.
    launcher = resources / "python/bin/north-star-python"
    launcher.write_text('#!/bin/sh\nexec "$(/usr/bin/dirname "$0")/python3" -B "$@"\n')
    launcher.chmod(0o755)
    (resources / "Runtime source.txt").write_text(
        "CPython 3.12.14, python-build-standalone release 20260901\n"
        + PYTHON_URL + "\nSHA-256: " + PYTHON_SHA256 + "\n"
        "Python's license is in python/lib/python3.12/LICENSE.txt.\n"
        "Additional runtime license notices are in Third-party licenses/.\n")
    shutil.copytree(ROOT / "packaging/licenses", resources / "Third-party licenses")
    # Sign native runtime components before sealing the enclosing app.
    mach_o = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe",
              b"\xbe\xba\xfe\xca", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce"}
    for path in sorted((resources / "python").rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as handle:
            is_native = handle.read(4) in mach_o
        if is_native:
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(path)],
                           check=True, capture_output=True)


def build(release=False):
    sources = sorted((ROOT / "native").glob("*.swift"))
    fingerprints = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    destination = ROOT / ("build/release/North Star.app" if release else "build/North Star.app")
    app = ROOT / ("build/.release-staging/North Star.app" if release else "build/.development-staging/North Star.app")
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    icon = build_icon()
    shutil.copyfile(icon, resources / icon.name)
    shutil.copytree(ROOT / "backend", resources / "backend",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
    info = {
        "CFBundleName": "North Star", "CFBundleDisplayName": "North Star",
        "CFBundleIdentifier": "local.northstar.prototype", "CFBundleVersion": "4",
        "CFBundleIconFile": "AppIcon.icns",
        "CFBundleShortVersionString": VERSION, "CFBundleExecutable": "NorthStar",
        "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": "Capture your spoken thoughts for your projects.",
        "NSSpeechRecognitionUsageDescription": "Transcribe your thoughts on this Mac. No audio is uploaded by North Star.",
    }
    if release:
        bundle_python(resources)
    else:
        info.update(NorthStarProjectDirectory=str(ROOT), NorthStarPython="/usr/bin/python3")
    with (app / "Contents/Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)
    cache = ROOT / "build/module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    subprocess.run(["swiftc", "-swift-version", "5", "-O", "-module-cache-path", str(cache),
        "-target", "arm64-apple-macosx14.0", "-framework", "SwiftUI", "-framework", "AppKit",
        "-framework", "Speech", "-framework", "AVFoundation", "-framework", "Carbon",
        *map(str, sources),
        "-o", str(macos / "NorthStar")], check=True)
    if fingerprints != {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in sorted((ROOT / "native").glob("*.swift"))}:
        raise RuntimeError("Native sources changed during compilation; rerun the build")
    if release:
        (resources / "Build manifest.json").write_text(json.dumps({
            "version": VERSION, "architecture": "arm64", "minimum_macos": "14.0",
            "native_sources_sha256": fingerprints, "python_archive_sha256": PYTHON_SHA256,
            "app_icon_sha256": hashlib.sha256(icon.read_bytes()).hexdigest(),
        }, indent=2) + "\n")
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    # A failed build must not remove the last usable app.
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        shutil.rmtree(destination)
    app.rename(destination)
    print(destination)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="Bundle Python and use Application Support for data")
    build(parser.parse_args().release)
