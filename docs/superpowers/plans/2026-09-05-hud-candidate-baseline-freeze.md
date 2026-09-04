# HUD Candidate Baseline Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已审核的 Godot HUD 候选、验证支架和现行证据冻结为一个可复现且可独立审查的本地 Git 基线。

**Architecture:** 保持正式战斗 HUD 与玩法路径完全不变，只对候选文件建立分层 manifest。使用一个 Godot `SceneTree` 测试同时机械生成和独立验证 manifest：二进制按原始字节哈希，文本先统一为 LF 后哈希；最终从 manifest 精确暂存文件，并在提交前审查 index tree。

**Tech Stack:** Godot 4.6.3、GDScript、JSON、Git、PowerShell。

**Spec:** `docs/superpowers/specs/2026-09-05-hud-candidate-baseline-freeze-design.md`

## Global Constraints

- 工作树固定为 `D:\ShipOfTheseus\worktrees\issue-18-action-resource-bar`，分支固定为 `codex/issue-18-action-resource-bar`。
- Task 起始提交为 `94e10f36757ad247dec0b779cd8859c5c02e61ea`；已审核设计检查点为 `a0ced3a5f3d7cddc9851dd9eba36d679c630db8d`。
- Godot 固定使用 `D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`，版本必须为 `4.6.3.stable.official.7d41c59c4`。
- 不修改正式 `BottomDashboard`、正式技能栏、正式行动资源栏、战斗场景、玩法数据、设计库、KB 或 Mercury。
- 不恢复 `VA-6R`、整图生产或已取代的原子素材路线。
- 不重新生成截图、不改变已审核视觉内容、不生成实际技能或装备图标。
- `*.import`、`*.uid`、`.godot/**`、缓存和规格第 5 节排除项不得进入 manifest 或提交。
- manifest 只表示开发候选基线；`production_admission=false` 且 `publication=false`。
- 本 Task 只创建一个候选基线提交；设计规格检查点提交不属于候选基线提交。
- 禁止 `git add .`、`git add -A`、stash、reset、清理未跟踪文件、push、PR 或保护分支写入。

## Task Card

- **Task ID:** `HUD-PROD-1A-CANDIDATE-BASELINE-FREEZE`
- **规模:** `M`
- **子代理预算级别:** `M`
- **单一主交付物:** 本地提交中的 `hud-godot-candidate-v1` 开发候选基线。
- **允许修改:** 本计划、已批准规格的状态行、`tests/test_hud_production_baseline_manifest.gd`、`dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json`，以及 Task 1 列出的 8 个现行证据文件。
- **只允许收录但不允许改写:** 规格第 4 节列出的其余候选、验证支架、合同证据和一个来源存档文件。
- **禁止路径:** 规格第 5、6 节的全部路径，以及任务前已有的 3 个跟踪修改。
- **相邻问题:** 正式 HUD 接线、行动资源多容量玩法、职业资源 HUD、装备／遗物业务逻辑、素材购买与新图生成均不处理。
- **验收条件 1:** manifest 的路径、分类、角色、哈希和 Git 忽略状态全部通过验证，且暂存路径精确等于 `manifest.files + manifest.json`。
- **验收条件 2:** 26 个受影响测试全部通过，12 张 GHV-10 关联截图存在、尺寸正确并由 manifest 锁定当前 SHA-256，受保护路径相对 Task 起点无变化。
- **验收条件 3:** 独立 reviewer 在提交前批准精确暂存候选；提交后的 `HEAD^{tree}` 等于已审 index tree。
- **纠正策略:** reviewer 最多提出 3 个当前范围阻断；允许一次集中修正，修正后重新生成 manifest、重跑验证并重新审查。

---

### Task 1: 修复现行证据并登记用户批准状态

**Files:**

- Modify: `docs/superpowers/specs/2026-09-05-hud-candidate-baseline-freeze-design.md`
- Modify: `dev_doc/ui-art-research/hud-ghv4-bottom-composition/visual-verdict.json`
- Modify: `dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/visual-verdict.json`
- Modify: `dev_doc/ui-art-research/hud-ghv6-action-resource-segments/evidence/README.md`
- Modify: `dev_doc/ui-art-research/hud-ghv6-action-resource-segments/evidence/visual-verdict.json`
- Modify: `dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/evidence/README.md`
- Modify: `dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/evidence/visual-verdict.json`
- Modify: `dev_doc/ui-art-research/hud-gha5-numeric-font-theme-integration/evidence/visual-verdict.json`
- Modify: `dev_doc/ui-art-research/hud-ghv9-typography-scale/evidence/visual-verdict.json`

