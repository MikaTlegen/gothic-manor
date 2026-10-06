shader_type spatial;
// Свинцовый переплёт окна: жилы непрозрачны, само стекло почти прозрачно — сквозь него виден ночной лес.
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float lead = 1.0 - smoothstep(0.06, 0.14, dot(t.rgb, vec3(0.333)));
	ALBEDO = mix(t.rgb * 0.35, vec3(0.03), lead);
	ALPHA = max(lead, 0.09 + 0.15 * clamp(t.a - 0.32, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.6, lead);
	SPECULAR = 0.7;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
