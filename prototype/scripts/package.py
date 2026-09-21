#!/usr/bin/env python3
"""Build a portable Apple Silicon app and a drag-to-Applications DMG."""
import hashlib
import shutil
import subprocess

from build import ROOT, VERSION, build


def main():
    app = build(release=True)
    staging = ROOT / "build/dmg-root"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    subprocess.run(["/usr/bin/ditto", str(app), str(staging / app.name)], check=True)
    (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
    shutil.copyfile(ROOT / "packaging/Install.txt", staging / "Install.txt")
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    dmg = destination / ("North-Star-" + VERSION + "-arm64.dmg")
    subprocess.run(["/usr/bin/hdiutil", "create", "-volname", "North Star", "-srcfolder", str(staging),
                    "-ov", "-format", "UDZO", "-fs", "HFS+", str(dmg)], check=True)
    subprocess.run(["/usr/bin/hdiutil", "verify", str(dmg)], check=True)
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    dmg.with_suffix(".dmg.sha256").write_text(digest + "  " + dmg.name + "\n")
    print(dmg)
    print("SHA-256: " + digest)


if __name__ == "__main__":
    main()
