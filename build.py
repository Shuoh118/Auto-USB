#!/usr/bin/env python3
"""build.py - pack the autousb module.

Produces one artefact:
  autousb-<ver>.zip         ~42 KB, pure shell + webui

If a payload/autousbmtp.apk is present next to this script, a second
artefact is produced with it bundled:
  autousb-<ver>-full.zip    payload included

The payload is deliberately not tracked in the source tree - drop your
own APK into payload/ to build the -full flavour.

Run from anywhere:  python3 build.py
"""
import os
import stat
import sys
import zipfile

SRC = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT", "/workspace/out")

SKIP_DIRS = {".git", "__pycache__", "out"}
SKIP_FILES = {"build.py", "build.sh", ".gitignore", ".DS_Store", "README_EN.md", "module.yaml"}
EXEC_SUFFIX = (".sh",)
EXEC_NAMES = {"autousbctl"}


def read_version():
    with open(os.path.join(SRC, "module.prop"), encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("version="):
                return line.split("=", 1)[1].strip()
    return "v0"


def is_exec(rel, name):
    return name.endswith(EXEC_SUFFIX) or name in EXEC_NAMES


def pack(zip_path, include_payload):
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                if name in SKIP_FILES:
                    continue
                full = os.path.join(root, name)
                rel = os.path.relpath(full, SRC).replace(os.sep, "/")
                if rel.startswith("payload/") and not include_payload:
                    continue
                mode = 0o755 if is_exec(rel, name) else 0o644
                info = zipfile.ZipInfo(rel, (2026, 1, 1, 0, 0, 0))
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(full, "rb") as fh:
                    z.writestr(info, fh.read())
                count += 1
    return count


def main():
    os.makedirs(OUT, exist_ok=True)
    ver = read_version()

    p = os.path.join(OUT, f"autousb-{ver}.zip")
    n = pack(p, False)
    print(f"{os.path.basename(p):32s} {n:3d} files  {os.path.getsize(p)/1024:9.1f} KiB")

    apk = os.path.join(SRC, "payload", "autousbmtp.apk")
    if os.path.isfile(apk):
        pf = os.path.join(OUT, f"autousb-{ver}-full.zip")
        n = pack(pf, True)
        print(f"{os.path.basename(pf):32s} {n:3d} files  {os.path.getsize(pf)/1024:9.1f} KiB")
    else:
        print("payload/autousbmtp.apk 不存在，跳过 -full 构建")
    return 0


if __name__ == "__main__":
    sys.exit(main())
