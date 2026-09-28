# 运行画面采集合同

视觉采集保留 `project.godot` 的拉伸设置，仅改变窗口尺寸。不得用关闭拉伸的截图替代玩家实际运行画面。输入事件和控件边界检查使用视口逻辑坐标；窗口像素尺寸单独记录。

## 采集记录

`capture_metadata.gd` 在保存 PNG 时记录实际参数。共享入口 `save_png` 写入同目录的 `capture-metadata.json`；已有主清单可使用 `capture_record` 与 `write_manifest` 保留原有来源字段。

每张图片记录文件名、SHA256、图片尺寸、窗口尺寸、视口可见区域、项目拉伸模式、实际拉伸模式与基准尺寸，以及实际渲染器。清单顶层同样记录渲染器和项目拉伸模式。

- `viewport`：引擎视口原图。
- `derived_detail`：从同批整屏裁切的诊断细节，另记 `source_file`、`source_sha256`、`source_region` 和正数 `scale`。不能用派生图代替整屏。
- `diagnostic`：固定像素几何或 SubViewport 的专项度量。清单标记 `runtime_evidence: false`，脚本文件头注明“不代表运行配置”，不得送作运行视觉验收。

新采集输出到仓库外的新目录。历史报告及证据清单保留在其原交付提交；后续工具修订不回写历史摘要。

## C8 验收

在仓库根目录运行：

```text
python tests/claude_review/test_capture_config.py
python tests/claude_review/claude_review_checks.py --c8-only --manifests <清单1> <清单2> --json <仓库外结果.json>
```

需要已有 Python 环境中的 Pillow 和 NumPy。C8 同时检查采集脚本、清单配置、实际 PNG 的尺寸及 SHA256。任一项失败返回非零退出码。固定像素诊断清单会被明确拒绝作为运行证据；其专项测试结果单独保留。

D-5 已由用户裁决：Windows 发行与验证统一使用 Compatibility（gl_compatibility）。C8 的渲染器目标取自项目配置。命令行覆盖渲染器而与项目不一致时，清单应失败；不能为消除检查失败而把清单字段改写成目标值。CR-01 使用偏置 0 的 mip 模式；棋子和碎石制作显示尺寸母版，不执行偏置实验。

配置及摘要通过只证明证据的采集身份，还需与原生场景对照布局，并分别记录独立审查和用户视觉验收。