**Interfaces:**

- Consumes: 当前 12 张组合／动态图 PNG 的原始字节。
- Produces: 与当前 PNG、五技能默认值和 11px／9px 数值字号一致的现行证据文本。

- [ ] **Step 1: 运行证据预检并确认当前状态为 RED**

```powershell
$root = (git rev-parse --show-toplevel).Trim()
$targets = @(
  'dev_doc/ui-art-research/hud-ghv4-bottom-composition/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv6-action-resource-segments/evidence/README.md',
  'dev_doc/ui-art-research/hud-ghv6-action-resource-segments/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/evidence/README.md',
  'dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-gha5-numeric-font-theme-integration/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv9-typography-scale/evidence/visual-verdict.json'
)
rg -n -e 'default_review_image.*6skills|six runtime hotkeys|six-skill composition|六技能完整底栏|六技能底栏|d89c853f|7065022c|d25c6ed6|112f237a|2c47ad53' $targets
```

Expected: 至少命中 GHV-4、GHV-5、GHV-6、GHV-7、GHA-5 和 GHV-9，证明现行证据仍含陈旧默认表述或陈旧哈希。

- [ ] **Step 2: 更新规格状态**

把规格第 3 行精确改为：

```markdown
**状态：** 推荐路线与书面规格均已于 2026-09-05 获用户批准。
```

- [ ] **Step 3: 修复 GHV-4 九张组合图与默认入口**

在 `hud-ghv4-bottom-composition/visual-verdict.json` 中将 `default_review_image` 改为五技能 1280×720 文件，并按矩阵顺序写入：

```text
5 / 1280x720  fc33d4bf4c9c078a5cb8cdbe89f44691269019de444ea18af8ef0f21ad0e7971
5 / 1920x1080 1b8e46b038a742cd1e8430956de113b7a40aae2f5378c65a35dd5e5b6ecbab8d
5 / 2560x1440 3a9e4cf72dfe6d8dd1ef11b07e94edac053b4dff5888247e02991437c8a751e2
6 / 1280x720  322c880fa65ed1d5f1cfb4a7ca9c178a6c1277d73df258924ef9f740a07a9e4d
6 / 1920x1080 ec5509cc11df628efce40362464d4bde786212a30de3c95bf1844bc3c40bb5bf
6 / 2560x1440 f19be2ac2e11e5132d2c11af0c5e9a7c350e885ad32bb660f2085594234921bd
7 / 1280x720  727f33a2893b0d28149c3a9c5b84b7a739bfb93fef3cb8742ae93a2c39723a5f
7 / 1920x1080 a8201f12e8cdacf41402b089fc91fd275d4995cc74b7ebc32b3cf960de4865ea
7 / 2560x1440 9970df1cf16ad65f697fe0b440e13ace525355fb35a5fa1ae93c2e81bbd63a11
```

- [ ] **Step 4: 修复 GHV-5 三张动态图和运行时描述**

按 `screenshots` 顺序写入：

```text
capacity_1_ready_zero_shield                 798ae4acfd5d95617e0b82cdd3475c86c4ec9048a089e3154cf7ad9cf1ff2817
capacity_2_early_move_lock_long_values       8460746fb04b4a6908bc30370e110d255e9e82ff90ccc9d85864581e4180d3bb
capacity_3_move_exhausted                    a351af0330d54c7c972e0c0e80b62a295aac82ae7d59f072b7c3d1d70b7f8997
```

并做以下精确语义修正：

```text
six runtime hotkeys              -> five runtime hotkeys
long values use the revised 8px  -> long values use the revised 9px
short values recover 8px         -> short values recover 11px
9px to 8px and back to 9px       -> 11px to 9px and back to 11px
```

- [ ] **Step 5: 修复 GHV-6、GHV-7、GHA-5 与 GHV-9 的代表图引用**

