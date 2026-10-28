extends Control
## Stage5 visual candidate: solid shield and full upright weapon silhouettes.
const SIZE := Vector2(17, 17)
const OFFSET := Vector2(14.5, -8.5)
const ROLES := {"myrmidon":"sword", "kensei":"master_sword", "test_lancer":"spear", "lancer":"spear"}
var kind: String = ""
var faction_color: Color = Color.WHITE
func configure(unit_id: String, allegiance: Color) -> void:
	kind = str(ROLES.get(unit_id, ""))
	faction_color = allegiance
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
func shield() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(40):
		var angle: float = TAU * float(i) / 40.0
		points.append(Vector2(8.5,8.5)+Vector2(cos(angle),sin(angle))*8.5)
	return points
func _stroke(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var n := Vector2(-(b-a).y,(b-a).x).normalized()*width*.5
	return PackedVector2Array([a-n,b-n,b+n,a+n])
func blade(a: Vector2, b: Vector2) -> Array[PackedVector2Array]:
	var d := (b-a).normalized()
	var n := Vector2(-d.y,d.x)
	return [PackedVector2Array([a-n*1.2,b-d*2-n*1.2,b,b-d*2+n*1.2,a+n*1.2]),_stroke(a-d*2,a,1.8),_stroke(a-d*.5-n*2.5,a-d*.5+n*2.5,1.6)]
func weapon_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if kind == "spear":
		result.append(_stroke(Vector2(10,17),Vector2(10,6),2))
		result.append(PackedVector2Array([Vector2(10,2),Vector2(6,8),Vector2(14,8)]))
	elif kind == "sword":
		result.append_array(blade(Vector2(10,14),Vector2(10,2)))
	elif kind == "master_sword":
		result.append_array(blade(Vector2(6,14),Vector2(15,3)))
		result.append_array(blade(Vector2(14,14),Vector2(5,3)))
	return result
## Includes the entire opaque plate and border, not only the white icon.
func ink_polygons() -> Array[PackedVector2Array]:
	return [shield()]
func _draw() -> void:
	if kind.is_empty():
		return
	draw_colored_polygon(shield(),Color("cfbc8a"))
	var inner := PackedVector2Array()
	for point: Vector2 in shield():
		inner.append(Vector2(8.5,8.5)+(point-Vector2(8.5,8.5))*.86)
	draw_colored_polygon(inner,Color("232923"))
	if kind == "sword":
		_pixel_sword(Vector2(4,13),Vector2(13,3))
	elif kind == "master_sword":
		_pixel_sword(Vector2(4,14),Vector2(13,3))
		_pixel_sword(Vector2(13,14),Vector2(4,3))
	elif kind == "spear":
		draw_line(Vector2(5,14),Vector2(10,7),Color("151a19"),3,false)
		draw_line(Vector2(5,14),Vector2(10,7),Color("c79d62"),2,false)
		draw_colored_polygon(PackedVector2Array([Vector2(10,9),Vector2(9,6),Vector2(13,2),Vector2(14,6),Vector2(12,9)]),Color("121b20"))
		draw_colored_polygon(PackedVector2Array([Vector2(10,8),Vector2(10,6),Vector2(13,3),Vector2(13,6),Vector2(12,8)]),Color("ece9d6"))
		draw_line(Vector2(10,8),Vector2(13,3),Color("f5ead0"),1,false)

func _pixel_sword(handle: Vector2, tip: Vector2) -> void:
	var axis: Vector2 = (tip-handle).normalized()
	var normal := Vector2(-axis.y,axis.x)
	var guard: Vector2 = handle+axis*3.2
	# Complete blade, distinct guard and grip; dark separation survives crossed swords.
	draw_line(handle,guard,Color("131b1b"),4,false)
	draw_line(handle,guard,Color("c79d62"),2,false)
	var blade_base: Vector2 = guard+axis*.6
	draw_colored_polygon(PackedVector2Array([blade_base-normal*2,tip-axis*2.3-normal*1.7,tip,tip-axis*2.3+normal*1.7,blade_base+normal*2]),Color("14202a"))
	draw_colored_polygon(PackedVector2Array([blade_base-normal*1.1,tip-axis*2-normal,tip,tip-axis*2+normal,blade_base+normal*1.1]),Color("ece9d6"))
	draw_line(blade_base-normal*.9,tip,Color("f5f0d9"),1,false)
	draw_line(guard-normal*3.1,guard+normal*3.1,Color("24201a"),3,false)
	draw_line(guard-normal*2.3,guard+normal*2.3,Color("9b8156"),1.5,false)
