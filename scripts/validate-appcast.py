#!/usr/bin/env python3
"""Fail a release build if its Sparkle feed does not match the archive."""

import argparse
import base64
import os
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def validate(feed: Path, archive: Path, version: str, repository: str, tag: str) -> str:
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("更新清单必须包含一个版本")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("缺少下载地址")
    expected_url = f"https://github.com/{repository}/releases/download/{tag}/{archive.name}"
    if enclosure.get("url") != expected_url:
        raise ValueError("更新清单的下载地址与发布仓库不一致")
    if item.findtext(f"{SPARKLE}version") != version:
        raise ValueError("更新清单版本与 tag 不一致")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("更新清单记录的安装包大小不一致")
    signature = enclosure.get(f"{SPARKLE}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("更新包缺少有效签名；请检查公钥和私钥是否配对")
    return signature


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    version = os.environ["CLIPBAR_VERSION"]
    try:
        print(
            validate(
                args.feed, args.archive, version,
                os.environ["CLIPBAR_UPDATE_REPOSITORY"],
                os.environ.get("RELEASE_TAG", f"v{version}"),
            )
        )
    except (ValueError, ET.ParseError) as error:
        parser.exit(1, f"更新清单验证失败：{error}\n")


if __name__ == "__main__":
    main()
