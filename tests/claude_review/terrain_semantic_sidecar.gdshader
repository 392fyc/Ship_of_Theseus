shader_type canvas_item;
render_mode blend_disabled;

uniform vec3 instance_token_rgb = vec3(0.0, 0.0, 0.0);
uniform float part_code_alpha = 0.0;
uniform bool coverage_output = false;
uniform bool semantic_region_map_enabled = false;
uniform sampler2D semantic_region_map : filter_nearest, repeat_disable;
uniform vec2 semantic_atlas_size = vec2(1.0, 1.0);
uniform vec4 semantic_atlas_region = vec4(0.0, 0.0, 1.0, 1.0);

// COLOR.a samples the original TEXTURE through its original Sprite2D sampler.
// The region map contains category bytes only; it has nearest/no-repeat sampling
// and no mipmaps. Coverage mode never samples the region map.
void fragment() {
	float effective_source_alpha = COLOR.a;
	if (effective_source_alpha <= 0.0) {
		discard;
	}
	if (coverage_output) {
		COLOR = vec4(effective_source_alpha, 0.0, 0.0, 1.0);
	} else {
		float resolved_part_code = part_code_alpha;
		if (semantic_region_map_enabled) {
			vec2 atlas_pixel = UV * semantic_atlas_size;
			vec2 region_local_uv = (atlas_pixel - semantic_atlas_region.xy) / semantic_atlas_region.zw;
			if (region_local_uv.x >= 0.0 && region_local_uv.y >= 0.0
					&& region_local_uv.x < 1.0 && region_local_uv.y < 1.0) {
				float sampled_code = texture(semantic_region_map, region_local_uv).r;
				resolved_part_code = sampled_code > 0.0 ? sampled_code : (255.0 / 255.0);
			} else {
				resolved_part_code = 255.0 / 255.0;
			}
		}
		COLOR = vec4(instance_token_rgb, resolved_part_code);
	}
}
