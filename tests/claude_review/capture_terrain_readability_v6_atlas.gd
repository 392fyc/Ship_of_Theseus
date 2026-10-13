extends "res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd"
## Keeps crown masks on the same full-atlas sampling path as the source Sprite2D.

const ATLAS_MASK_ENTRY_SCRIPT := "res://tests/claude_review/capture_terrain_readability_v6_atlas.gd"
const ATLAS_MASK_SCRIPT_CHAIN: PackedStringArray = [
	ATLAS_MASK_ENTRY_SCRIPT,
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/capture_terrain_readability.gd",
]
const ATLAS_MASK_SOURCE_PATHS: PackedStringArray = [
	ATLAS_MASK_ENTRY_SCRIPT,
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/capture_terrain_readability.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_atlas.gd",
	"res://dev_doc/ui-art-research/terrain-readability/atlas-mask-sampling-fix.md",
	"res://tests/claude_review/test_terrain_readability_atlas_mask_contract.py",
]


func _make_annotated_texture(sprite: Sprite2D, polygon_records: Array) -> Texture2D:
	var region_mask: Texture2D = super._make_annotated_texture(sprite, polygon_records)
	if region_mask == null:
		return null
	var crown_polygons: Array = _region_regions().get("crown", [])
	if _sha256_text(JSON.stringify(polygon_records)) != _sha256_text(JSON.stringify(crown_polygons)):
		return region_mask
	var source_atlas := sprite.texture as AtlasTexture
	if source_atlas == null or source_atlas.atlas == null:
		return null
	var source_atlas_image: Image = source_atlas.atlas.get_image()
	var region_mask_image: Image = region_mask.get_image()
	if source_atlas_image == null or source_atlas_image.is_empty() \
			or region_mask_image == null or region_mask_image.is_empty():
		return null
	var region_rect := _atlas_region_rect(source_atlas.region)
	if region_rect.size != region_mask_image.get_size() \
			or region_rect.position.x < 0 or region_rect.position.y < 0 \
			or region_rect.end.x > source_atlas_image.get_width() \
			or region_rect.end.y > source_atlas_image.get_height():
		return null
	var full_atlas_mask := Image.create(source_atlas_image.get_width(), source_atlas_image.get_height(), false, Image.FORMAT_RGBA8)
	full_atlas_mask.fill(Color(0, 0, 0, 0))
	full_atlas_mask.blit_rect(region_mask_image,
		Rect2i(Vector2i.ZERO, region_mask_image.get_size()), region_rect.position)
	var masked_atlas := AtlasTexture.new()
	masked_atlas.atlas = ImageTexture.create_from_image(full_atlas_mask)
	masked_atlas.region = source_atlas.region
	masked_atlas.margin = source_atlas.margin
	masked_atlas.filter_clip = source_atlas.filter_clip
	return masked_atlas


func _atlas_region_rect(region: Rect2) -> Rect2i:
	return Rect2i(
		Vector2i(roundi(region.position.x), roundi(region.position.y)),
		Vector2i(roundi(region.size.x), roundi(region.size.y)))


func _validate_annotated_region_clone(source_root: Node2D, source_sprite: Sprite2D,
		copy_root: Node2D, copy_sprite: Sprite2D, rgb: Color, region_name: String, mode: String) -> Dictionary:
	var validation: Dictionary = super._validate_annotated_region_clone(
		source_root, source_sprite, copy_root, copy_sprite, rgb, region_name, mode)
	if str(validation.get("status", "")) != "PASS_STRUCTURE_ONLY":
		return validation
	if region_name != "crown":
		return validation
	var source_atlas := source_sprite.texture as AtlasTexture
	var mask_atlas := copy_sprite.texture as AtlasTexture
	if source_atlas == null or mask_atlas == null or source_atlas.atlas == null or mask_atlas.atlas == null:
		return {"status": "FAIL", "reason": "crown mask is not backed by source and mask AtlasTexture resources"}
	if mask_atlas.region != source_atlas.region \
			or mask_atlas.margin != source_atlas.margin \
			or mask_atlas.filter_clip != source_atlas.filter_clip:
		return {"status": "FAIL", "reason": "crown mask AtlasTexture region, margin, or filter_clip differs from source"}
	var source_atlas_image: Image = source_atlas.atlas.get_image()
	var mask_atlas_image: Image = mask_atlas.atlas.get_image()
	if source_atlas_image == null or mask_atlas_image == null \
			or source_atlas_image.is_empty() or mask_atlas_image.is_empty() \
			or source_atlas_image.get_size() != mask_atlas_image.get_size():
		return {"status": "FAIL", "reason": "crown mask backing atlas dimensions differ from the source atlas"}
	var region_image: Image = mask_atlas.get_image()
	if region_image == null or region_image.is_empty() \
			or region_image.get_size() != _atlas_region_rect(source_atlas.region).size:
		return {"status": "FAIL", "reason": "crown AtlasTexture.get_image() dimensions do not match the source region"}
	var alpha_pixels := 0
	for y: int in region_image.get_height():
		for x: int in region_image.get_width():
			if region_image.get_pixel(x, y).a > 0.0:
				alpha_pixels += 1
	if alpha_pixels <= 0:
		return {"status": "FAIL", "reason": "approved crown geometry produced an empty AtlasTexture region alpha mask"}
	validation["alpha_path"] = "SHA-bound source atlas alpha intersected with reviewed crown geometry, stored in a full-size RGBA8 atlas and sampled through an AtlasTexture with matching region, margin, and filter_clip; AtlasTexture.get_image() verifies the region; flat shader forwards COLOR.a; source root/Sprite2D modulation alpha and transforms match"
	validation["mask_storage"] = "full-atlas ImageTexture wrapped by AtlasTexture"
	validation["source_atlas_size"] = [source_atlas_image.get_width(), source_atlas_image.get_height()]
	validation["mask_atlas_size"] = [mask_atlas_image.get_width(), mask_atlas_image.get_height()]
	validation["get_image_region_size"] = [region_image.get_width(), region_image.get_height()]
	validation["atlas_region_matches_source"] = true
	validation["atlas_margin_matches_source"] = true
	validation["atlas_filter_clip_matches_source"] = true
	validation["nonzero_alpha_pixels_in_region_mask"] = alpha_pixels
	return validation


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	var capture_config: Dictionary = manifest.get("capture_config", {}).duplicate(true)
	capture_config["capture_entry_script"] = ATLAS_MASK_ENTRY_SCRIPT
	capture_config["capture_script_inheritance"] = ATLAS_MASK_SCRIPT_CHAIN.duplicate()
	manifest["capture_config"] = capture_config
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in ATLAS_MASK_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in ATLAS_MASK_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("atlas-mask capture source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["capture_entry_script"] = ATLAS_MASK_ENTRY_SCRIPT
	candidate["capture_script_inheritance"] = ATLAS_MASK_SCRIPT_CHAIN.duplicate()
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate