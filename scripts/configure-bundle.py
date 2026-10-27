#!/usr/bin/env python3
"""Inject and validate version/update metadata before signing the app bundle."""

from __future__ import annotations

import argparse
import base64
import binascii
import os
import plistlib
import re
from pathlib import Path


def configure(plist_path: Path, version: str | None, repository: str, public_key: str) -> None:
    with plist_path.open("rb") as source:
        info = plistlib.load(source)
    version = version or info["CFBundleShortVersionString"]
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("版本号必须为不带前缀的稳定版本，例如 1.2.3")
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = version

    if bool(repository) != bool(public_key):
        raise ValueError("更新源 CLIPBAR_UPDATE_REPOSITORY 和 SPARKLE_PUBLIC_ED_KEY 必须同时配置")
    if repository:
        if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9_.-]+", repository):
            raise ValueError("更新仓库必须为 owner/repo 格式")
        if repository.split("/")[1] in (".", ".."):
            raise ValueError("无效的仓库名称")
        try:
            valid_key = len(base64.b64decode(public_key, validate=True)) == 32
        except (ValueError, binascii.Error):
            valid_key = False
        if not valid_key:
            raise ValueError("SPARKLE_PUBLIC_ED_KEY 必须为 Base64 编码的 32 字节 Ed25519 公钥")
        info["SUFeedURL"] = f"https://github.com/{repository}/releases/latest/download/appcast.xml"
        info["SUPublicEDKey"] = public_key
    else:
        info.pop("SUFeedURL", None)
        info.pop("SUPublicEDKey", None)

    with plist_path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    args = parser.parse_args()
    with args.plist.open("rb") as source:
        defaults = plistlib.load(source)
    try:
        configure(
            args.plist,
            os.environ.get("CLIPBAR_VERSION"),
            os.environ.get("CLIPBAR_UPDATE_REPOSITORY", defaults.get("ClipBarUpdateRepository", "")),
            os.environ.get("SPARKLE_PUBLIC_ED_KEY", defaults.get("SUPublicEDKey", "")),
        )
    except ValueError as error:
        parser.exit(1, f"配置应用失败：{error}\n")


if __name__ == "__main__":
    main()
