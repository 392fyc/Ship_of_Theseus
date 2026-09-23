class_name HudM2PopupPlacement
extends RefCounted


static func place_above(anchor: Rect2, popup_size: Vector2, obstacles: Array[Rect2], gap: float, canvas: Rect2) -> Rect2:
	var x: float = clampf(anchor.position.x, canvas.position.x, maxf(canvas.position.x, canvas.end.x - popup_size.x))
	var result := Rect2(Vector2(x, anchor.position.y - gap - popup_size.y), popup_size)
	# 每次只向上移动；再次扫描处理移动后新遇到的障碍。
	for _pass: int in obstacles.size() + 1:
		var next_y: float = result.position.y
		for obstacle: Rect2 in obstacles:
			if result.position.x < obstacle.end.x and result.end.x > obstacle.position.x and result.position.y < obstacle.end.y and result.end.y + gap > obstacle.position.y:
				next_y = minf(next_y, obstacle.position.y - gap - popup_size.y)
		if is_equal_approx(next_y, result.position.y):
			break
		result.position.y = next_y
	return result