统一采用以下当前值：

```text
默认五技能完整底栏：hud_bottom_composition_5skills_1280x720.png
SHA-256：fc33d4bf4c9c078a5cb8cdbe89f44691269019de444ea18af8ef0f21ad0e7971

动态容量 1：798ae4acfd5d95617e0b82cdd3475c86c4ec9048a089e3154cf7ad9cf1ff2817
动态容量 2：8460746fb04b4a6908bc30370e110d255e9e82ff90ccc9d85864581e4180d3bb
动态容量 3：a351af0330d54c7c972e0c0e80b62a295aac82ae7d59f072b7c3d1d70b7f8997
人物 1280×720：c627f03821bb3046ebe06a2c30412440a5bb1dfe84f437dd352522e0f69b70b7
工具区 1280×720：db77135c1fb3fc08eee77e0c3f937f633bd2dfa72402a42350ec4d17946e74b8
```

GHA-5 同时把普通／长值字号改为 `11px`／`9px`，把 `six-skill composition` 改为 `default five-skill composition`。GHV-9 的现行检查说明把“六技能底栏”改为“默认五技能底栏”。GHV-4 README 中的“六技能兼容图”和所有明确的 6／7 技能兼容矩阵保持不变。

- [ ] **Step 6: 运行 JSON、哈希和默认表述验证并确认 GREEN**

```powershell
$jsonFiles = @(
  'dev_doc/ui-art-research/hud-ghv4-bottom-composition/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv6-action-resource-segments/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-gha5-numeric-font-theme-integration/evidence/visual-verdict.json',
  'dev_doc/ui-art-research/hud-ghv9-typography-scale/evidence/visual-verdict.json'
)
foreach ($path in $jsonFiles) {
  Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
}
rg -n -e 'default_review_image.*6skills|six runtime hotkeys|six-skill composition|六技能完整底栏|六技能底栏|d89c853f|7065022c|d25c6ed6|112f237a|2c47ad53' $targets
if ($LASTEXITCODE -eq 0) { throw '现行证据仍含陈旧引用' }
```

Expected: 六个 JSON 全部可解析；最后一次 `rg` 无输出并返回 1。历史 `candidate-receipt.json` 与排除的 GHV-8 不参与此扫描。

- [ ] **Step 7: 暂不提交**

本 Task 的全部内容必须在 Task 4 形成一个候选基线提交；此处不暂存、不提交。

### Task 2: 建立可生成、可验证的 manifest 合同测试

**Files:**

- Create: `tests/test_hud_production_baseline_manifest.gd`
- Create in Task 3: `dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json`

**Interfaces:**

- Consumes: 规格第 4 节目录规则、四种 `category`、LF 文本哈希合同和当前候选文件树。
- Produces: `--write-hud-production-baseline` 显式生成模式，以及默认只读验证模式。

- [ ] **Step 1: 创建 RED 测试入口**

先创建符合仓库 `SceneTree` 测试模式的脚本，并在 manifest 不存在时失败：

```gdscript
extends SceneTree

const MANIFEST_PATH := "res://dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json"
const WRITE_FLAG := "--write-hud-production-baseline"

var _pass := 0
var _fail := 0
var _fails: Array[String] = []
var _ran := false

func _initialize() -> void:
	print("=== test_hud_production_baseline_manifest ===")

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_check("manifest 存在", FileAccess.file_exists(MANIFEST_PATH))
	_finish()
	return false

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))

func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	for failure in _fails:
		print("  ✗ " + failure)
	quit(0 if _fail == 0 else 1)
```

