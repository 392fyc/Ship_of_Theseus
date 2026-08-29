# Bottom Dashboard Combined Visual Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改 Godot 的前提下，完成底部界面与人物、战棋棋子、地形、特效统一质感的联合设计、用户验收、正式 UI 素材生产及生产目录准入。

**Architecture:** VA-6 分为仓库外候选阶段和用户批准后的生产阶段。候选图片全部保存在 Main 为任务卡传入的本会话 `review_root`，先通过联合视觉审核；只有绑定视觉批准、来源、使用权和 SHA256 的精确文件才能进入 `assets/ui/bottom_dashboard/`。Godot Theme、场景、脚本和 `.import` 文件全部留给 VA-7。

**Tech Stack:** Codex 内置 `imagegen`（GPT-Image-2）、本地 PNG 机械清理、Python 3、pytest、Git、SoT 固定 KB、独立视觉与技术审查。

**Spec:** `dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md`

## Global Constraints

- 当前只执行 VA-6；不得修改 Godot 场景、GDScript、Theme、`project.godot` 或 `.import` 文件。
- Main 必须在每个仓库外视觉任务卡中传入一个已经解析的绝对 `review_root`；计划和其他版本控制文件不得写入本机绝对路径。
- 用户批准前，生成图片及其机械衍生文件只允许存在于 `review_root`，不得进入 Ship、设计库或 KB 的素材目录。
- 生成只能调用 Codex 内置 `imagegen`；不得配置、读取或调用外部 API key、SDK、CLI 或 HTTP 图像接口。Rika 暂停。
- 购买任何素材前必须由用户明确确认；未出现获批购买候选时不进入第三方素材路线。
- 底部五区顺序保持角色、空职业资源、技能、2×4 八格遗物、结束回合。职业资源内部保持空白。
- 行动资源横条保持技能栏上方紧凑布局；移动为数值，标准行动和迅捷行动各预留最多 3 点。
- 结束回合控件保持最右侧单控件，但允许比提交 `61bd822` 的样板更小。
- 被动技能位略小于主动技能位，但必须支持快捷键、可触发、悬停、按下、选中和禁用状态。快捷键字符由 Godot 渲染，位图只提供无文字角标底框。
- 不设计 Buff/Debuff 血条样式，不生产职业资源内容、完整遗物图标库或战斗动画。
- 人物原画、棋子、地形和特效在候选图中承担统一质感锚点；除非另获精确文件准入，不得把它们误记为本批新生产素材。
- 每个 Task 都必须由未参与作者工作的 reviewer 审查，并返回 `sot-task-receipt`。

### Runtime Variable Contract

- `$ReviewRoot`：Main 在每个仓库外任务卡中传入的本会话 visualizations 绝对目录；执行者不得自行改到仓库内。
- `$ResolvedKbRoot`：按 `SOT_KB_ROOT` 或 `.codex/project/sot-roots.local.toml` 解析出的固定 KB 根。
- `$ReferenceFiles`：Task 2 根据清单解析出的八个精确文件的绝对路径数组，顺序固定为：`ui_preview_final_v3.png`、`portrait_preview_final.png`、`map_token_preview_final_v2.png`、`terrain_preview_final.png`、`vfx_preview_clean.png`、已准入 `map_token_clean_v2.png`、满载布局 `default-v2.png`、消耗态布局 `mixed-v2.png`。
- `$ProductionManifest`：`Join-Path $ReviewRoot 'production\asset_manifest.json'`。

### Manifest Contracts

`00_review_contract.json` 必须包含以下字段，字段名和枚举不得由执行者改写：

```json
{
  "schema_version": 1,
  "batch_id": "va6-bottom-dashboard-v1",
  "ship_head": "40 位小写 Git 提交哈希",
  "spec_path": "dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md",
  "sample_manifest_version": 3,
  "generator": {
    "provider": "codex_builtin_imagegen",
    "external_api": false,
    "rika": false
  },
  "references": [
    {
      "role": "ui_style | portrait_style | map_token_style | terrain_style | vfx_style | production_map_token | layout_full | layout_consumed",
      "file_name": "仅记录文件名，不记录本机绝对路径",
      "sha256": "64 位小写十六进制",
      "pixel_size": [1, 1]
    }
  ],
  "layout": {
    "sections": ["character", "class_resource", "skills", "relics", "end_turn"],
    "class_resource_content": "empty",
    "active_slots": 4,
    "passive_slots": 1,
    "passive_relative_size": "smaller",
    "passive_hotkey_capable": true,
    "end_turn_position": "rightmost",
    "end_turn_relative_size": "smaller_than_61bd822",
    "relic_grid": [2, 4],
    "action_resources": {
      "movement": "numeric",
      "standard_max_points": 3,
      "swift_max_points": 3
    }
  }
}
```

`references` 必须恰好八项，八个 `role` 各出现一次。运行时绝对路径只通过任务卡传递，不写入 JSON。

`candidate_manifest.json` 必须包含 `schema_version=1`、相同 `batch_id`、与审核合同完全相同的 `generator`、`review_contract_sha256` 和六项 `outputs`。每项输出必须包含 `id`、`file_name`、`raw_file_name`、`pixel_size`、`sha256`、`parent_sha256`、`processing`、`approval=pending`。`id` 与文件图中的 `01`—`06` 基名一致；`processing` 是按执行顺序排列的对象数组，每项只允许 `contain`、`crop`、`alpha_cleanup`、`canvas` 四种 `operation`，并记录坐标、目标尺寸、重采样方法和背景色或透明值。

