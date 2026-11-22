#!/usr/bin/env python3
"""build.py - pack the autousb module.

Produces one artefact in the sibling `out/` directory (outside the source tree):
  autousb-<ver>.zip         ~60 KB, pure shell + webui

Run from anywhere:  python3 build.py
Override output dir: OUT=/some/dir python3 build.py
"""
import os
import stat
import sys
import zipfile

SRC = os.path.dirname(os.path.abspath(__file__))
# 产物默认放在源码目录之外（同级 out/），别混进模块里被下一次打包带进去
OUT = os.environ.get("OUT") or os.path.join(os.path.dirname(SRC), "out")

# payload/ 不再参与打包（模块是纯 shell + 前端）
SKIP_DIRS = {".git", "__pycache__", "out", "payload"}
SKIP_FILES = {"build.py", "build.sh", ".gitignore", ".gitattributes", ".DS_Store",
              "RELEASE.md", "RELEASE_zh.md"}
EXEC_SUFFIX = (".sh",)
# update-binary 必须带可执行位，否则 recovery 里直接跑会报 Permission denied
EXEC_NAMES = {"autousbctl", "update-binary"}


def read_version():
    with open(os.path.join(SRC, "module.prop"), encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("version="):
                return line.split("=", 1)[1].strip()
    return "v0"


def is_exec(rel, name):
    return name.endswith(EXEC_SUFFIX) or name in EXEC_NAMES


def pack(zip_path):
    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                if name in SKIP_FILES:
                    continue
                full = os.path.join(root, name)
                rel = os.path.relpath(full, SRC).replace(os.sep, "/")
                mode = 0o755 if is_exec(rel, name) else 0o644
                info = zipfile.ZipInfo(rel, (2026, 1, 1, 0, 0, 0))
                # create_system=3(Unix) 才会让解压工具去读 external_attr 里的权限位
                info.create_system = 3
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
    n = pack(p)
    print(f"{os.path.basename(p):32s} {n:3d} files  {os.path.getsize(p)/1024:9.1f} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
