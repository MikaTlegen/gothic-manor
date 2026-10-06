shader_type spatial;
// Полотно картины. У «следящих» портретов зрачки сдвигаются: область вокруг каждого глаза
// выбирается со смещением gaze (в долях радиуса радужки), края плавно гасят сдвиг.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 eye_l = vec2(-1.0);
uniform vec2 eye_r = vec2(-1.0);
uniform float eye_radius = 0.0;     // радиус радужки в долях ширины полотна; 0 — портрет не следит
uniform vec2 gaze = vec2(0.0);      // -1..1: куда смотрят зрачки (u вправо, v вниз)
uniform sampler2D creep_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D creep_noise : filter_linear, repeat_enable;
uniform float creep = 0.0;          // 0 — полотно как есть, 1 — жуткий двойник (растворение по шуму)

const float ASPECT = 1410.0 / 1024.0;   // высота/ширина текстуры полотна

vec2 warp(vec2 uv, vec2 c) {
	vec2 d = (uv - c) * vec2(1.0, ASPECT);
	float f = 1.0 - smoothstep(0.9, 2.3, length(d) / eye_radius);
	return uv - gaze * eye_radius * 0.6 * f * vec2(1.0, 1.0 / ASPECT);
}

void fragment() {
	vec2 uv = UV;
	if (eye_radius > 0.0) {
		uv = warp(warp(uv, eye_l), eye_r);
	}
	vec3 base = texture(albedo_tex, uv).rgb;
	if (creep > 0.0) {
		float n = texture(creep_noise, UV * 1.7).r;
		float m = smoothstep(n - 0.05, n + 0.05, creep * 1.12);
		base = mix(base, texture(creep_tex, uv).rgb, m);
		float edge = (1.0 - abs(m * 2.0 - 1.0)) * (1.0 - step(0.999, creep));
		EMISSION = vec3(0.55, 0.06, 0.02) * edge * 0.8;   // тлеющая кромка превращения
	}
	ALBEDO = base * tint;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.3;              // мелкое плетение холста под близкой свечой давало муар
	ROUGHNESS = texture(rough_tex, UV).r;
	SPECULAR = 0.45;
}