`asset_manifest.json` 必须包含 `schema_version=1`、相同 `batch_id`、六项 `source_candidate_sha256`、`production_sources`、`generator`、`visual_direction_basis`、`visual_approval`、`visual_approval_basis`、`rights_status`、`rights_basis`、`production_admission`、`production_admission_basis` 和十项 `assets`。`production_sources` 每项包含仓库外原始生成文件的 `id`、`file_name` 和 `sha256`；每个正式素材的 `parent_sha256` 必须指向其中一项。每项素材必须包含 `id`、`file_name`、`pixel_size`、`sha256`、`parent_sha256`、非空 `processing`、`texture_filter=nearest`、`alpha_required=true`、`baked_text=false`、`frames`；`processing` 每步只允许 `crop`、`alpha_cleanup`、`split`、`resize`、`color_adjust`，并保存该操作的精确参数；`frames` 是从状态名到 `[x, y, width, height]` 的映射。状态集合固定如下：

| 素材 `id` | 精确状态集合 | 附加字段 |
|---|---|---|
| `panel_frame_9patch` | `idle` | `ninepatch={left,top,right,bottom}`，四值均为正且不越界 |
| `portrait_frame` | `idle` | 无 |
| `skill_slot_active_states` | `idle, hover, pressed, selected, disabled` | 无 |
| `skill_slot_passive_states` | `idle, hover, pressed, selected, disabled` | 无 |
| `hotkey_badge` | `empty` | 不允许任何字符、键名或文字字段 |
| `relic_slot_states` | `empty, occupied, hover, disabled` | 无 |
| `end_turn_button_states` | `idle, hover, pressed, disabled` | 比 `61bd822` 样板紧凑 |
| `action_resource_frame` | `idle` | 无 |
| `action_resource_pips` | `standard_filled, standard_spent, swift_filled, swift_spent` | 每类最多 3 点由引擎重复排布，不在位图烘焙数量 |
| `meter_parts` | `track, hp_fill, shield_fill, xp_fill` | 无 |

所有正式 PNG 必须为 `RGBA`。Task 5 只生成 `visual_direction_basis`，其字段固定为 `kind=user_direction_approval`、`recorded_at`、六项 `candidate_sha256`。正式文件产生后的预准入状态固定为 `visual_approval=pending_exact_file_review`、`rights_status=pending_user_admission`、`production_admission=pending`，对应三个终态依据字段必须为 `null`。用户在 Task 8 查看绑定 SHA256 的精确文件并逐项确认后，才可改为 `approved/verified/approved`，并写入以下三个非空对象：

- `visual_approval_basis`：`kind=user_exact_file_visual_approval`、`recorded_at`、十项 `asset_sha256`；
- `rights_basis`：`kind=codex_builtin_generation_user_authorization`、`recorded_at`、`statement_sha256`、十项 `covered_asset_sha256`；
- `production_admission_basis`：`kind=user_exact_file_admission`、`recorded_at`、十项 `asset_sha256`。

三个映射的键必须恰好是十个正式素材 `id`，值必须与同一 manifest 内对应输出 SHA256 一致。`statement_sha256` 是用户本轮授权原文的 UTF-8 SHA256；manifest 不复制聊天全文。

## File and Artifact Map

### 用户批准前，仅在 `review_root`

- `00_review_contract.json`：本批输入提交、参考文件哈希、布局约束和生成方式。
- `prompts/combined_visual_prompt.md`：设计组收敛后的公共提示与六张图差异要求。
- `raw/`：Codex 内置 imagegen 原始输出。
- `candidate/01_combined_visual_system_board_v1.png`
- `candidate/02_bottom_dashboard_component_states_v1.png`
- `candidate/03_bottom_dashboard_full_state_v1.png`
- `candidate/04_bottom_dashboard_consumed_state_v1.png`
- `candidate/05_cross_asset_cohesion_scene_v1.png`
- `candidate/06_nineslice_and_native_scale_check_v1.png`
- `candidate_manifest.json`：原始输出、机械处理、尺寸与 SHA256。
- `tools/normalize_review_image.py`：只在审核目录内使用的确定性画布归一化脚本。
- `review/visual-review.md`：独立视觉审查结果。

### 用户视觉批准后、正式准入前，仍在 `review_root/production`

- `raw/`：正式十类素材的 Codex 内置 imagegen 原始输出，只作为来源证据，不进入 Ship。
- `panel_frame_9patch.png`
- `portrait_frame.png`
- `skill_slot_active_states.png`
- `skill_slot_passive_states.png`
- `hotkey_badge.png`
- `relic_slot_states.png`
- `end_turn_button_states.png`
- `action_resource_frame.png`
- `action_resource_pips.png`
- `meter_parts.png`
- `asset_manifest.json`

人物原画、头像裁切、代表性技能和遗物图标只用于联合审核，不进入上述首批正式 UI 框体包。人物和实际内容图标另按角色来源、设计库现行技能与遗物记录建立内容素材批次。

### 用户正式准入后，进入 Ship

- `assets/ui/bottom_dashboard/*.png`
- `assets/ui/bottom_dashboard/asset_manifest.json`
- `scripts/codex/validate_bottom_dashboard_assets.py`
- `tests/codex/test_bottom_dashboard_asset_validator.py`

---

### Task 1: 固化补充裁决与计划合同

