---
name: sot-art-review
description: SoT 美术素材审核 lane（Claude 专用）：审核 Codex 产出的 UI、人物、棋子、地形、特效素材与产线，给出保留/调整/删减/推翻重做结论，附材质或式样参考、机械证据和产线修改指导。仅用于 Ship of Theseus 相关仓库。
---

# SoT 美术审核 lane

> 状态：2026-09-27 初版，尚未经过独立审查（按用户规则，代理规则变更需独立审查后再视为定稿）。2026-10-27 随 Mercury #692 从用户级目录迁入本仓库项目区，只改了路径写法。

## 职责与权限

- 审核 Codex 已完成的素材与产线；有权调整、删减或推翻重来。修改素材时必须附材质或式样参考（已批准锚点的裁切 + 精确像素规格色块/线宽/光照说明）；改进产线时给出可执行的修改指导。
- 自己改动或新做的素材不得自评通过：交给独立审查者（mercury-reviewer / mercury-acceptance，或 Codex、用户）。
- 不直接提交或推送 develop/main/master；审核证据放在自己的任务工作树（用 `scripts/codex/sot-worktree.ps1 -Action Create` 在 `.worktrees/<task>/` 创建，分支 `claude/<task>`），经 `scripts/codex/sot-publish.ps1` 发布。
- 第三方参考只给链接；下载或导入第三方图片（含导入 Penpot）前先征得用户同意，绝不进入正式素材目录。

## 开始前必读（按目标 HEAD 读取，不抄副本）

1. Ship `AGENTS.md`；roots 按 `~/.claude/mercury-roots.local.json` 解析，不猜路径。
2. VA-6 规格：`dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md`。
3. KB 现行视觉裁决：`git -C <kb_root> show origin/master:04-Assets/visual-style-decisions.md`（固定 vault 工作区常被其他线路占用且有未提交改动，只读默认分支）。
4. `assets/prototype/visual_style/sample_manifest.json` v3（五个锚点 + clean_v2 的 SHA 绑定）。

## 审核流程

1. **收件核对**：目标 Milestone/Task、分支与完整 SHA、文件清单（路径/SHA256/像素尺寸/显示尺寸/过滤/类型/状态名）、生成提示词与参考图 SHA、处理步骤、Penpot 画板名、冻结项与待裁决项。缺项先向 Codex 索取。
2. **机械审计**：`art_audit.py`（身份、alpha、残留 RGB、白边、假棋盘格、网格、色板、明度、对称、1.5×/2× 缩放均匀性）。结论只是证据，不替代目检。
3. **目检**：`contact_sheet.py` 合成到 black/magenta/scene/白底 + L* 灰度；原生 1:1 裁切；游戏内缩放用 `--sim`。
4. **九宫格**：`nineslice_check.py` 覆盖最小/标准/最大尺寸，检查边条是否适合 stretch、边距奇偶。
5. **实机**：在审核工作树启动 Godot 编辑器，Godot MCP `run` + `screenshot_game`；像素级证据用项目的 capture 脚本（MCP 截图是窗口尺寸，不是原生视口）。
6. **结论**：每项给 保留/调整/删减/推翻重做 + 严重度 + 证据 + 修改要求 + 参考 + 修复后验收标准；另附可直接转交 Codex 的指令块。

## 脚本

统一运行：`uv run --no-project --python 3.13 --with numpy --with pillow python .claude/skills/sot-art-review/scripts/<脚本> ...`（在 Ship 仓根或任务工作树根运行），Bash 下加 `PYTHONUTF8=1`。先跑 `selftest.py`（CIEDE2000 已用 Sharma 2005 数据校验）。

## 已验证的环境要点（2026-09-27）

- Claude 看图会忽略 alpha，透明区残留 RGB 会直接显示；一律先合成到已知底色再判断。
- Penpot：应用 2.18.1，本机 MCP 插件 2.17.2（服务哈希比对确认）。冒烟测试通过。插件无 `user:read`，不要读 `currentUser`/`activeUsers`；组件方法是 `isComponentMainInstance()`；`component.instance()` 可能自动放进最近的画板，需显式改父级；`openPage` 会切换用户可见页面，结束前必须切回；`page.remove()` 可能让任务超时，放最后并重新读取确认。
- Godot 4.6.3（安装位置见本机配置，不写进仓库）；MCP 服务 2.16.0、仓内插件 2.15.0（版本不一致仅告警）。编辑器监听 127.0.0.1:6550，同一时间只开一个编辑器，用完关闭，避免 Codex 连到错误工作树。打开编辑器会把 `project.godot` 改成只有换行符差异，不要提交。
- Obsidian MCP 连不上时，KB 只读 Git；写入等 MCP 恢复并按 sot-kb-write。`gh` 未登录时无法读 Issue/PR。

## 基线观察（锚点，不是本轮审核结论）

- 五个锚点都不是严格网格像素画（网格置信度 <0.1，色数 5–20 万），属于“像素质感插画”；审核时按屏幕上的像素簇大小比较密度，不要求严格网格。
- 特效锚点 `vfx_preview_clean.png`：外轮廓 80% 为近白像素，透明区底色为白，已在黑底/品红底目检确认白灰残边（白底生成后二值抠图）。`portrait_preview_final.png` 透明区残留棋盘格 RGB（alpha 正确）。旧棋子预览板有白边，clean_v2 无。
- 结构性风险待实机核实：项目为 `canvas_items` 1280×720 基准，1080p 是 1.5× 非整数缩放，nearest 下 1 像素细线会粗细交替。按 2 像素美术单位、偶数坐标与偶数边距制作可在 1.5×/2× 下保持均匀（Godot 官方文档对像素游戏建议 viewport + integer 缩放）。
