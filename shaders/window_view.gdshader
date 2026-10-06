shader_type spatial;
// Плоскость диорамы за окном (фон-картина или слой силуэтов): без освещения и тумана,
// альфа-отсечение для силуэтов, «воздушная перспектива» — подмешивание дымки к дальним слоям.
render_mode unshaded, fog_disabled, cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float brightness = 1.0;
uniform vec3 haze_color : source_color = vec3(0.06, 0.075, 0.11);
uniform float haze = 0.0;

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = mix(t.rgb * brightness, haze_color, haze);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
