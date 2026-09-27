shader_type canvas_item;
render_mode unshaded;

uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform sampler2D pair_styles : filter_nearest, repeat_disable;
uniform vec2 paving_bank;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform sampler2D meadow : source_color, filter_linear, repeat_enable;
uniform sampler2D moss : source_color, filter_linear, repeat_enable;
uniform sampler2D paving : source_color, filter_linear, repeat_enable;
uniform sampler2D rock : source_color, filter_linear, repeat_enable;
uniform bool relief = false;
varying vec4 vertex_shade;

void vertex() { vertex_shade = COLOR; }

vec3 terrain_at(vec2 at) {
	return floor(texture(terrain_map, (at - map_origin + vec2(0.5)) / map_size).rgb * 255.0 + vec3(0.5));
}
float hash_value(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float value_noise(vec2 p) {
	vec2 at = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_value(at), hash_value(at + vec2(1.0, 0.0)), f.x), mix(hash_value(at + vec2(0.0, 1.0)), hash_value(at + vec2(1.0)), f.x), f.y);
}
float noise_field(vec2 p) {
	return (value_noise(p) * 0.67 + value_noise(p * 2.13 + vec2(19.7, 5.1)) * 0.33) * 2.0 - 1.0;
}
float crack_distance(vec2 p) {
	vec2 base = floor(p);
	float first = 10.0;
	float second = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			vec2 seed = cell + vec2(hash_value(cell), hash_value(cell + vec2(23.2, 7.5)));
			float d = length(seed - p);
			if (d < first) { second = first; first = d; }
			else { second = min(second, d); }
		}
	}
	return second - first;
}
bool water(float t) { return t == 5.0 || t == 6.0; }
vec3 transition_style(float a, float b) {
	return texture(pair_styles, (vec2(a, b) + vec2(0.5)) / 9.0).rgb;
}

vec3 surface(vec3 code, vec2 p) {
	vec3 grass = texture(meadow, p / 8.0).rgb * vec3(0.761, 0.792, 0.690);
	if (code.y > 0.5) { return texture(paving, p / 8.0).rgb * vec3(0.816, 0.812, 0.737); }
	float t = code.x;
	if (t == 1.0) { return texture(moss, p / 8.0).rgb * vec3(0.576, 0.620, 0.455); }
	if (t == 2.0 || t == 3.0) {
		vec3 stone_color = texture(rock, p / 5.5).rgb * (t == 3.0 ? vec3(0.93, 0.93, 0.89) : vec3(0.91, 0.91, 0.78));
		return code.z > 0.5 ? mix(stone_color, texture(moss, p / 5.0).rgb * vec3(0.62, 0.75, 0.53), smoothstep(-0.4, 0.8, noise_field(p)) * 0.70) : stone_color;
	}
	if (t == 4.0) { return mix(grass, texture(paving, p / 8.0).rgb * vec3(0.72, 0.71, 0.62), 0.46); }
	if (t == 8.0) {
		float pool = smoothstep(-0.08, 0.26, noise_field(p * 1.75));
		return mix(texture(moss, p / 6.0).rgb * vec3(0.48, 0.55, 0.35), vec3(0.055, 0.13, 0.11), pool * 0.82);
	}
	if (t == 7.0) {
		float vein = 1.0 - smoothstep(0.018, 0.10, crack_distance(p * 1.9 + noise_field(p * 2.4) * 0.16));
		return mix(texture(rock, p / 4.0).rgb * vec3(0.31, 0.27, 0.25), vec3(0.83, 0.25, 0.055), vein * 0.87);
	}
	return grass;
}

void fragment() {
	vec2 p = UV;
	// 所有格子、外边与转角使用同一世界坐标；没有按格随机的边缘贴花。
	vec2 warped = p + vec2(noise_field(p * 0.72), noise_field(p.yx * 0.69)) * 0.055;
	vec2 base = floor(warped);
	vec2 f = smoothstep(vec2(0.16), vec2(0.84), fract(warped));
	vec3 land_sum = vec3(0.0);
	float land_weight = 0.0;
	float water_weight = 0.0;
	float deep_weight = 0.0;
	vec3 shallow_style = vec3(0.0);
	vec3 deep_style = vec3(0.0);
	float scorch = 0.0;
	float lava_weight = 0.0;
	float moss_weight = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec3 code = terrain_at(base + vec2(float(x), float(y)));
			float weight = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
			if (water(code.x)) {
				water_weight += weight;
				if (code.x == 6.0) { deep_weight += weight; }
			}
			else {
				land_sum += surface(code, p) * weight;
				land_weight += weight;
				vec3 shallow = transition_style(code.x, 5.0);
				vec3 deep = transition_style(code.x, 6.0);
				if (code.y > 0.5) { shallow.xy = paving_bank; deep.xy = paving_bank; }
				shallow_style += shallow * weight;
				deep_style += deep * weight;
				scorch += transition_style(code.x, 7.0).z * weight;
				if (code.x == 7.0) { lava_weight += weight; }
				if (code.x == 3.0 && code.z > 0.5) { moss_weight += weight; }
			}
		}
	}
	vec3 bank = mix(shallow_style, deep_style, deep_weight / max(water_weight, 0.0001)) / max(land_weight, 0.0001);
	float half_width = clamp(bank.x * 0.5, 0.02, 0.49);
	float shore = smoothstep(0.5 - half_width, 0.5 + half_width, water_weight);
	vec3 land = land_sum / max(land_weight, 0.0001);
	// 水岸只出现湿暗，熔岩岸先出现冷却焦土。不存在高亮轮廓。
	land *= 1.0 - bank.y * smoothstep(0.01, 0.45, water_weight);
	land *= 1.0 - (scorch / max(land_weight, 0.0001)) * sin(clamp(lava_weight, 0.0, 1.0) * 3.14159265);
	if (relief) {
		// 凸起的坡面使用岩石；沼泽水洼和熔岩保持水平，不能被贴到山壁上。
		vec3 hillside = texture(rock, p / 5.5).rgb * vec3(0.93, 0.93, 0.86);
		hillside = mix(hillside, texture(moss, p / 5.0).rgb * vec3(0.62, 0.75, 0.53), moss_weight * 0.75);
		COLOR = vec4(hillside * vertex_shade.rgb, vertex_shade.a);
	} else {
		COLOR = vec4(land, 1.0 - shore);
	}
}