**Files:**
- Modify: `dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md`
- Create: `docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md`
- Cross-repository modify: KB `04-Assets/visual-style-decisions.md`

**Interfaces:**
- Consumes: 用户对规格的通过、较小结束回合按钮裁决、被动技能快捷键裁决。
- Produces: 后续设计组和审查者使用的唯一 VA-6 文字合同。

- [ ] **Step 1: 核对 Ship 工作树与固定 KB 均无范围外改动**

Run:
```powershell
git status --short --branch
git -C $ResolvedKbRoot status --short --branch
```
Expected: Ship 只出现本 Task 声明的规格和计划文件；KB 写入前为干净的受保护默认分支。

- [ ] **Step 2: 在固定 KB 任务分支记录两项补充裁决**

使用 `sot-kb-write` 的 `vault_get_document_map`、带 `ifMatch` 的 `vault_patch` 和 `vault_read`，使现行 UI 规则明确：结束回合控件允许缩小；被动技能位支持快捷键和可触发状态；快捷键字符不得烘焙。

- [ ] **Step 3: 运行文档一致性检查**

Run:
```powershell
git diff --check
Select-String -Path 'dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md','docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md' -Pattern ('T'+'BD|T'+'ODO|<{7}|={7}|>{7}')
```
Expected: `git diff --check` exit 0；`Select-String` 无输出。

- [ ] **Step 4: 由独立 reviewer 核对规格、计划和 KB current canonical**

Expected: 五区、较小结束回合按钮、被动技能快捷键、候选/生产分离和 VA-6 不进 Godot 全部 PASS；无 Critical 或 Important。

- [ ] **Step 5: 分别提交 Ship 文档和 KB 裁决，并受控发布 KB**

Run:
```powershell
git add dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md
git commit -m 'docs(ui): plan combined visual production'
```
Expected: Ship 提交只包含上述两个文件。KB 从固定 vault 当前任务分支调用 `scripts/codex/sot-publish.ps1`，PR 合并后固定 vault 切回默认分支并 `--ff-only` 更新。

### Task 2: 建立仓库外审核合同与 imagegen 提示

**Files:**
- Create outside repository: `review_root/00_review_contract.json`
- Create outside repository: `review_root/prompts/combined_visual_prompt.md`

**Interfaces:**
- Consumes: Task 1 规格提交、`sample_manifest.json` v3、五张批准预览、已准入 `clean_v2` 棋子、Main 传入的 `review_root` 和两张已通过布局状态截图。
- Produces: Task 3 每次 imagegen 调用使用的同一公共提示与六张图差异合同。

- [ ] **Step 1: 解析并记录所有参考文件的实际路径、尺寸和 SHA256**

Run:
```powershell
Get-FileHash -Algorithm SHA256 $ReferenceFiles
```
Expected: 八个精确参考文件均有非空 SHA256；`references` 恰好包含 `ui_style`、`portrait_style`、`map_token_style`、`terrain_style`、`vfx_style`、`production_map_token`、`layout_full`、`layout_consumed` 各一次；合同记录 Ship HEAD 和 `sample_manifest` version 3。

- [ ] **Step 2: 由专用视觉设计角色写入公共提示合同**

公共提示必须逐字包含以下语义：保持批准五区与行动资源布局；使用略微精细的深色哥特像素化质感；联合参考人物、棋子、地形和特效；结束回合按钮更小；被动技能按钮有快捷键角标与可触发状态；职业资源内部空白；无白底；无烘焙文字；不生成 Buff/Debuff 血条样式或战斗动画。

- [ ] **Step 3: 为六张图写入差异要求**

`01` 展示色彩、材质、像素簇、光照和跨类型母题；`02` 展示主动/被动技能、遗物槽、状态条、行动资源、结束回合的必要状态；`03` 展示满载底栏；`04` 展示消耗状态；`05` 展示棋子、地形、特效与完整底栏同屏；`06` 展示 NinePatch 切线及 720p、1080p、1440p 原生尺寸局部。

- [ ] **Step 4: 独立 reviewer 检查提示未篡改布局或引入未决玩法**

Expected: PASS；提示未要求外部 API、具体职业资源、Buff/Debuff 血条或战斗动画。

### Task 3: 生成并机械整理六张候选审核图

**Files:**
- Create outside repository: `review_root/raw/*`
- Create outside repository: `review_root/candidate/*.png`
- Create outside repository: `review_root/candidate_manifest.json`

**Interfaces:**
- Consumes: Task 2 提示和八个精确本地参考文件：五张批准预览、`map_token_clean_v2.png`、满载布局截图、消耗态布局截图。
- Produces: 文件图中列出的六张候选图及完整原始/衍生身份记录。

- [ ] **Step 1: 由 Main 调用 Codex 内置 imagegen 生成六张原始图**

每次调用使用本地 `referenced_image_paths`，包含批准 UI、人物原画、棋子、地形、特效和对应布局截图。不得传入 API key，也不得用 SDK、CLI 或 HTTP 替代。

- [ ] **Step 2: 把原始结果逐张持久化到 `raw/`**

Expected: 每张原始图有唯一文件名、像素尺寸和 SHA256；聊天中能重新显示，不依赖临时预览 URL。

- [ ] **Step 3: 用审核目录内脚本做可复现的机械整理**

