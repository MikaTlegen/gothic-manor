shader_type spatial;
// Паутина из фото (рефы 10-12): альфа-маска нитей (Alpha Scissor — без сортировки прозрачности),
// двусторонний рендер, нормали; нити просвечивают на свет (BACKLIGHT), а рядом с пламенем свечи
// вспыхивают тёплым отсветом — сила растёт с приближением.
render_mode cull_disabled, depth_prepass_alpha;

global uniform vec3 candle_pos;
global uniform float candle_energy;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float glow_range = 2.6;      // м: дальше свеча на нити не «бликует»
uniform float glow_strength = 1.6;
uniform float scissor = 0.32;        // порог отсечения нитей

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float near = 1.0 - smoothstep(0.25, glow_range, distance(world_pos, candle_pos));
	near *= near;
	ALBEDO = t.rgb * 0.7;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.5;
	SPECULAR = 0.6;
	BACKLIGHT = glow_color * 0.9;
	EMISSION = glow_color * t.a * near * candle_energy * glow_strength;
	ALPHA = clamp(t.a * (1.1 + 0.6 * near), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ALPHA_ANTIALIASING_EDGE = 0.3;
}
