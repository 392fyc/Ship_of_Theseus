extends SceneTree

const SOURCE := "res://dev_doc/ui-art-research/myrmidon-skill-icons/candidate-v3"
const TARGET := "res://assets/ui/skills/myrmidon"
const ICONS := ["xinyan", "zhanji", "yishan", "zhaojia", "juhe"]


func _initialize() -> void:
	var directory: String = ProjectSettings.globalize_path(TARGET)
	DirAccess.make_dir_recursive_absolute(directory)
	for skill_id: String in ICONS:
		var filename: String = "%s-source.png" % skill_id
		var source_path: String = ProjectSettings.globalize_path(SOURCE.path_join(filename))
		var image: Image = Image.load_from_file(source_path)
		if image == null:
			push_error("Missing icon source: " + filename)
			quit(1)
			return
		image.resize(104, 104, Image.INTERPOLATE_LANCZOS)
		var target_path: String = directory.path_join(skill_id + ".png")
		if image.save_png(target_path) != OK:
			push_error("Cannot save icon: " + skill_id)
			quit(1)
			return
		print("MYRMIDON_ICON ", skill_id, " 104x104 ", FileAccess.get_sha256(target_path))
	quit()
