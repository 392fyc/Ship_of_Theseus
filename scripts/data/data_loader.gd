extends Node

var classes:   Dictionary = {}
var skills:    Dictionary = {}
var buffs:     Dictionary = {}
var enemies:   Dictionary = {}
var maps:      Dictionary = {}
var relics:    Dictionary = {}
var buildings: Dictionary = {}
var events:    Dictionary = {}
var affixes:   Dictionary = {}
var waves:     Dictionary = {}
var equipment: Dictionary = {}
var weapons:   Dictionary = {}
# 设计库 State 注册表的引擎镜像（条件类状态：即时判定、不快照、本身不给加成）。
# 访问与求值走 scripts/data/state_registry.gd，不走 BuffEffect——理由见该文件头注释。
var states:    Dictionary = {}
# 天赋载体（Wave 1 · A1）。注册与按事件索引走 scripts/data/talent_registry.gd——
# 那里会拒收不可执行的卡，本字典是未经筛选的原始数据。
var talents:   Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_load_directory("res://data/classes/", classes)
	_load_directory("res://data/skills/", skills)
	_load_directory("res://data/buffs/", buffs)
	_load_directory("res://data/enemies/", enemies)
	_load_directory("res://data/maps/", maps)
	_load_directory("res://data/relics/", relics)
	_load_directory("res://data/buildings/", buildings)
	_load_directory("res://data/events/", events)
	_load_directory("res://data/affixes/base/", affixes)
	_load_directory("res://data/affixes/special/", affixes)
	_load_directory("res://data/waves/", waves)
	_load_directory("res://data/equipment/", equipment)
	_load_directory("res://data/weapons/", weapons)
	_load_directory("res://data/states/", states)
	_load_directory("res://data/talents/", talents)
	print("[DataLoader] Loaded: %d classes, %d skills, %d buffs, %d enemies, %d maps, %d states, %d talents" \
		% [classes.size(), skills.size(), buffs.size(), enemies.size(), maps.size(),
			states.size(), talents.size()])


func _load_directory(path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[DataLoader] Directory not found: " + path)
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var full_path := path + filename
			var data = _parse_json_file(full_path)
			if data is Dictionary and data.has("id"):
				target[data["id"]] = data
		filename = dir.get_next()


func _parse_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataLoader] Cannot open: " + path)
		return null
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("[DataLoader] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	return json.data
