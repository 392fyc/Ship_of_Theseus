extends SceneTree

const MANIFEST_PATH := "res://dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json"
const WRITE_FLAG := "--write-hud-production-baseline"
const MANIFEST_DIRECTORY := "dev_doc/ui-art-research/hud-production-baseline-v1"
const TARGET_HEAD := "94e10f36757ad247dec0b779cd8859c5c02e61ea"
const PROVENANCE_PATH := "dev_doc/ui-art-research/hud-r1-material-sample-v1/hud-r1-material-direction-v1.png"

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
	["provenance_archive", PROVENANCE_PATH],
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

var _pass := 0
var _fail := 0
var _fails: Array[String] = []
var _category_conflicts: Array[String] = []
var _ran := false


func _initialize() -> void:
	print("=== test_hud_production_baseline_manifest ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_exclusion_contract()
	_test_category_collision_contract()
	var expected_categories := _collect_expected_categories()
	if not _category_conflicts.is_empty():
		_finish()
		return false
	_test_rule_category_contract(expected_categories)
	var expected_paths := _paths_from_categories(expected_categories)
	if WRITE_FLAG in OS.get_cmdline_user_args():
		_write_manifest(expected_paths, expected_categories)
	_check("manifest 存在", FileAccess.file_exists(MANIFEST_PATH))
	if FileAccess.file_exists(MANIFEST_PATH):
		_validate_manifest(expected_paths, expected_categories)
	_finish()
	return false


func _test_exclusion_contract() -> void:
	var nested_cache_paths := [
		"scripts/ui/hud/.godot/imported/hud_cache.bin",
		"scripts/ui/hud/__pycache__/hud_view.cpython-312.pyc",
		"scripts/ui/hud/.cache/preview.bin",
		"scripts/ui/hud/captures/transient_capture.png",
		"scripts/ui/hud/.tmp_godot_mcp_preview.txt",
	]
	for path: String in nested_cache_paths:
		_check("嵌套缓存路径排除：%s" % path, _is_explicitly_excluded(path), path)


func _test_category_collision_contract() -> void:
	var same_category := {}
	_category_conflicts.clear()
	_add_path("tests/repeated_fixture.gd", same_category, "verification_support")
	_add_path("tests/repeated_fixture.gd", same_category, "verification_support")
	_eq("同类别重复保留唯一映射", same_category.get("tests/repeated_fixture.gd"), "verification_support")
	_eq("同类别重复不记录冲突", _category_conflicts.size(), 0)

	var conflicting_category := {}
	_category_conflicts.clear()
	_add_path("tests/conflicting_fixture.gd", conflicting_category, "verification_support")
	_add_path("tests/conflicting_fixture.gd", conflicting_category, "contract_evidence")
	_eq("异类别重复保留首个映射", conflicting_category.get("tests/conflicting_fixture.gd"), "verification_support")
	_check("异类别重复记录冲突", _category_conflicts.size() == 1,
		str(_category_conflicts))


func _test_rule_category_contract(expected_categories: Dictionary) -> void:
	var representative_paths := {
		"assets/ui/themes/hud_structure_prototype.tres": "runtime_candidate",
		"tests/test_hud_production_baseline_manifest.gd": "verification_support",
		"docs/superpowers/specs/2026-09-05-hud-candidate-baseline-freeze-design.md": "contract_evidence",
		PROVENANCE_PATH: "provenance_archive",
	}
	for path: String in representative_paths:
		_eq("规则表分类映射：%s" % path, expected_categories.get(path), representative_paths[path])


func _collect_expected_paths() -> PackedStringArray:
	return _paths_from_categories(_collect_expected_categories())


func _collect_expected_categories() -> Dictionary:
	var categories := {}
	_category_conflicts.clear()
	for rule: Array in RECURSIVE_RULES:
		_append_recursive(String(rule[1]), categories, String(rule[0]))
	for rule: Array in EXACT_FILES:
		_add_path(String(rule[1]), categories, String(rule[0]))
	for rule: Array in NON_RECURSIVE_GLOBS:
		var directory := String(rule[1])
		var pattern := String(rule[2])
		for filename: String in DirAccess.get_files_at("res://" + directory):
			if filename.match(pattern):
				_add_path(directory + "/" + filename, categories, String(rule[0]))
	_check("候选规则无分类冲突", _category_conflicts.is_empty(), "\n".join(_category_conflicts))
	return categories


func _paths_from_categories(categories: Dictionary) -> PackedStringArray:
	var paths := PackedStringArray()
	for path: String in categories:
		paths.append(path)
	paths.sort()
	return paths


func _append_recursive(root_path: String, output: Dictionary, category: String = "") -> void:
	for filename: String in DirAccess.get_files_at("res://" + root_path):
		var path := root_path + "/" + filename
		_add_path(path, output, category)
	for child_directory: String in DirAccess.get_directories_at("res://" + root_path):
		_append_recursive(root_path + "/" + child_directory, output, category)


func _add_path(path: String, output: Dictionary, expected_category: String) -> void:
	var normalized := path.replace("\\", "/").trim_prefix("res://")
	if _is_explicitly_excluded(normalized) or _is_protected_path(normalized):
		return
	if output.has(normalized):
		var existing_category := String(output[normalized])
		if existing_category != expected_category:
			_category_conflicts.append("%s: %s 与 %s" % [normalized, existing_category, expected_category])
		return
	output[normalized] = expected_category


func _category_for(path: String) -> String:
	if path == PROVENANCE_PATH:
		return "provenance_archive"
	if path.begins_with("assets/fonts/ibm_plex_mono/") \
		or path.begins_with("assets/ui/skins/hud/") \
		or path == "assets/ui/themes/hud_structure_prototype.tres" \
		or path.begins_with("scenes/tactical/hud/") \
		or path.begins_with("scripts/ui/hud/"):
		return "runtime_candidate"
	if path.begins_with("scenes/dev/") or path.begins_with("scripts/ui/playground/") \
		or path.begins_with("tests/"):
		return "verification_support"
	if path.begins_with("dev_doc/ui-art-research/") or path.begins_with("docs/superpowers/"):
		return "contract_evidence"
	return ""


func _role_for(path: String, category: String) -> String:
	if path == PROVENANCE_PATH:
		return "GHA-1／GHA-2 生成来源存档"
	match category:
		"runtime_candidate":
			return "HUD 运行候选"
		"verification_support":
			return "HUD 候选验证支架"
		"contract_evidence":
			return "HUD 候选现行合同与证据"
	return ""


func _is_explicitly_excluded(path: String) -> bool:
	if path == MANIFEST_PATH.trim_prefix("res://") or path.ends_with(".import") or path.ends_with(".uid"):
		return true
	var components := path.split("/", false)
	for component: String in components:
		if component in [".godot", "__pycache__", ".cache", "captures"]:
			return true
	var filename := path.get_file()
	if filename.begins_with(".tmp_godot_mcp_") and filename.ends_with(".txt"):
		return true
	for prefix: String in [
		"dev_doc/ui-art-research/hud-r1-atomic-atoms-v1/",
		"dev_doc/ui-art-research/hud-r1-component-sources-v1/",
		"dev_doc/ui-art-research/penpot-hud-r1-review-v3/",
		"dev_doc/ui-art-research/hud-ghv8-numeric-readability/",
	]:
		if path.begins_with(prefix):
			return true
	if path.begins_with("dev_doc/ui-art-research/hud-r1-material-sample-v1/") and path != PROVENANCE_PATH:
		return true
	return path == "dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md" \
		or path == "dev_doc/skillbar-design/hud-r1-atomic-asset-contract.json" \
		or path == "dev_doc/ui-art-research/hud-r1-material-sample-matrix.md" \
		or path == "dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/hourglass-a-gallery-1280x720.png" \
		or path == "docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md" \
		or path == "docs/superpowers/plans/2026-08-31-bottom-dashboard-atomic-asset-system.md" \
		or path == "docs/superpowers/specs/2026-08-31-bottom-dashboard-atomic-asset-architecture.md"


func _is_protected_path(path: String) -> bool:
	if path in [
		"project.godot", "scenes/tactical/TacticalScene.tscn", "scenes/tactical/bottom_dashboard.tscn",
		"scripts/tactical/tactical_scene.gd", "scripts/core/tactical_manager.gd",
		"scripts/ui/bottom_dashboard.gd", "scripts/ui/skill_bar.gd", "scripts/ui/action_resource_bar.gd",
	]:
		return true
	return path.begins_with("scripts/units/") or path.begins_with("data/")


func _write_manifest(expected_paths: PackedStringArray, expected_categories: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	for path: String in expected_paths:
		var category := String(expected_categories.get(path, ""))
		var hash_mode := "binary" if path.ends_with(".png") or path.ends_with(".ttf") else "text_lf"
		var sha256 := FileAccess.get_sha256("res://" + path) if hash_mode == "binary" else _sha256_text_lf(path)
		entries.append({
			"path": path,
			"sha256": sha256,
			"hash_mode": hash_mode,
			"category": category,
			"role": _role_for(path, category),
		})
	var manifest := {
		"schema_version": 1,
		"baseline_id": "hud-godot-candidate-v1",
		"admission_kind": "development_candidate_baseline",
		"target_head_before": TARGET_HEAD,
		"production_admission": false,
		"publication": false,
		"files": entries,
	}
	var directory_path := ProjectSettings.globalize_path("res://" + MANIFEST_DIRECTORY)
	_check("生成目录可创建", DirAccess.make_dir_recursive_absolute(directory_path) == OK)
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	_check("manifest 可写入", file != null)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
		file.close()


func _validate_manifest(expected_paths: PackedStringArray, expected_categories: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var json := JSON.new()
	_check("manifest JSON 可解析", json.parse(text) == OK, json.get_error_message())
	if json.data is not Dictionary:
		_check("manifest 根对象为字典", false)
		return
	var manifest: Dictionary = json.data
	_eq("schema_version", manifest.get("schema_version"), 1)
	_eq("baseline_id", manifest.get("baseline_id"), "hud-godot-candidate-v1")
	_eq("admission_kind", manifest.get("admission_kind"), "development_candidate_baseline")
	_eq("target_head_before", manifest.get("target_head_before"), TARGET_HEAD)
	_eq("production_admission", manifest.get("production_admission"), false)
	_eq("publication", manifest.get("publication"), false)
	var entries: Array = manifest.get("files", [])
	var actual_paths := PackedStringArray()
	var paths_to_entries := {}
	var counts := {"runtime_candidate": 0, "verification_support": 0, "contract_evidence": 0, "provenance_archive": 0}
	for index: int in entries.size():
		var entry: Dictionary = entries[index] if entries[index] is Dictionary else {}
		_validate_entry(index, entry, paths_to_entries, counts, expected_categories)
		actual_paths.append(String(entry.get("path", "")))
	_eq("files 按 path 严格升序", actual_paths, _sorted_paths(actual_paths))
	_eq("files 无重复路径", paths_to_entries.size(), actual_paths.size())
	_eq("files 精确等于机械收集集合", actual_paths, expected_paths)
	_eq("files 总数", entries.size(), 218)
	_eq("runtime_candidate 数量", counts["runtime_candidate"], 43)
	_eq("verification_support 数量", counts["verification_support"], 43)
	_eq("contract_evidence 数量", counts["contract_evidence"], 131)
	_eq("provenance_archive 数量", counts["provenance_archive"], 1)
	_check_git_ignore(actual_paths)
	_validate_review_captures(paths_to_entries)


func _validate_entry(index: int, entry: Dictionary, paths_to_entries: Dictionary, counts: Dictionary,
		expected_categories: Dictionary) -> void:
	var path := String(entry.get("path", ""))
	var category := String(entry.get("category", ""))
	var hash_mode := String(entry.get("hash_mode", ""))
	var sha256 := String(entry.get("sha256", ""))
	_check("条目 %d 路径格式" % index, _is_repository_relative_path(path), path)
	_check("条目 %d 路径存在" % index, FileAccess.file_exists("res://" + path), path)
	_check("条目 %d 分类合法" % index,
		category in ["runtime_candidate", "verification_support", "contract_evidence", "provenance_archive"], category)
	_check("条目 %d 分类匹配正向规则" % index, category == expected_categories.get(path, ""),
		"%s => %s" % [path, category])
	_check("条目 %d 分类满足目录边界" % index, category == _category_for(path), "%s => %s" % [path, category])
	_check("条目 %d role 非空" % index, not String(entry.get("role", "")).is_empty())
	if category == "provenance_archive":
		_eq("来源存档 role", entry.get("role"), "GHA-1／GHA-2 生成来源存档")
	_check("条目 %d hash_mode 合法" % index, hash_mode == "binary" or hash_mode == "text_lf", hash_mode)
	_check("条目 %d hash_mode 匹配文件类型" % index,
		hash_mode == ("binary" if path.ends_with(".png") or path.ends_with(".ttf") else "text_lf"), path)
	_check("条目 %d SHA-256 格式" % index, _is_sha256(sha256), sha256)
	var actual_hash := FileAccess.get_sha256("res://" + path) if hash_mode == "binary" else _sha256_text_lf(path)
	_eq("条目 %d SHA-256 当前值" % index, sha256, actual_hash)
	_check("条目 %d 非明确排除路径" % index, not _is_explicitly_excluded(path), path)
	_check("条目 %d 非正式保护路径" % index, not _is_protected_path(path), path)
	paths_to_entries[path] = entry
	if counts.has(category):
		counts[category] = int(counts[category]) + 1


func _validate_review_captures(paths_to_entries: Dictionary) -> void:
	for path: String in REVIEW_CAPTURES:
		_check("关联截图存在：%s" % path, FileAccess.file_exists("res://" + path))
		_check("关联截图列入 manifest：%s" % path, paths_to_entries.has(path))
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + path))
		var expected_size: Vector2i = REVIEW_CAPTURES[path]
		_check("关联截图尺寸：%s" % path, image != null and image.get_size() == expected_size,
			"actual=%s expected=%s" % [str(image.get_size() if image != null else Vector2i.ZERO), str(expected_size)])


func _check_git_ignore(paths: PackedStringArray) -> void:
	var repository_root := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	for offset: int in range(0, paths.size(), 64):
		var arguments := PackedStringArray(["-C", repository_root, "check-ignore", "--no-index", "--"])
		for index: int in range(offset, mini(offset + 64, paths.size())):
			arguments.append(paths[index])
		var output: Array = []
		var exit_code := OS.execute("git", arguments, output, true)
		_check("批次 %d 未包含 Git 忽略路径" % (offset / 64), exit_code == 1,
			"exit=%d output=%s" % [exit_code, str(output)])


func _sha256_text_lf(repository_path: String) -> String:
	var text := FileAccess.get_file_as_string("res://" + repository_path)
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _sorted_paths(paths: PackedStringArray) -> PackedStringArray:
	var sorted := paths.duplicate()
	sorted.sort()
	return sorted


func _is_repository_relative_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	for component: String in path.split("/"):
		if component.is_empty() or component == "." or component == "..":
			return false
	return true


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not (character >= "0" and character <= "9") and not (character >= "a" and character <= "f"):
			return false
	return true


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	for failure in _fails:
		print("  ✗ " + failure)
	quit(0 if _fail == 0 else 1)