在 `$ReviewRoot\tools\normalize_review_image.py` 写入并运行以下脚本；`01`—`05` 使用 1280×720 画布，`06` 使用 2560×1440 画布并在生成内容中直接包含 720p、1080p、1440p 原生尺寸局部。脚本只能居中缩放并补画布，不得改变生成内容；白底、错误透明边或布局错误必须重新生成，不能靠脚本绘制修复。

```python
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageColor, ImageOps


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--background", default="#08090C")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    contained = ImageOps.contain(
        source,
        (args.width, args.height),
        Image.Resampling.LANCZOS,
    )
    if args.background == "transparent":
        background = (0, 0, 0, 0)
    else:
        background = (*ImageColor.getrgb(args.background), 255)
    canvas = Image.new("RGBA", (args.width, args.height), background)
    offset = (
        (args.width - contained.width) // 2,
        (args.height - contained.height) // 2,
    )
    canvas.alpha_composite(contained, offset)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, format="PNG", optimize=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Run for `01`—`05`:
```powershell
python (Join-Path $ReviewRoot 'tools\normalize_review_image.py') --input $RawFile --output $CandidateFile --width 1280 --height 720 --background '#08090C'
```

Run for `06`:
```powershell
python (Join-Path $ReviewRoot 'tools\normalize_review_image.py') --input $RawFile --output $CandidateFile --width 2560 --height 1440 --background '#08090C'
```

- [ ] **Step 4: 写入候选 manifest 并确认 Ship 工作树没有新增图片**

Run:
```powershell
git status --short
Get-FileHash -Algorithm SHA256 (Join-Path $ReviewRoot 'candidate\*.png')
```
Expected: Git 不出现候选 PNG；六张候选均有哈希。

### Task 4: 独立视觉审查候选包

**Files:**
- Create outside repository: `review_root/review/visual-review.md`

**Interfaces:**
- Consumes: 六张候选原图、规格、布局截图和参考素材。
- Produces: 逐项 PASS/FAIL/PARTIAL 的视觉 verdict。

- [ ] **Step 1: reviewer 以原始尺寸查看全部六张图片**

Expected: 不以 8 倍 nearest 图作为审美依据。

- [ ] **Step 2: 核对布局和新增裁决**

必须确认结束回合按钮比样板更紧凑且仍清晰；被动技能位虽较小，仍有快捷键角标、可触发、悬停、按下、选中和禁用语义。

- [ ] **Step 3: 核对跨素材一致性和机械缺陷**

检查像素密度、光照、金属/石材语言、颜色层级、透明白边、背景残留、图标可读性、UI 是否压过人物和地图，以及是否出现烘焙文字。

- [ ] **Step 4: 对任何 Important 失败返回 Task 2 或 Task 3**

Expected: 只有无 Critical/Important 的候选包可以进入用户视觉门。

### Task 5: 用户视觉门

**Files:**
- No repository changes.

**Interfaces:**
- Consumes: 通过独立审查的六张候选图。
- Produces: 用户视觉通过，或具体修改意见。

- [ ] **Step 1: 在当前会话重新发送六张图片**

同时提供 `review_root` 实际目录、六个文件名和原生尺寸；不能只给目录或失效预览。

- [ ] **Step 2: 明确本门只批准视觉方向**

说明此时尚未准入正式 PNG，也未授予新文件使用权；用户修改意见返回 Task 2—4。

- [ ] **Step 3: 记录用户裁决**

用户明确通过时，立即记录 `visual_direction_basis={kind:user_direction_approval, recorded_at, candidate_sha256}`，其中六项哈希必须与 `candidate_manifest.json` 完全一致。Expected: 只有该依据完整才进入 Task 6；否则继续候选迭代。

### Task 6: 生产正式无文字透明 UI 素材

**Files:**
- Create outside repository: `review_root/production/*.png`
- Create outside repository: `review_root/production/asset_manifest.json`
- Create: `scripts/codex/validate_bottom_dashboard_assets.py`
- Create: `tests/codex/test_bottom_dashboard_asset_validator.py`

**Interfaces:**
- Consumes: Task 5 通过的视觉方向和精确候选 SHA256。
- Produces: 十类正式 UI 框体/状态素材、生产 manifest 和可重复运行的验证器。

- [ ] **Step 1: 先写验证器测试**

测试用临时 RGBA PNG 和 manifest 断言：文件存在；尺寸匹配；SHA256 匹配；存在透明像素；状态集合完整；NinePatch 四边界为正且位于图内；快捷键角标没有字符字段；生成方式、六项候选来源、原始生产父文件和机械处理链完整。严格准入模式只接受 `approved/verified/approved` 及三份逐文件依据；预准入模式只接受 `pending_exact_file_review/pending_user_admission/pending` 且三个终态依据为空，其他机械错误仍必须失败。

`tests/codex/test_bottom_dashboard_asset_validator.py` 使用以下完整测试骨架；后续只允许补充断言，不得弱化这些失败条件：

```python
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

from scripts.codex.validate_bottom_dashboard_assets import validate_manifest


REQUIRED_STATES = {
    "panel_frame_9patch": {"idle"},
    "portrait_frame": {"idle"},
    "skill_slot_active_states": {"idle", "hover", "pressed", "selected", "disabled"},
    "skill_slot_passive_states": {"idle", "hover", "pressed", "selected", "disabled"},
    "hotkey_badge": {"empty"},
    "relic_slot_states": {"empty", "occupied", "hover", "disabled"},
    "end_turn_button_states": {"idle", "hover", "pressed", "disabled"},
    "action_resource_frame": {"idle"},
    "action_resource_pips": {"standard_filled", "standard_spent", "swift_filled", "swift_spent"},
    "meter_parts": {"track", "hp_fill", "shield_fill", "xp_fill"},
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_batch(root: Path) -> Path:
    assets = []
    for asset_id, states in REQUIRED_STATES.items():
        ordered = sorted(states)
        path = root / f"{asset_id}.png"
        image = Image.new("RGBA", (8 * len(ordered), 8), (50, 55, 64, 255))
        image.putpixel((0, 0), (0, 0, 0, 0))
        image.save(path)
        entry = {
            "id": asset_id,
            "file_name": path.name,
            "pixel_size": [image.width, image.height],
            "sha256": _sha256(path),
            "parent_sha256": "c" * 64,
            "processing": [{"operation": "split", "rect": [0, 0, image.width, image.height]}],
            "texture_filter": "nearest",
            "alpha_required": True,
            "baked_text": False,
            "frames": {
                state: [index * 8, 0, 8, 8]
                for index, state in enumerate(ordered)
            },
        }
        if asset_id == "panel_frame_9patch":
            entry["ninepatch"] = {"left": 1, "top": 1, "right": 1, "bottom": 1}
        assets.append(entry)
    manifest = {
        "schema_version": 1,
        "batch_id": "va6-bottom-dashboard-v1",
        "source_candidate_sha256": [f"{index:064x}" for index in range(1, 7)],
        "production_sources": [
            {"id": "production_master_01", "file_name": "raw/production_master_01.png", "sha256": "c" * 64}
        ],
        "generator": {
            "provider": "codex_builtin_imagegen",
            "external_api": False,
            "rika": False,
        },
        "visual_direction_basis": {
            "kind": "user_direction_approval",
            "recorded_at": "2026-08-29T00:00:00+09:00",
            "candidate_sha256": [f"{index:064x}" for index in range(1, 7)],
        },
        "visual_approval": "pending_exact_file_review",
        "visual_approval_basis": None,
        "rights_status": "pending_user_admission",
        "rights_basis": None,
        "production_admission": "pending",
        "production_admission_basis": None,
        "assets": assets,
    }
    path = root / "asset_manifest.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    return path


def _admit(manifest_path: Path) -> None:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    hashes = {asset["id"]: asset["sha256"] for asset in data["assets"]}
    data.update({
        "visual_approval": "approved",
        "visual_approval_basis": {
            "kind": "user_exact_file_visual_approval",
            "recorded_at": "2026-08-29T01:00:00+09:00",
            "asset_sha256": hashes,
        },
        "rights_status": "verified",
        "rights_basis": {
            "kind": "codex_builtin_generation_user_authorization",
            "recorded_at": "2026-08-29T01:00:00+09:00",
            "statement_sha256": "d" * 64,
            "covered_asset_sha256": hashes,
        },
        "production_admission": "approved",
        "production_admission_basis": {
            "kind": "user_exact_file_admission",
            "recorded_at": "2026-08-29T01:00:00+09:00",
            "asset_sha256": hashes,
        },
    })
    manifest_path.write_text(json.dumps(data), encoding="utf-8")


def test_valid_pending_batch_passes_pre_admission(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    assert validate_manifest(manifest_path, require_admission=False) == []


def test_pending_batch_fails_strict_admission(tmp_path: Path) -> None:
    errors = validate_manifest(_write_batch(tmp_path), require_admission=True)
    assert any("rights_status" in error for error in errors)
    assert any("production_admission" in error for error in errors)


def test_admitted_batch_passes_strict_admission(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    _admit(manifest_path)
    assert validate_manifest(manifest_path, require_admission=True) == []


def test_missing_passive_state_fails(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    passive = next(item for item in data["assets"] if item["id"] == "skill_slot_passive_states")
    passive["frames"].pop("pressed")
    manifest_path.write_text(json.dumps(data), encoding="utf-8")
    assert any("skill_slot_passive_states states" in error for error in validate_manifest(manifest_path, require_admission=False))


def test_hotkey_badge_text_field_fails(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    badge = next(item for item in data["assets"] if item["id"] == "hotkey_badge")
    badge["text"] = "1"
    manifest_path.write_text(json.dumps(data), encoding="utf-8")
    assert any("hotkey_badge text" in error for error in validate_manifest(manifest_path, require_admission=False))


def test_hash_and_ninepatch_bounds_fail(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    panel = next(item for item in data["assets"] if item["id"] == "panel_frame_9patch")
    panel["sha256"] = "0" * 64
    panel["ninepatch"]["left"] = panel["pixel_size"][0]
    manifest_path.write_text(json.dumps(data), encoding="utf-8")
    errors = validate_manifest(manifest_path, require_admission=False)
    assert any("sha256" in error for error in errors)
    assert any("ninepatch" in error for error in errors)


def test_missing_provenance_fails(tmp_path: Path) -> None:
    manifest_path = _write_batch(tmp_path)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    data["production_sources"] = []
    data["assets"][0]["processing"] = []
    manifest_path.write_text(json.dumps(data), encoding="utf-8")
    errors = validate_manifest(manifest_path, require_admission=False)
    assert any("parent_sha256" in error for error in errors)
    assert any("processing" in error for error in errors)
```

- [ ] **Step 2: 运行测试确认红灯**

Run:
```powershell
python -m pytest tests/codex/test_bottom_dashboard_asset_validator.py -q
```
Expected: FAIL，因为验证器尚不存在。

- [ ] **Step 3: 实现最小验证器**

`scripts/codex/validate_bottom_dashboard_assets.py` 实现以下合同代码：

```python
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from PIL import Image


REQUIRED_STATES = {
    "panel_frame_9patch": {"idle"},
    "portrait_frame": {"idle"},
    "skill_slot_active_states": {"idle", "hover", "pressed", "selected", "disabled"},
    "skill_slot_passive_states": {"idle", "hover", "pressed", "selected", "disabled"},
    "hotkey_badge": {"empty"},
    "relic_slot_states": {"empty", "occupied", "hover", "disabled"},
    "end_turn_button_states": {"idle", "hover", "pressed", "disabled"},
    "action_resource_frame": {"idle"},
    "action_resource_pips": {"standard_filled", "standard_spent", "swift_filled", "swift_spent"},
    "meter_parts": {"track", "hp_fill", "shield_fill", "xp_fill"},
}
FORBIDDEN_HOTKEY_FIELDS = {"text", "label", "key", "key_name", "character"}
ALLOWED_PROCESSING = {"crop", "alpha_cleanup", "split", "resize", "color_adjust"}
GENERATOR = {"provider": "codex_builtin_imagegen", "external_api": False, "rika": False}
HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _is_hash(value: Any) -> bool:
    return isinstance(value, str) and HASH_PATTERN.fullmatch(value) is not None


def _validate_basis(
    name: str,
    basis: Any,
    expected_kind: str,
    hash_field: str,
    asset_hashes: dict[str, str],
) -> list[str]:
    if not isinstance(basis, dict):
        return [f"{name} must be an object"]
    errors = []
    if basis.get("kind") != expected_kind:
        errors.append(f"{name} kind mismatch")
    if not isinstance(basis.get("recorded_at"), str) or not basis["recorded_at"]:
        errors.append(f"{name} recorded_at missing")
    if basis.get(hash_field) != asset_hashes:
        errors.append(f"{name} {hash_field} mismatch")
    return errors


def _validate_frame(asset_id: str, state: str, frame: Any, size: tuple[int, int]) -> str | None:
    if not isinstance(frame, list) or len(frame) != 4 or not all(isinstance(value, int) for value in frame):
        return f"{asset_id} frame {state} must be four integers"
    x, y, width, height = frame
    if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > size[0] or y + height > size[1]:
        return f"{asset_id} frame {state} is outside image bounds"
    return None


def validate_manifest(manifest_path: Path, *, require_admission: bool) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"manifest unreadable: {exc}"]

    if data.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if data.get("batch_id") != "va6-bottom-dashboard-v1":
        errors.append("batch_id mismatch")
    if data.get("generator") != GENERATOR:
        errors.append("generator mismatch")
    candidate_hashes = data.get("source_candidate_sha256")
    if not isinstance(candidate_hashes, list) or len(candidate_hashes) != 6 or not all(_is_hash(value) for value in candidate_hashes) or len(set(candidate_hashes)) != 6:
        errors.append("source_candidate_sha256 must contain six unique hashes")
        candidate_hashes = []
    direction_basis = data.get("visual_direction_basis")
    if not isinstance(direction_basis, dict) or direction_basis.get("kind") != "user_direction_approval" or not direction_basis.get("recorded_at") or direction_basis.get("candidate_sha256") != candidate_hashes:
        errors.append("visual_direction_basis mismatch")

    production_sources = data.get("production_sources")
    if not isinstance(production_sources, list) or not production_sources:
        errors.append("production_sources must be a non-empty list")
        parent_hashes: set[str] = set()
    else:
        parent_hashes = {
            source.get("sha256")
            for source in production_sources
            if isinstance(source, dict) and source.get("id") and source.get("file_name") and _is_hash(source.get("sha256"))
        }
        if len(parent_hashes) != len(production_sources):
            errors.append("production_sources entries must have unique valid hashes")

    expected_visual = "approved" if require_admission else "pending_exact_file_review"
    expected_rights = "verified" if require_admission else "pending_user_admission"
    expected_admission = "approved" if require_admission else "pending"
    if data.get("visual_approval") != expected_visual:
        errors.append(f"visual_approval must be {expected_visual}")
    if data.get("rights_status") != expected_rights:
        errors.append(f"rights_status must be {expected_rights}")
    if data.get("production_admission") != expected_admission:
        errors.append(f"production_admission must be {expected_admission}")

    entries = data.get("assets")
    if not isinstance(entries, list):
        return errors + ["assets must be a list"]
    by_id = {entry.get("id"): entry for entry in entries if isinstance(entry, dict)}
    if len(entries) != len(REQUIRED_STATES) or set(by_id) != set(REQUIRED_STATES):
        errors.append("asset id set mismatch")
    asset_hashes = {
        asset_id: entry.get("sha256")
        for asset_id, entry in by_id.items()
        if asset_id in REQUIRED_STATES
    }
    if require_admission:
        errors.extend(_validate_basis("visual_approval_basis", data.get("visual_approval_basis"), "user_exact_file_visual_approval", "asset_sha256", asset_hashes))
        errors.extend(_validate_basis("rights_basis", data.get("rights_basis"), "codex_builtin_generation_user_authorization", "covered_asset_sha256", asset_hashes))
        rights_basis = data.get("rights_basis")
        if not isinstance(rights_basis, dict) or not _is_hash(rights_basis.get("statement_sha256")):
            errors.append("rights_basis statement_sha256 invalid")
        errors.extend(_validate_basis("production_admission_basis", data.get("production_admission_basis"), "user_exact_file_admission", "asset_sha256", asset_hashes))
    elif any(data.get(name) is not None for name in ("visual_approval_basis", "rights_basis", "production_admission_basis")):
        errors.append("pending batch approval basis fields must be null")

    for asset_id, required_states in REQUIRED_STATES.items():
        asset = by_id.get(asset_id)
        if asset is None:
            continue
        if asset.get("baked_text") is not False:
            errors.append(f"{asset_id} baked_text must be false")
        if asset.get("texture_filter") != "nearest":
            errors.append(f"{asset_id} texture_filter must be nearest")
        if asset.get("alpha_required") is not True:
            errors.append(f"{asset_id} alpha_required must be true")
        if asset_id == "hotkey_badge" and FORBIDDEN_HOTKEY_FIELDS.intersection(asset):
            errors.append("hotkey_badge text fields are forbidden")
        if not _is_hash(asset.get("parent_sha256")) or asset.get("parent_sha256") not in parent_hashes:
            errors.append(f"{asset_id} parent_sha256 is not linked to production_sources")
        processing = asset.get("processing")
        if not isinstance(processing, list) or not processing:
            errors.append(f"{asset_id} processing must be non-empty")
        elif any(not isinstance(step, dict) or step.get("operation") not in ALLOWED_PROCESSING for step in processing):
            errors.append(f"{asset_id} processing operation invalid")

        file_name = asset.get("file_name")
        file_path = manifest_path.parent / file_name if isinstance(file_name, str) else None
        if file_path is None or not file_path.is_file():
            errors.append(f"{asset_id} file missing")
            continue
        if asset.get("sha256") != _sha256(file_path):
            errors.append(f"{asset_id} sha256 mismatch")
        try:
            with Image.open(file_path) as image:
                image.load()
                if image.mode != "RGBA":
                    errors.append(f"{asset_id} mode must be RGBA")
                size = image.size
                if asset.get("pixel_size") != [size[0], size[1]]:
                    errors.append(f"{asset_id} pixel_size mismatch")
                if image.mode == "RGBA" and image.getchannel("A").getextrema()[0] == 255:
                    errors.append(f"{asset_id} has no transparent pixel")
        except OSError as exc:
            errors.append(f"{asset_id} PNG unreadable: {exc}")
            continue

        frames = asset.get("frames")
        if not isinstance(frames, dict) or set(frames) != required_states:
            errors.append(f"{asset_id} states mismatch")
        else:
            for state, frame in frames.items():
                frame_error = _validate_frame(asset_id, state, frame, size)
                if frame_error:
                    errors.append(frame_error)

        if asset_id == "panel_frame_9patch":
            margins = asset.get("ninepatch")
            keys = {"left", "top", "right", "bottom"}
            if not isinstance(margins, dict) or set(margins) != keys or not all(isinstance(margins[key], int) and margins[key] > 0 for key in keys):
                errors.append("panel_frame_9patch ninepatch margins invalid")
            elif margins["left"] + margins["right"] >= size[0] or margins["top"] + margins["bottom"] >= size[1]:
                errors.append("panel_frame_9patch ninepatch margins out of bounds")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--allow-pending-admission", action="store_true")
    args = parser.parse_args()
    errors = validate_manifest(args.manifest, require_admission=not args.allow_pending_admission)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

可选 `--allow-pending-admission` 把 `require_admission` 设为 `False`。存在任何错误时逐行输出错误并返回 exit 1，无错误时返回 exit 0。使用工作区 bundled Python/Pillow 读取 PNG；不连接网络，不修改输入文件。

- [ ] **Step 4: 运行测试确认绿灯**

Run:
```powershell
python -m pytest tests/codex/test_bottom_dashboard_asset_validator.py -q
```
Expected: PASS。

- [ ] **Step 5: 通过 Codex 内置 imagegen 生产十类分离的透明母版**

严格按 Manifest Contracts 中十个素材 `id` 和精确状态集合生成 `panel_frame_9patch.png`、`portrait_frame.png`、`skill_slot_active_states.png`、`skill_slot_passive_states.png`、`hotkey_badge.png`、`relic_slot_states.png`、`end_turn_button_states.png`、`action_resource_frame.png`、`action_resource_pips.png`、`meter_parts.png`。同一文件的状态从左到右按表格中的顺序排列，并在 `frames` 记录每格矩形。生产母版不得包含人物场景背景、快捷键字符、按钮文字或数值。

- [ ] **Step 6: 机械拆分正式文件并记录父文件链**

每项记录原始父文件 SHA256、裁切坐标、透明清理、尺寸转换、输出 SHA256、像素尺寸、过滤方式和 NinePatch 边界。Task 5 裁决只写入 `visual_direction_basis`；此时精确文件状态固定为 `visual_approval=pending_exact_file_review`、`rights_status=pending_user_admission`、`production_admission=pending`，三个终态依据字段保持 `null`。

- [ ] **Step 7: 运行验证器的预准入模式**

Run:
```powershell
python scripts/codex/validate_bottom_dashboard_assets.py $ProductionManifest --allow-pending-admission
```
Expected: exit 0；除使用权最终准入外的机械合同全部通过。

### Task 7: 独立技术审查正式候选

**Files:**
- Create outside repository: `review_root/review/production-review.md`

**Interfaces:**
- Consumes: Task 6 生产目录、manifest、验证器测试输出。
- Produces: 正式文件逐项技术 verdict。

- [ ] **Step 1: reviewer 核对十类文件与 manifest 一一对应**

Expected: 不缺状态、不混入头像裁切或代表性内容图标、不含职业资源内部素材；生成方式、六项候选来源、原始生产父文件及非空机械处理链全部可追溯。

- [ ] **Step 2: reviewer 检查透明、白边、NinePatch 和原生尺寸**

Expected: 最小、标准、最大拉伸无角饰变形；主动/被动状态和较小结束回合按钮可读；快捷键底框没有烘焙字符。

- [ ] **Step 3: reviewer 复跑验证器测试和预准入验证**

Expected: pytest PASS，预准入 exit 0。

- [ ] **Step 4: 无 Critical/Important 才进入用户正式准入**

### Task 8: 用户正式素材准入

**Files:**
- Modify outside repository: `review_root/production/asset_manifest.json`
- Cross-repository modify: fixed KB `04-Assets/visual-style-decisions.md`

**Interfaces:**
- Consumes: 通过技术审查的精确生产文件和 SHA256 清单。
- Produces: 用户视觉、使用权和生产目录准入裁决。

- [ ] **Step 1: 在当前会话展示正式文件及检查图**

发送原生尺寸组合图、状态对照、NinePatch 拉伸图、生产目录和精确哈希清单。

- [ ] **Step 2: 请求三项独立确认**

用户需确认视觉通过、Codex 内置图像生成及本地机械处理的精确文件可用于项目/修改/随游戏分发、绑定 SHA256 的文件获准进入正式素材目录。第三方购买素材若存在，以核验后的商业许可为权利依据，不能用用户声明替代。

- [ ] **Step 3: 将 manifest 状态和三类依据改为已准入并回读**

将 `visual_approval_basis`、`rights_basis`、`production_admission_basis` 按 Manifest Contracts 写入；三份素材哈希映射都必须从当前十项 `assets` 机械构造，授权原文以 UTF-8 计算 `statement_sha256`。Expected: `visual_approval=approved`、`rights_status=verified`、`production_admission=approved`，三份依据非空且逐项匹配，所有 PNG SHA256 不变。

- [ ] **Step 4: 在固定 KB 记录用户对精确批次的裁决**

按 `sot-kb-write` 流程在固定 vault 的独立任务分支记录 `batch_id`、最终 manifest SHA256、用户视觉通过、授权与正式目录准入三项裁决及 `statement_sha256`，不复制授权全文或本机路径。独立回读后提交，并通过 Ship 根 `scripts/codex/sot-publish.ps1` 受控发布；PR 合并后固定 vault 切回并快进到受保护默认分支。

### Task 9: 精确文件进入 Ship 并提交

**Files:**
- Create: `assets/ui/bottom_dashboard/*.png`
- Create: `assets/ui/bottom_dashboard/asset_manifest.json`
- Modify only if needed for provenance link: `assets/prototype/visual_style/README.md`

**Interfaces:**
- Consumes: Task 8 已准入的精确文件与 manifest。
- Produces: Ship 正式 UI 素材目录；VA-7 可读取但尚未导入 Godot。

- [ ] **Step 1: 复制精确批准文件并验证字节身份**

Run:
```powershell
Get-FileHash -Algorithm SHA256 (Join-Path $ReviewRoot 'production\*.png')
Get-FileHash -Algorithm SHA256 'assets\ui\bottom_dashboard\*.png'
```
Expected: 每个源/目标 SHA256 成对相同。

- [ ] **Step 2: 运行生产准入验证**

Run:
```powershell
python scripts/codex/validate_bottom_dashboard_assets.py assets/ui/bottom_dashboard/asset_manifest.json
python -m pytest tests/codex/test_bottom_dashboard_asset_validator.py -q
```
Expected: 两个命令均 exit 0。

- [ ] **Step 3: 确认没有 Godot 实现或导入副产物**

Run:
```powershell
git status --short
git diff --name-only
```
Expected: 只出现规格、计划、验证器、测试、批准 PNG、正式 manifest 和必要 README；没有 `.import`、`.gd`、`.tscn`、`project.godot` 或 Theme 文件。

- [ ] **Step 4: 独立 reviewer 核对批准文件身份和范围**

Expected: 精确 SHA256、用户准入、来源链、无烘焙文字、较小结束回合按钮、被动快捷键角标合同全部 PASS。

- [ ] **Step 5: 提交 VA-6 正式素材包**

Run:
```powershell
git add dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md scripts/codex/validate_bottom_dashboard_assets.py tests/codex/test_bottom_dashboard_asset_validator.py assets/ui/bottom_dashboard assets/prototype/visual_style/README.md
git commit -m 'feat(ui): admit bottom dashboard visual assets'
```
Expected: commit 成功；工作树干净。不得在本 Task 发布或合并现有 Issue #18 分支，除非独立分支终验确认早期 Godot 占位实现不会被误作为最终材质。

## VA-7 Entry Gate

完成 Task 9 只表示 VA-6 完成。只有正式素材 SHA256、来源、使用权、用户准入和技术验证全部有效，才另行制定 VA-7 Godot 导入计划；不得把 VA-6 的 PNG 入仓表述为已经完成引擎接入。
