shader_type spatial;
// Тёмный силуэт-билборд (поворачивается к камере вокруг вертикали) с растворением по шуму.
// dissolve 0 → фигура целиком, 1 → исчезла. opacity — общая прозрачность (появление).
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D mask_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float dissolve = 0.0;
uniform float opacity = 1.0;
uniform vec3 color : source_color = vec3(0.012, 0.011, 0.012);
uniform vec2 eye_l = vec2(0.47, 0.088);       // бледные точки глаз — фигуру видно и в полной темноте
uniform vec2 eye_r = vec2(0.53, 0.088);
uniform float eye_glow = 1.1;
uniform float tex_color = 0.0;      // 1 — цвет из текстуры (силуэт из фото с дымкой вокруг)
uniform float halo_glow = 0.0;      // свечение дымки: фигуру видно тёмной на сером даже без света

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(mask_tex, UV);
	float a = t.a;
	float n = texture(noise_tex, UV * vec2(1.0, 2.4)).r;
	float keep = smoothstep(0.0, 0.12, n + 0.1 - dissolve * 1.25);
	vec2 asp = vec2(1.0, 2.4);
	float eyes = max(1.0 - smoothstep(0.006, 0.02, length((UV - eye_l) * asp)),
		1.0 - smoothstep(0.006, 0.02, length((UV - eye_r) * asp)));
	ALBEDO = mix(color, t.rgb, tex_color);
	EMISSION = vec3(0.75, 0.78, 0.8) * eyes * eye_glow * keep + t.rgb * halo_glow * tex_color;
	ROUGHNESS = 1.0;
	ALPHA = a * keep * opacity;
}