- [ ] **Step 2: 运行测试并确认因 manifest 缺失而失败**

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
& $godot --headless --path $project --script res://tests/test_hud_production_baseline_manifest.gd
if ($LASTEXITCODE -eq 0) { throw 'RED 测试意外通过' }
```

Expected: exit 1，失败项为 `manifest 存在`。

- [ ] **Step 3: 实现确定性的候选集合与分类**

测试必须使用以下函数边界和规则表：

```gdscript
func _collect_expected_paths() -> PackedStringArray
func _append_recursive(root_path: String, output: Dictionary) -> void
func _category_for(path: String) -> String
func _role_for(path: String, category: String) -> String
func _is_explicitly_excluded(path: String) -> bool
func _is_protected_path(path: String) -> bool
```

```gdscript
const RECURSIVE_RULES := [
	["runtime_candidate", "assets/fonts/ibm_plex_mono"],
	["runtime_candidate", "scenes/tactical/hud"],
	["runtime_candidate", "scripts/ui/hud"],
	["contract_evidence", "dev_doc/ui-art-research/penpot-hud-r1-method-reset"],
	["contract_evidence", "dev_doc/ui-art-research/hud-gha1-neutral-surfaces"],
	["contract_evidence", "dev_doc/ui-art-research/hud-gha2-character-surfaces"],
	["contract_evidence", "dev_doc/ui-art-research/hud-gha3-utility-surfaces"],
	["contract_evidence", "dev_doc/ui-art-research/hud-gha4-numeric-font"],
	["contract_evidence", "dev_doc/ui-art-research/hud-gha5-numeric-font-theme-integration"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv2-character-slice"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv3-utility-slice"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv4-bottom-composition"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv6-action-resource-segments"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv7-frame-safe-insets"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv9-typography-scale"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv10-default-five-skills"],
]

const EXACT_FILES := [
	["runtime_candidate", "assets/ui/themes/hud_structure_prototype.tres"],
	["verification_support", "scripts/ui/playground/diamond_board_stress.gd"],
	["contract_evidence", "dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md"],
	["contract_evidence", "dev_doc/ui-art-research/ibm-plex-mono-godot-4-6-2026-09-03.md"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv1-candidate-receipt.json"],
	["contract_evidence", "dev_doc/ui-art-research/hud-ghv1-minimum-asset-needs.md"],
	["contract_evidence", "docs/superpowers/plans/2026-09-02-hud-godot-vertical-slices.md"],
	["contract_evidence", "docs/superpowers/specs/2026-09-05-hud-candidate-baseline-freeze-design.md"],
	["contract_evidence", "docs/superpowers/plans/2026-09-05-hud-candidate-baseline-freeze.md"],
	["provenance_archive", "dev_doc/ui-art-research/hud-r1-material-sample-v1/hud-r1-material-direction-v1.png"],
]

const NON_RECURSIVE_GLOBS := [
	["runtime_candidate", "assets/ui/skins/hud", "*.png"],
	["verification_support", "scenes/dev", "hud_*.tscn"],
	["verification_support", "scripts/ui/playground", "hud_*.gd"],
	["verification_support", "tests", "test_hud_*.gd"],
	["verification_support", "tests", "capture_hud_*.gd"],
	["contract_evidence", "docs/superpowers/plans", "2026-09-03-hud-*.md"],
	["contract_evidence", "docs/superpowers/plans", "2026-09-04-hud-*.md"],
]
```

正向集合精确为：

```text
runtime_candidate:
  assets/fonts/ibm_plex_mono/**
  assets/ui/skins/hud/*.png
  assets/ui/themes/hud_structure_prototype.tres
  scenes/tactical/hud/**
  scripts/ui/hud/**

verification_support:
  scenes/dev/hud_*.tscn
  scripts/ui/playground/diamond_board_stress.gd
  scripts/ui/playground/hud_*.gd
  tests/test_hud_*.gd
  tests/capture_hud_*.gd

contract_evidence:
  上述 RECURSIVE_RULES、EXACT_FILES 和 NON_RECURSIVE_GLOBS 中标为 contract_evidence 的项目
  docs/superpowers/specs/2026-09-05-hud-candidate-baseline-freeze-design.md
  docs/superpowers/plans/2026-09-05-hud-candidate-baseline-freeze.md

provenance_archive:
  dev_doc/ui-art-research/hud-r1-material-sample-v1/hud-r1-material-direction-v1.png
```

收集时统一把 `res://` 去掉并使用 `/`；排除 manifest 自身、全部 `.import`／`.uid`、第 5 节精确排除项和缓存。路径以序数字典去重，最后调用 `sort()`。

- [ ] **Step 4: 实现哈希、写入和只读验证**

文本哈希固定为：

```gdscript
func _sha256_text_lf(repository_path: String) -> String:
	var text := FileAccess.get_file_as_string("res://" + repository_path)
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()
```

`.png` 与 `.ttf` 使用 `hash_mode=binary` 和 `FileAccess.get_sha256()`；其余允许文件使用 `hash_mode=text_lf`。生成根对象固定为：

```gdscript
{
	"schema_version": 1,
	"baseline_id": "hud-godot-candidate-v1",
	"admission_kind": "development_candidate_baseline",
	"target_head_before": "94e10f36757ad247dec0b779cd8859c5c02e61ea",
	"production_admission": false,
	"publication": false,
	"files": entries,
}
```

仅当 `WRITE_FLAG in OS.get_cmdline_user_args()` 时，用 `DirAccess.make_dir_recursive_absolute()` 建目录，并以 `JSON.stringify(manifest, "\t", true) + "\n"` 写入 manifest。默认模式不得写文件。

- [ ] **Step 5: 实现完整 manifest 验证**

默认模式逐项断言：

```text
schema_version == 1
baseline_id == hud-godot-candidate-v1
admission_kind == development_candidate_baseline
target_head_before == 94e10f36757ad247dec0b779cd8859c5c02e61ea
production_admission == false
publication == false
files 按 path 严格升序、无重复，并精确等于机械收集集合
files 总数为 218；分类计数为 runtime_candidate=43、verification_support=43、contract_evidence=131、provenance_archive=1
path 是仓库相对正斜杠路径，不含盘符、反斜杠、空段、.、..
category 只能是四个允许值，且满足对应目录规则
role 非空；来源存档的 role 精确为“GHA-1／GHA-2 生成来源存档”
hash_mode 只能是 binary 或 text_lf，且当前哈希与 sha256 完全相等
sha256 是 64 位小写十六进制字符串
路径不属于明确排除或正式保护范围
```

每 64 个安全路径调用一次 Git：

```gdscript
func _check_git_ignore(paths: PackedStringArray) -> void:
	var repository_root := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	for offset in range(0, paths.size(), 64):
		var arguments := PackedStringArray([
			"-C", repository_root, "check-ignore", "--no-index", "--",
		])
		for index in range(offset, mini(offset + 64, paths.size())):
			arguments.append(paths[index])
		var output: Array = []
		var exit_code := OS.execute("git", arguments, output, true)
		_check("批次 %d 未包含 Git 忽略路径" % (offset / 64), exit_code == 1,
			"exit=%d output=%s" % [exit_code, str(output)])
```

退出码 1 才表示本批没有忽略路径；退出码 0 表示至少一个路径被忽略；其他退出码表示 Git 调用失败。

- [ ] **Step 6: 锁定 12 张关联截图的存在性和尺寸**

在同一测试中使用以下精确表：

```gdscript
const REVIEW_CAPTURES := {
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_5skills_1280x720.png": Vector2i(1280, 720),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_5skills_1920x1080.png": Vector2i(1920, 1080),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_5skills_2560x1440.png": Vector2i(2560, 1440),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_6skills_1280x720.png": Vector2i(1280, 720),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_6skills_1920x1080.png": Vector2i(1920, 1080),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_6skills_2560x1440.png": Vector2i(2560, 1440),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_7skills_1280x720.png": Vector2i(1280, 720),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_7skills_1920x1080.png": Vector2i(1920, 1080),
	"dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence/hud_bottom_composition_7skills_2560x1440.png": Vector2i(2560, 1440),
	"dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/hud_bottom_dynamic_capacity_1_ready_1280x720.png": Vector2i(1280, 720),
	"dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/hud_bottom_dynamic_capacity_2_early_lock_1280x720.png": Vector2i(1280, 720),
	"dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence/hud_bottom_dynamic_capacity_3_exhausted_1280x720.png": Vector2i(1280, 720),
}
```

逐张使用 `Image.load_from_file()` 断言宽高等于表中值，并断言对应路径存在于 manifest；其 SHA-256 已由 manifest 的 `binary` 校验覆盖。

- [ ] **Step 7: 检查测试脚本但仍保持 RED**

```powershell
& $godot --headless --path $project --script res://tests/test_hud_production_baseline_manifest.gd
if ($LASTEXITCODE -eq 0) { throw 'manifest 尚未生成，测试不应通过' }
```

Expected: 脚本可解析和运行；唯一根本失败原因仍是 manifest 不存在。

- [ ] **Step 8: 暂不提交**

Task 2 完成后不修改 Git index，等待 manifest 生成和完整验证。

### Task 3: 生成基线清单并运行完整受影响验证

**Files:**

- Create: `dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json`
- Verify: Task Card 中允许收录的全部候选路径

**Interfaces:**

- Consumes: Task 1 定稿证据、Task 2 生成器／验证器、当前候选文件树。
- Produces: 218 项、按路径升序的 `manifest.files`，以及完整测试证据。

- [ ] **Step 1: 显式生成 manifest**

```powershell
& $godot --headless --path $project --script res://tests/test_hud_production_baseline_manifest.gd -- --write-hud-production-baseline
if ($LASTEXITCODE -ne 0) { throw 'manifest 生成或生成后验证失败' }
```

Expected: 生成 `manifest.json` 后在同一进程完成验证并 exit 0；`files` 精确为 218 项，其中当前预期分类为 runtime 43、verification 43、contract evidence 131、archive 1。若数量不同，必须先用规格正向集合解释差异，不得直接改期望数字掩盖额外文件。

- [ ] **Step 2: 重跑默认只读验证**

```powershell
$before = (Get-FileHash -Algorithm SHA256 'dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json').Hash
& $godot --headless --path $project --script res://tests/test_hud_production_baseline_manifest.gd
if ($LASTEXITCODE -ne 0) { throw 'manifest 默认验证失败' }
$after = (Get-FileHash -Algorithm SHA256 'dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json').Hash
if ($before -ne $after) { throw '默认验证模式修改了 manifest' }
```

Expected: exit 0，且两次哈希相同。

- [ ] **Step 3: 运行 26 个受影响测试**

```powershell
$hudTests = Get-ChildItem -LiteralPath tests -File -Filter 'test_hud_*.gd' |
  Sort-Object Name | ForEach-Object { $_.Name }
$tests = @($hudTests) + @(
  'test_skillbar_v3_ui.gd',
  'test_action_resource_bar.gd',
  'test_action_resource_dashboard.gd',
  'test_action_resource_runtime.gd',
  'test_tactical_inject_smoke.gd'
)
if ($tests.Count -ne 26) { throw "受影响测试数量异常：$($tests.Count)" }
foreach ($test in $tests) {
  & $godot --headless --path $project --script "res://tests/$test"
  if ($LASTEXITCODE -ne 0) { throw "测试失败：$test" }
}
```

Expected: 26 个脚本全部 exit 0，无 `SCRIPT ERROR`、资源缺失或节点缺失。

- [ ] **Step 4: 验证保护范围、格式与来源存档边界**

```powershell
$start = '94e10f36757ad247dec0b779cd8859c5c02e61ea'
$protected = @(
  'project.godot',
  'scenes/tactical/TacticalScene.tscn',
  'scenes/tactical/bottom_dashboard.tscn',
  'scripts/tactical/tactical_scene.gd',
  'scripts/core/tactical_manager.gd',
  'scripts/ui/bottom_dashboard.gd',
  'scripts/ui/skill_bar.gd',
  'scripts/ui/action_resource_bar.gd',
  'scripts/units',
  'data'
)
if (git diff --name-only $start -- $protected) { throw '正式保护路径发生变化' }
git diff --check
if ($LASTEXITCODE -ne 0) { throw '工作树补丁格式检查失败' }
```

Expected: 保护路径比较无输出；`git diff --check` 无错误。来源存档只有 `hud-r1-material-direction-v1.png`，旧目录 README 不在 manifest。

- [ ] **Step 5: 冻结生成后的字节**

从此步骤开始，不再修改 manifest 所列文件。若任何修正改变了其中一个文件，必须重新执行 Task 3 Step 1 至 Step 4。

### Task 4: 精确暂存、独立审查并创建单一基线提交

**Files:**

- Stage: `manifest.files[*].path`
- Stage: `dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json`
- Preserve unstaged: Task Card 禁止路径和 3 个任务前已有跟踪修改

**Interfaces:**

- Consumes: 已验证 manifest 与冻结后的文件字节。
- Produces: 一个本地候选基线提交和可核对的 `candidate_head`。

- [ ] **Step 1: 确认 index 为空并从 manifest 精确暂存**

```powershell
if (git diff --cached --name-only) { throw '开始前 Git index 不为空' }
$manifestPath = 'dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$paths = @($manifest.files.path)
for ($offset = 0; $offset -lt $paths.Count; $offset += 50) {
  $last = [Math]::Min($offset + 49, $paths.Count - 1)
  $batch = @($paths[$offset..$last])
  git --literal-pathspecs add -- $batch
  if ($LASTEXITCODE -ne 0) { throw "暂存批次失败：$offset-$last" }
}
git --literal-pathspecs add -- $manifestPath
if ($LASTEXITCODE -ne 0) { throw '暂存 manifest 失败' }
```

- [ ] **Step 2: 双向比较暂存路径与允许集合**

```powershell
$expected = @(@($paths) + $manifestPath) | Sort-Object -Unique
$actual = @(git -c core.quotepath=false diff --cached --name-only) | Sort-Object -Unique
$delta = Compare-Object $expected $actual
if ($delta) { $delta | Format-Table; throw '暂存路径与允许集合不相等' }
if ($actual.Count -ne 219) { throw "暂存路径数量异常：$($actual.Count)" }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw '暂存补丁格式检查失败' }
$indexTree = (git write-tree).Trim()
if (-not $indexTree) { throw '无法记录待审 index tree' }
$indexTree
```

Expected: `Compare-Object` 无输出，实际路径 219 项，格式检查通过，并输出一个 40 位 tree 标识。

- [ ] **Step 3: 交给独立 reviewer 审查精确暂存候选**

reviewer 只读核对：

```text
任务卡的一个主交付物与三项验收条件
manifest 的 218 个条目及四类边界
暂存路径精确等于 files + manifest
八个证据文件只修当前引用，不改历史回执
六／七技能兼容证据仍保留
正式保护路径相对 94e10f36757ad247dec0b779cd8859c5c02e61ea 无变化
旧 VA-6R、GHV-8、缓存、*.import、*.uid 和三个既有 tracked dirty 文件均未暂存
26 个测试和 manifest 默认验证的最新输出
```

Expected: reviewer 返回 PASS。若返回当前范围阻断，最多执行一次集中修正，然后重新生成 manifest、验证、暂存并复审。

- [ ] **Step 4: reviewer 通过后直接提交，不再改变 index**

```powershell
git commit -m 'chore: freeze HUD candidate baseline v1'
if ($LASTEXITCODE -ne 0) { throw '候选基线提交失败' }
$candidateHead = (git rev-parse HEAD).Trim()
$headTree = (git rev-parse 'HEAD^{tree}').Trim()
if ($headTree -ne $indexTree) { throw '提交树与已审 index tree 不一致' }
$candidateHead
```

- [ ] **Step 5: 提交后核验路径与保护状态**

```powershell
$committed = @(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r HEAD) |
  Sort-Object -Unique
$delta = Compare-Object $expected $committed
if ($delta) { $delta | Format-Table; throw '提交路径与已审允许集合不相等' }
git show --name-status --stat HEAD
git status --short
```

Expected: 提交路径仍精确为 219 项；三个任务前已有跟踪修改和明确排除的未跟踪目录仍留在工作树，未被提交或删除。

- [ ] **Step 6: 返回 Mercury 兼容任务回执**

最终会话回执用提交后已经取得的 `$candidateHead` 组装，字段至少包含：

```powershell
$receipt = [ordered]@{
  task_id = 'HUD-PROD-1A-CANDIDATE-BASELINE-FREEZE'
  status = 'completed'
  target_repository = 'Ship_of_Theseus'
  target_branch = 'codex/issue-18-action-resource-bar'
  target_head_before = '94e10f36757ad247dec0b779cd8859c5c02e61ea'
  candidate_head = $candidateHead
  changed_files = @($manifest.files.path) + $manifestPath
  residual_risks = @(
    '候选尚未接入正式战斗 HUD',
    '本地提交尚未推送或发布'
  )
  escalation_reason = $null
}
```

实际回执继续展开 `contract_summary`、`verification`、`criteria_evidence` 和 `protected_state`；不得把本地基线描述为生产准入或已发布。
