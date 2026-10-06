shader_type spatial;
// Старое зеркало с живым отражением из SubViewport (см. scripts/mirror.gd).
// Координаты кадра считаются из локальной позиции вершины: кадр камеры-отражения точно
// совпадает с прямоугольником стекла, ось u идёт против локальной X (зеркальный разворот).
render_mode unshaded, fog_disabled;

uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D tarnish_tex : source_color, filter_linear_mipmap;   // mirror_albedo: тёмные пятна амальгамы
uniform vec2 rect_center = vec2(0.0, 1.0);   // центр стекла (локальные X, Y)
uniform vec2 rect_size = vec2(0.9, 1.9);
uniform float live = 0.0;                    // 0 — отражение не обновляется (игрок далеко): тусклое стекло
uniform vec3 dead_color : source_color = vec3(0.015, 0.016, 0.02);

varying vec2 mirror_uv;

void vertex() {
	mirror_uv = vec2(0.5 - (VERTEX.x - rect_center.x) / rect_size.x, 0.5 - (VERTEX.y - rect_center.y) / rect_size.y);
}

void fragment() {
	vec3 tarnish = texture(tarnish_tex, UV).rgb / 0.82;
	vec3 refl = texture(reflection_tex, mirror_uv).rgb * 0.82;
	ALBEDO = mix(dead_color, refl, live) * tarnish;
}
