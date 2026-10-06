extends Node
## Неявная навигация: язычок пламени слегка клонится в сторону верного пути.
## Путь — маршруты автотеста (основной и срезка, оба ведут к «Своей комнате»): берётся ближайший отрезок,
## точка в LOOK_AHEAD метрах дальше по маршруту, и направление на неё переводится в оси руки со свечой.

const AT := preload("res://scripts/autotest.gd")
const LOOK_AHEAD := 3.0
const INTERVAL := 0.25
const STRENGTH := 0.8                ## 1.0 — наклон ~11°

var _routes: Array = []
var _t := 0.0
var _player: Node3D
var _candle: Node3D


func _ready() -> void:
	_player = get_parent() as Node3D
	_candle = _player.get_node_or_null("Head/Camera3D/Hand") as Node3D
	var main: Array = AT.MAIN_A + AT.MAIN_F1 + AT.MAIN_B + AT.MAIN_C + AT.MAIN_F2 + AT.MAIN_D + AT.FINISH
	var shortcut: Array = AT.MAIN_A + AT.MAIN_F1 + AT.MAIN_B + AT.SHORT_A + _spiral() + AT.SHORT_B + AT.FINISH
	_routes = [main, shortcut]


func _spiral() -> Array:
	var pts := []
	for a in range(170, 530, 10):
		var r := deg_to_rad(a)
		pts.append(Vector2(34.0 + 0.72 * cos(r), -14.0 - 0.72 * sin(r)))
	return pts


func _process(delta: float) -> void:
	_t += delta
	if _t < INTERVAL or _candle == null:
		return
	_t = 0.0
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	var target := ahead_point(p)
	var dir := Vector3(target.x - p.x, 0.0, target.y - p.y)
	if dir.length() < 0.2:
		_candle.set("lean", Vector3.ZERO)
		return
	var local := _candle.global_basis.inverse() * dir.normalized()
	_candle.set("lean", Vector3(local.x, 0.0, local.z) * STRENGTH)


## Точка на LOOK_AHEAD м дальше по ближайшему маршруту от позиции p (план x, z).
func ahead_point(p: Vector2) -> Vector2:
	var best := INF
	var best_route: Array = []
	var best_i := 0
	var best_proj := Vector2.ZERO
	for route in _routes:
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var proj := a + ab * t
			var d := p.distance_to(proj)
			if d < best:
				best = d
				best_route = route
				best_i = i
				best_proj = proj
	var left := LOOK_AHEAD
	var cur := best_proj
	for i in range(best_i + 1, best_route.size()):
		var nxt: Vector2 = best_route[i]
		var seg := cur.distance_to(nxt)
		if seg >= left:
			return cur + (nxt - cur).normalized() * left
		left -= seg
		cur = nxt
	return cur
