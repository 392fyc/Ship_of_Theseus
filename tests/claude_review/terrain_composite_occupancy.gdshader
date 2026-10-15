shader_type canvas_item;
render_mode blend_disabled;

uniform vec3 instance_token_rgb = vec3(0.0, 0.0, 0.0);

// COLOR.a is the original effective source alpha after texture/primitive alpha
// and inherited CanvasItem modulation. A discarded draw leaves the previous
// sufficiently opaque owner untouched in the ordered occupancy pass.
void fragment() {
	if (COLOR.a <= 0.5) {
		discard;
	}
	COLOR = vec4(instance_token_rgb, 1.0);
}
