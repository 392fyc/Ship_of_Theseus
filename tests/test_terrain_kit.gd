extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
## 实际运行所有有效异类组合，保留样图并验证输入约束、变体和共享绘制入口。

const Catalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")
const Board := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const PROFILE := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const EXAMPLES := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"
var output: String
var profile: Dictionary
var failures: Array[String] = []
var checks: int = 0
var page: Node
var views: Array[Node2D] = []
var captures: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, success: bool) -> void:
	checks += 1
	if not success:
		failures.append(label)
		print("[FAIL] ", label)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	profile = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	var catalog := Catalog.catalog()
	check("45种无方向组合都有显式记录", catalog["pairs"].size() == 45)
	var legal: Array[Vector2i] = []
	var excluded := 0
	for a: int in 9:
		for b: int in range(a, 9):
			var rule := Catalog.pair_rule(a, b)
			check("交换邻居不改变规则 %d:%d" % [a,b], rule == Catalog.pair_rule(b,a))
			if rule["allowed"] and a != b:
				legal.append(Vector2i(a,b))
			if not rule["allowed"]:
				excluded += 1
				check("拒绝组合有原因", not str(rule["reason"]).is_empty())
	check("32种合法异类与4种排除组合", legal.size() == 32 and excluded == 4)
	for group: int in 4:
		_new_page("地形接壤 · %d / 4" % [group+1], "正式类型之间共用世界坐标混合；地图只保存地形和外观，不保存边缘图片。")
		for slot: int in 8:
			var pair := legal[group * 8 + slot]
			var map := _pair_map(pair.x, pair.y)
			check("合法地形片段 %s" % str(pair), Catalog.validate_layout(map).is_empty())
			var title: String = str(catalog["terrains"][str(pair.x)]["name"]) + "  /  " + str(catalog["terrains"][str(pair.y)]["name"])
			_panel(map, title, slot)
		await _capture("terrain-pairs-%02d.png" % [group+1])
	_new_page("转角与多种地形交会", "内角、外角、窄道、斜接和三四种地形交会，均由同一规则生成。")
	var patterns: Array = [
		[[0,0,0,0,0],[0,5,5,5,0],[0,5,0,5,0],[0,5,5,5,0],[0,0,0,0,0]],
		[[0,0,0,0,0],[0,5,5,0,0],[0,5,0,0,0],[0,0,0,0,0],[0,0,0,0,0]],
		[[0,0,5,0,0],[0,0,5,0,0],[5,5,5,5,5],[0,0,5,0,0],[0,0,5,0,0]],
		[[0,0,0,0,0],[0,5,0,0,0],[0,0,5,0,0],[0,0,0,5,0],[0,0,0,0,0]],
		[[0,0,1,1,1],[0,0,1,1,1],[8,8,5,5,5],[8,8,5,5,5],[8,8,5,5,5]],
		[[3,3,2,2,2],[3,3,2,2,2],[1,1,0,0,0],[1,1,0,0,0],[1,1,0,0,0]],
		[[0,4,0,0,0],[0,4,4,4,0],[0,4,0,4,0],[0,4,4,4,0],[0,0,0,0,0]],
		[[2,2,2,0,0],[2,7,2,0,0],[2,7,2,0,0],[2,2,2,0,0],[0,0,0,0,0]],
	]
	var labels := ["环形岸与内角", "水岸外角", "十字窄水道", "对角接触", "林地 / 平原 / 沼泽 / 水", "山峰 / 山地 / 林地 / 平原", "墙端 / 转角 / T 形", "岩地隔离熔岩"]
	for slot: int in 8:
		var data := _map(patterns[slot])
		check("转角地形片段合法", Catalog.validate_layout(data).is_empty())
		_panel(data, labels[slot], slot)
	await _capture("terrain-corners.png")
	_new_page("障碍物外观库", "连墙、残墙、石柱使用墙类型；山峰可选裸岩或覆苔，地表和通行格仍可辨认。")
	for slot: int in 5:
		var t := 4 if slot < 3 else 3
		var data := _map([[0,0,0,0,0],[0,0,0,0,0],[0,t,t,t,0],[0,0,0,0,0],[0,0,0,0,0]])
		var variant: String = ["dressed","ruined","pillar","rocky","mossy"][slot]
		for x: int in range(1,4):
			data["terrain_variants"]["%d,2" % x] = variant
		if slot < 3:
			for y: int in range(1,4):
				for x: int in range(1,4):
					if data["terrain"][y][x] == 0:
						data["paving"].append([x,y])
		_panel(data, ["砌石连墙","风化残墙","石柱列","裸岩山峰","覆苔山峰"][slot], slot, false, 3)
	_label("墙：自动连接端头与转角\n残墙：降低并打破墙顶轮廓\n石柱：独立立柱，不接成墙\n山峰：相邻时连接山脊和坡脚\n覆苔：在同一山体上改变植被",Vector2(870,475),20)
	await _capture("terrain-obstacles.png")
	var examples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES))
	for id: String in examples:
		check("示例有效 " + id, Catalog.validate_map(examples[id]).is_empty())
		_new_page(str(examples[id]["name"]), "可编辑的 10×10 地形地图 · 关闭格线检查真实接壤")
		_panel(examples[id], "", 0, true)
		await _capture("terrain-example-" + id + ".png")
	# 同一固定输入重复创建输出应一致。排除逐格随机选择带来的手工/自动结果漂移。
	var bytes_first: PackedByteArray = root.get_texture().get_image().get_data()
	_new_page(str(examples["highland"]["name"]), "可编辑的 10×10 地形地图 · 关闭格线检查真实接壤")
	_panel(examples["highland"], "", 0, true)
	await _frames()
	check("同一数据重复生成像素一致", bytes_first == root.get_texture().get_image().get_data())
	var invalid := _map([[1,0],[0,7]])
	check("排除组合对角相邻也拒绝", not Catalog.validate_layout(invalid).is_empty())
	invalid = _map([[0,0],[0,0]])
	invalid["terrain"][0][0] = 0.5
	check("非整数地形拒绝", not Catalog.validate_layout(invalid).is_empty())
	invalid = _map([[0,0],[0,0]])
	invalid["terrain_variants"]["0,0"] = "pillar"
	check("错误地形外观拒绝", not Catalog.validate_layout(invalid).is_empty())
	invalid = _map([[0,0],[0,0]])
	invalid["terrain_variants"]["01,0"] = "paving"
	check("外观非规范坐标拒绝", not Catalog.validate_layout(invalid).is_empty())
	invalid = _map([[0,0],[0,0]])
	invalid["paving"] = [[0,0],[0,0]]
	check("重复铺路坐标拒绝", not Catalog.validate_layout(invalid).is_empty())
	var material: ShaderMaterial = views[0]._surface_layer.material
	var style_texture: Texture2D = material.get_shader_parameter("pair_styles")
	var style_pixels := style_texture.get_image()
	check("砌石岸实际读取组合窄岸参数", is_equal_approx(style_pixels.get_pixel(4,5).r, 0.14))
	check("泥土岸实际读取组合宽岸参数", is_equal_approx(style_pixels.get_pixel(0,5).r, 0.5))
	check("渲染参数交换邻居一致", style_pixels.get_pixel(4,5) == style_pixels.get_pixel(5,4))
	var altered: Dictionary = catalog.duplicate(true)
	altered["transition_styles"]["wet_soil_bank"]["shore_width"] = 0.35
	check("组合表现族参数可以独立调整", is_equal_approx(float(Catalog.transition_style(0,5,altered)["shore_width"]), 0.35))
	await _verify_style_pixels(0, 5, true, 0.95)
	await _verify_style_pixels(0, 7, false, 0.85)
	var report := {"checks":checks,"failures":failures,"allowed_distinct_pairs_rendered":legal.size(),"excluded_pairs":excluded,"captures":captures,"result":"pass" if failures.is_empty() else "fail"}
	var file := FileAccess.open(output.path_join("terrain-kit-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("TERRAIN_KIT_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _verify_style_pixels(a: int, b: int, shore_width: bool, changed: float) -> void:
	_new_page("组合参数接线检查", "固定地图，仅替换该组合的材质参数。")
	_panel(_pair_map(a, b), "", 0, true)
	await _frames()
	var before := root.get_texture().get_image().get_data()
	var material: ShaderMaterial = views[0]._surface_layer.material
	var table: Texture2D = material.get_shader_parameter("pair_styles")
	var values := table.get_image()
	var value := values.get_pixel(a, b)
	if shore_width:
		value.r = changed
	else:
		value.b = changed
	values.set_pixel(a, b, value)
	values.set_pixel(b, a, value)
	material.set_shader_parameter("pair_styles", ImageTexture.create_from_image(values))
	await _frames()
	check("组合参数实际改变画面 %d:%d" % [a,b], before != root.get_texture().get_image().get_data())

func _pair_map(a: int, b: int) -> Dictionary:
	var rows: Array = []
	for y: int in 5:
		var row: Array = []
		for x: int in 5:
			row.append(a if x < 2 else b)
		rows.append(row)
	return _map(rows)

func _map(rows: Array) -> Dictionary:
	return {"id":"terrain_kit_fixture","width":rows[0].size(),"height":rows.size(),"terrain":rows,
		"transition_preview":true,"environment":"terrain_workshop","paving":[],"terrain_variants":{}}

func _new_page(title: String, subtitle: String) -> void:
	if is_instance_valid(page):
		page.free()
	views.clear()
	page = Node.new()
	root.add_child(page)
	var bg := ColorRect.new()
	bg.color = Color("171e21")
	bg.size = root.get_visible_rect().size
	page.add_child(bg)
	_label(title,Vector2(24,15),28)
	_label(subtitle,Vector2(24,56),17)

func _label(text: String, at: Vector2, size: int) -> void:
	var node := Label.new()
	node.theme = load("res://assets/ui/themes/hud_m2.tres")
	node.position = at
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("e2ddc6"))
	page.add_child(node)

func _panel(data: Dictionary, title: String, slot: int, large: bool = false, columns: int = 4) -> void:
	var size := Vector2i(304 if columns == 4 else 404,276) if not large else Vector2i(1232, int(root.get_visible_rect().size.y) - 105)
	var at := Vector2(24+(slot%columns)*(310 if columns == 4 else 414),126+(slot/columns)*314) if not large else Vector2(24,95)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	page.add_child(viewport)
	var texture := TextureRect.new()
	texture.position = at
	texture.size = size
	texture.texture = viewport.get_texture()
	page.add_child(texture)
	_label(title,at-Vector2(0,28),19)
	var grid := Grid.new()
	grid.initialize(data)
	var view := Board.new()
	view.configure(grid,profile,data)
	view.grid_visible = false
	var zoom := 1.65 if large else (0.86 if columns == 4 else 1.2)
	view.scale = Vector2.ONE*zoom
	view.position = Vector2(size)*Vector2(0.5,0.60)-view.point((grid.width-1)*0.5,(grid.height-1)*0.5)*zoom
	viewport.add_child(view)
	view.set_process(false)
	view._time = 2.0
	view.queue_redraw()
	views.append(view)
	check("共用渲染层已创建", view._surface_layer != null)

func _frames() -> void:
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await _frames()
	var path := output.path_join(name)
	check("保存"+name,CaptureMetadata.save_png(root, root.get_texture().get_image(), path)==OK)
	captures[name]=FileAccess.get_sha256(path)
