"""核验本地定版文件；云端访问使用同目录 verify-cloud.js。仅依赖 Python 标准库。"""

import hashlib
import json
from pathlib import Path
import struct
import sys


def main():
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    errors = []
    paths = set()
    for item in manifest["artifacts"]:
        rel = item["path"]
        path = (root / rel).resolve()
        if not path.is_relative_to(root) or rel in paths:
            errors.append(f"非法或重复路径：{rel}")
            continue
        paths.add(rel)
        if not path.is_file():
            errors.append(f"缺少文件：{rel}")
            continue
        data = path.read_bytes()
        if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            errors.append(f"摘要或长度不符：{rel}")
        if "png_size" in item:
            if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 26:
                errors.append(f"PNG 头无效：{rel}")
            elif list(struct.unpack(">II", data[16:24])) != item["png_size"]:
                errors.append(f"PNG 尺寸不符：{rel}")

    previews = {f"previews/marks-{i:03b}-1x.png" for i in range(8)}
    previews.update({"previews/main-native.png", "previews/marks-000-3x-native.png",
                     "previews/marks-111-3x-native.png"})
    if not previews.issubset(paths):
        errors.append("整体图或印记预览不完整。")
    cloud = json.loads((root / "evidence/2026-09-24-cloud-readback.json").read_text(encoding="utf-8"))
    source = json.loads((root / "evidence/2026-09-12-main-readback.json").read_text(encoding="utf-8"))["result"]
    if cloud["main"]["record"] != source["record"]:
        errors.append("本次云端主图记录与定版预览来源记录不一致。")
    if cloud["file"]["id"] != manifest["cloud"]["file_id"]:
        errors.append("云端文件编号不一致。")
    if cloud["file"]["revn"] != manifest["cloud"]["revision"]:
        errors.append("云端修订号不一致。")
    version = manifest["cloud"]["named_version"]
    if not any(v["label"] == version["label"] and v["createdAt"] == version["created_at_utc"]
               and not v["isAutosave"] for v in cloud["versions"]):
        errors.append("回读证据中没有对应的手动命名版本。")
    if errors:
        print(json.dumps({"passed": False, "errors": errors}, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({"passed": True, "artifact_count": len(paths), "preview_count": len(previews),
                      "scope": "本地字节、尺寸及保存的云端回读；不证明其他账号的云端权限。"},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
