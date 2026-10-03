"""CR-23：检查每种运行画面状态均有三档真实截图。配置和图像身份另由 C8 核验。"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

REQUIRED = {(1280, 720), (1920, 1080), (2560, 1440)}


def check_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    errors = []
    groups: dict[str, set[tuple[int, int]]] = {}
    if data.get("runtime_evidence") is False:
        errors.append("专项诊断不能作为三档运行证据")
    for record in data.get("captures", []):
        if record.get("capture_kind", "viewport") != "viewport":
            continue
        group = record.get("capture_group")
        if not isinstance(group, str) or not group.strip():
            errors.append(f"缺少画面状态标识：{record.get('file')}")
            continue
        window = record.get("window_size")
        image = record.get("image_size")
        if not isinstance(window, list) or len(window) != 2 or any(type(v) is not int for v in window):
            errors.append(f"窗口尺寸无效：{record.get('file')}")
            continue
        if image != window:
            errors.append(f"图片与实际窗口尺寸不符：{record.get('file')}")
        groups.setdefault(group, set()).add(tuple(window))
    if not groups:
        errors.append("没有运行画面状态")
    for group, sizes in sorted(groups.items()):
        missing = REQUIRED - sizes
        if missing:
            errors.append(f"{group} 缺少尺寸：{sorted(missing)}")
    return {"manifest": path.name, "groups": {k: sorted(v) for k, v in sorted(groups.items())},
            "errors": errors, "pass": not errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifests", type=Path, nargs="+", required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()
    checks = []
    for path in args.manifests:
        try:
            checks.append(check_manifest(path))
        except (OSError, ValueError, TypeError, AttributeError) as error:
            checks.append({"manifest": path.name, "pass": False, "errors": [str(error)]})
    report = {"pass": all(c["pass"] for c in checks), "checks": checks}
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
