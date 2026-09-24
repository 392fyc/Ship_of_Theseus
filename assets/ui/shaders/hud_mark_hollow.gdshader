shader_type canvas_item;

uniform vec4 inactive_color : source_color = vec4(0.66, 0.65, 0.69, 1.0);

void fragment() {
	float opacity = texture(TEXTURE, UV).a;
	vec2 reach = TEXTURE_PIXEL_SIZE * 14.0;
	float core = texture(TEXTURE, UV + vec2(reach.x, 0.0)).a;
	core = min(core, texture(TEXTURE, UV - vec2(reach.x, 0.0)).a);
	core = min(core, texture(TEXTURE, UV + vec2(0.0, reach.y)).a);
	core = min(core, texture(TEXTURE, UV - vec2(0.0, reach.y)).a);
	core = min(core, texture(TEXTURE, UV + reach).a);
	core = min(core, texture(TEXTURE, UV - reach).a);
	core = min(core, texture(TEXTURE, UV + vec2(reach.x, -reach.y)).a);
	core = min(core, texture(TEXTURE, UV + vec2(-reach.x, reach.y)).a);
	float outline = opacity * (1.0 - smoothstep(0.15, 0.7, core));
	COLOR = vec4(inactive_color.rgb, outline * inactive_color.a);
}
