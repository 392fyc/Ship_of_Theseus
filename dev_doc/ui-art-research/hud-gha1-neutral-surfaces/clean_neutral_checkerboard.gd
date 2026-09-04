extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 3, 5]:
		printerr("Usage: -- <input_png> <output_png> [--trim|--trim-square] [width height]")
		quit(2)
		return

	var source := Image.load_from_file(args[0])
	if source == null or source.is_empty():
		printerr("Could not load input PNG: %s" % args[0])
		quit(3)
		return

	source.convert(Image.FORMAT_RGBA8)
	var pixels := source.get_data()
	for index in range(0, pixels.size(), 4):
		var red := int(pixels[index])
		var green := int(pixels[index + 1])
		var blue := int(pixels[index + 2])
		var minimum := mini(red, mini(green, blue))
		var maximum := maxi(red, maxi(green, blue))
		if maximum - minimum > 16 or minimum < 175:
			continue

		var luminance := 0.2126 * red + 0.7152 * green + 0.0722 * blue
		var cleaned_alpha := 0 if luminance >= 232.0 else roundi(255.0 * (232.0 - luminance) / 57.0)
		pixels[index + 3] = mini(int(pixels[index + 3]), clampi(cleaned_alpha, 0, 255))

	source.set_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, pixels)
	if args.size() == 3 and args[2] in ["--trim", "--trim-square"]:
		source = _trim_to_visible_alpha(source, 8, 2)
		if args[2] == "--trim-square":
			source = _place_on_square_canvas(source)
	if args.size() == 5 and args[2] in ["--trim", "--trim-square"]:
		source = _trim_to_visible_alpha(source, 8, 2)
		if args[2] == "--trim-square":
			source = _place_on_square_canvas(source)
			source = _resize_with_transparent_border(source, int(args[3]), int(args[4]), 1)
		else:
			source = _resize_with_transparent_border(source, int(args[3]), int(args[4]), 1)
	var error := source.save_png(args[1])
	if error != OK:
		printerr("Could not save output PNG: %s (error %s)" % [args[1], error])
		quit(4)
		return

	print("cleaned=%s size=%sx%s" % [args[1], source.get_width(), source.get_height()])
	quit()


func _trim_to_visible_alpha(source: Image, alpha_threshold: int, padding: int) -> Image:
	var pixels := source.get_data()
	var width := source.get_width()
	var height := source.get_height()
	var minimum_x := width
	var minimum_y := height
	var maximum_x := -1
	var maximum_y := -1

	for y in height:
		for x in width:
			var alpha_index := (y * width + x) * 4 + 3
			if int(pixels[alpha_index]) <= alpha_threshold:
				pixels[alpha_index] = 0
				continue
			minimum_x = mini(minimum_x, x)
			minimum_y = mini(minimum_y, y)
			maximum_x = maxi(maximum_x, x)
			maximum_y = maxi(maximum_y, y)

	source.set_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	if maximum_x < minimum_x or maximum_y < minimum_y:
		return source

	var used_rect := Rect2i(
		minimum_x,
		minimum_y,
		maximum_x - minimum_x + 1,
		maximum_y - minimum_y + 1
	)
	var visible := source.get_region(used_rect)
	var result := Image.create_empty(
		visible.get_width() + padding * 2,
		visible.get_height() + padding * 2,
		false,
		Image.FORMAT_RGBA8
	)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(visible, Rect2i(Vector2i.ZERO, visible.get_size()), Vector2i(padding, padding))
	return result


func _place_on_square_canvas(source: Image) -> Image:
	var side := maxi(source.get_width(), source.get_height())
	if source.get_width() == side and source.get_height() == side:
		return source
	var result := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var offset := Vector2i((side - source.get_width()) / 2, (side - source.get_height()) / 2)
	result.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), offset)
	return result


func _resize_with_transparent_border(source: Image, width: int, height: int,
		border: int) -> Image:
	source.resize(width - border * 2, height - border * 2, Image.INTERPOLATE_LANCZOS)
	var result := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(border, border))
	return result
