shader_type canvas_item;
render_mode unshaded;

uniform vec2 source_size = vec2(964.0, 950.0);
uniform float trunk_u = 0.56818;
uniform float saturation = 0.86;
uniform float contrast = 0.92;
uniform float reveal_alpha = 0.18;
uniform float reveal_strength = 0.0;
uniform int reveal_count = 0;
uniform vec4 reveal_regions[8];
varying vec2 source_position;
varying vec4 instance_tint;

void vertex() {
	source_position = VERTEX;
	instance_tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV) * instance_tint;
	vec2 object_uv = source_position / source_size;
	float canopy = 1.0 - smoothstep(0.66, 0.82, object_uv.y);
	// Keep the lower trunk and the actual root/base fully present.
	float stem_clearance = smoothstep(0.07, 0.14, abs(object_uv.x - trunk_u));
	canopy *= mix(1.0, stem_clearance, smoothstep(0.43, 0.66, object_uv.y));
	float luminance = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 muted = (mix(vec3(luminance), texel.rgb, saturation) - vec3(0.28)) * contrast + vec3(0.28);
	texel.rgb = mix(texel.rgb, muted, 1.0 - smoothstep(0.72, 0.9, object_uv.y));
	vec2 screen_pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	float reveal = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= reveal_count) { break; }
		vec4 window = reveal_regions[i];
		float distance_in_window = length((screen_pixel - window.xy) / max(window.zw, vec2(1.0)));
		reveal = max(reveal, 1.0 - smoothstep(0.62, 1.0, distance_in_window));
	}
	texel.a *= mix(1.0, reveal_alpha, canopy * reveal * reveal_strength);
	COLOR = texel;
}
