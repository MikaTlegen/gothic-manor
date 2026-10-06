extends SceneTree
## Сборка уровня «Догорающая свеча» из модульных ассетов (без редактора):
##   Godot --headless --path . --script res://tools/build_level.gd
## Результат: res://scenes/level.tscn (перезаписывается целиком).
##
## Планировка задана вручную на сетке 2 м: клетка (i, j) занимает x 2i..2i+2, z 2j..2j+2; север — -Z.
## Уровни пола: склеп/нижний зал -1.08, первый этаж 0, бельэтаж +2.16 (6 и 12 ступеней по 0.18 м).
## Стены — лицом внутрь комнаты на линии сетки; проходы и двери — по оси ребра.

const CELL := 2.0
const WALL_H := 3.2
const LOW := -1.08
const UP := 2.16
const MODELS := "res://assets/gothic_manor/models"
const OUT := "res://scenes/level.tscn"
const TWEAK := preload("res://scripts/prop_tweak.gd")
const HORROR := preload("res://tools/build_horror.gd")
const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const OFF := {"lights_off": true}
const CHARRED := Color(0.25, 0.22, 0.2)
const CHARACTER := "Character_Gentleman"   ## сцена тела игрока (задел под выбор персонажа)

var paths := {}
var cache := {}
var rooms := {}
var cell_rooms := {}
var features := {}
var walls := []
var groups := {}
var level: Node3D
var rng := RandomNumberGenerator.new()
var count := 0


func _initialize() -> void:
	rng.seed = 1337
	_index_models()
	level = Node3D.new()
	level.name = "Level"
	level.set_script(load("res://scripts/game.gd"))
	var arch := _group("Architecture", level)
	for g in ["Floors", "Walls", "Ceilings"]:
		_group(g, arch)
	for g in ["Props", "Lights", "Gameplay"]:
		_group(g, level)
	_layout()
	_build_walls()
	_build_features()
	_build_floors_ceilings()
	_decor_walls()
	_props()
	_stair_rails()
	_gameplay()
	_player()
	_environment()
	_ui()
	HORROR.new(self).build()
	var at := Node.new()
	at.name = "Autotest"
	at.set_script(load("res://scripts/autotest.gd"))
	_own(level, at)
	var ps := PackedScene.new()
	var err := ps.pack(level)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("[BUILD] Экземпляров ассетов: %d, комнат: %d, сохранение: %s" % [count, rooms.size(), error_string(err)])
	level.free()
	quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
# Планировка
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Первый этаж: коридор прислуги (старт) → галерея портретов → зал «Плачущей девы»
	room("S", [Rect2i(20, 27, 1, 9), Rect2i(13, 27, 7, 1), Rect2i(12, 22, 1, 6)], 0.0, 2.6, {"floor": "wood"})
	room("G", [Rect2i(11, 14, 2, 8)], 0.0, 3.6, {"wall": ["Wall_Panel", "Wall_Niche"], "floor": "checker"})
	room("F1", [Rect2i(10, 10, 4, 4)], 0.0, 4.0, {"wall": "Wall_Panel", "floor": "checker"})
	room("D1a", [Rect2i(7, 11, 3, 1)], 0.0, 3.0, {"wall": "Wall_Panel", "floor": "wood"})
	room("D1", [Rect2i(3, 9, 4, 5)], 0.0, 3.6, {"wall": "Wall_Panel", "floor": "wood"})
	# Колоннада со спуском: терраса на 0, нижний ярус на -1.08
	var terrace := {}
	for i in range(10, 14):
		for j in range(7, 10):
			terrace[Vector2i(i, j)] = 0.0
	room("C", [Rect2i(10, 4, 4, 6), Rect2i(11, 3, 2, 1)], LOW, 2.42, {"cell_floor": terrace})
	# Нижний ярус: зал упавшей люстры, лаз к винтовой лестнице, склеп, «Ангел», часовня, парадная лестница
	room("H", [Rect2i(9, -3, 6, 6)], LOW, 4.92, {"floor": "checker"})
	room("P", [Rect2i(14, -7, 1, 4), Rect2i(15, -7, 1, 1)], LOW, 1.32)
	room("SP", [Rect2i(16, -8, 2, 2)], LOW, 5.3, {"extra_floors": [[Vector2i(16, -7), UP, "Floor_Wood"]]})
	room("Q", [Rect2i(15, -8, 1, 2)], UP, 5.36, {"wall": "Wall_Panel", "floor": "wood"})
	room("K", [Rect2i(1, -1, 8, 2), Rect2i(1, -13, 2, 12)], LOW, 2.12,
		{"wall": ["Wall_Stone", "Wall_Niche"], "ceil": "vault"})
	room("F2", [Rect2i(0, -17, 4, 4)], LOW, 3.92, {"ceil": "vault"})
	room("D2a", [Rect2i(-3, -16, 3, 1)], LOW, 2.12)
	room("D2", [Rect2i(-7, -19, 4, 6)], LOW, 3.92, {"wall": ["Wall_Stone", "Wall_Niche"], "ceil": "vault"})
	room("ST", [Rect2i(4, -16, 5, 1), Rect2i(8, -17, 1, 1)], LOW, 5.3,
		{"cell_floor": {Vector2i(8, -16): 1.08, Vector2i(8, -17): 1.08}})
	# Бельэтаж: галерея с окнами → «Два зеркала» → ухоженный коридор → «Своя комната»
	var outer := {}
	for j in range(-28, -17):
		outer["x:8:%d" % j] = "Wall_Window" if j % 2 == 0 else "Wall_Stone"
	for i in range(8, 15):
		outer["z:%d:-28" % i] = "Wall_Window" if i % 2 == 0 else "Wall_Stone"
	room("U", [Rect2i(8, -27, 1, 10), Rect2i(8, -28, 7, 1), Rect2i(14, -27, 1, 15)], UP, 5.36,
		{"wall": "Wall_Panel", "floor": "wood", "overrides": outer})
	room("F3", [Rect2i(12, -12, 4, 4)], UP, 5.36, {"wall": "Wall_Panel", "floor": "wood"})
	room("R", [Rect2i(16, -11, 8, 2)], UP, 6.56, {"wall": "Wall_Panel_Clean", "floor": "wood"})
	room("SR", [Rect2i(24, -12, 4, 4)], UP, 6.56, {"wall": "Wall_Panel_Clean", "floor": "wood"})

	# Проходы основного маршрута
	for pair in [["S", "G"], ["G", "F1"], ["F1", "D1a"], ["D1a", "D1"], ["F1", "C"], ["C", "H"], ["H", "K"],
			["K", "F2"], ["F2", "D2a"], ["D2a", "D2"], ["F2", "ST"], ["ST", "U"], ["U", "F3"], ["Q", "F3"],
			["F3", "R"]]:
		link(pair[0], pair[1])
	# Срезка: пролом в зале → лаз → винтовая лестница; вход снизу и выход сверху в одном ребре
	link("H", "P", "breach")
	edge_feature(Vector2i(15, -7), Vector2i(1, 0), "arch", LOW, ["P", "SP"], {"header": false})
	edge_feature(Vector2i(15, -7), Vector2i(1, 0), "arch", UP, ["Q", "SP"], {"filler": false, "header": false})
	# Естественные границы: заколоченные проходы, запертая дверь
	edge_feature(Vector2i(13, 11), Vector2i(1, 0), "boarded", 0.0, ["F1"])
	edge_feature(Vector2i(14, 0), Vector2i(1, 0), "boarded", LOW, ["H"])
	edge_feature(Vector2i(12, -10), Vector2i(-1, 0), "boarded", UP, ["F3"])
	edge_feature(Vector2i(21, -11), Vector2i(0, -1), "boarded", UP, ["R"])
	edge_feature(Vector2i(8, -22), Vector2i(1, 0), "boarded", UP, ["U"])
	for i in [10, 11]:
		edge_feature(Vector2i(i, -3), Vector2i(0, -1), "covered", LOW, ["H"], {"module_h": WALL_H})
	for j in [-11, -10]:
		edge_feature(Vector2i(23, j), Vector2i(1, 0), "covered", UP, ["R", "SR"], {"module_h": 4.4})


func room(id: String, rects: Array, floor_y: float, ceil_y: float, opts := {}) -> void:
	var r := {
		"id": id, "rects": rects, "fy": floor_y, "ceil": ceil_y,
		"wall": opts.get("wall", "Wall_Stone"), "fkind": opts.get("floor", "stone"),
		"ckind": opts.get("ceil", "beams"), "cell_floor": opts.get("cell_floor", {}),
		"extra_floors": opts.get("extra_floors", []), "overrides": opts.get("overrides", {}), "cells": {},
	}
	var lo := floor_y
	for c in r.cell_floor:
		lo = minf(lo, r.cell_floor[c])
	r["min"] = lo
	for rc in rects:
		for i in range(rc.position.x, rc.end.x):
			for j in range(rc.position.y, rc.end.y):
				var c := Vector2i(i, j)
				r.cells[c] = true
				if not cell_rooms.has(c):
					cell_rooms[c] = []
				cell_rooms[c].append(id)
	rooms[id] = r


func cfloor(r: Dictionary, c: Vector2i) -> float:
	return r.cell_floor.get(c, r.fy)


func overlap(a: Dictionary, b: Dictionary) -> bool:
	return a.min < b.ceil - 0.01 and b.min < a.ceil - 0.01


func link(a: String, b: String, kind := "arch") -> void:
	var ra: Dictionary = rooms[a]
	var rb: Dictionary = rooms[b]
	for c in ra.cells:
		for d in DIRS:
			var n: Vector2i = c + d
			if rb.cells.has(n) and overlap(ra, rb):
				edge_feature(c, d, kind, maxf(cfloor(ra, c), cfloor(rb, n)), [a, b])


## Особое ребро: проход/граница. Первая комната в room_ids — та, в клетку c которой смотрит лицо модуля.
func edge_feature(c: Vector2i, d: Vector2i, kind: String, y: float, room_ids: Array, opts := {}) -> void:
	var key := ekey(c, d)
	if not features.has(key):
		features[key] = []
	var f := {"kind": kind, "c": c, "d": d, "y": y, "rooms": room_ids}
	f.merge(opts)
	features[key].append(f)


func ekey(c: Vector2i, d: Vector2i) -> String:
	if d == Vector2i(0, -1):
		return "z:%d:%d" % [c.x, c.y]
	if d == Vector2i(0, 1):
		return "z:%d:%d" % [c.x, c.y + 1]
	if d == Vector2i(-1, 0):
		return "x:%d:%d" % [c.x, c.y]
	return "x:%d:%d" % [c.x + 1, c.y]


func epos(c: Vector2i, d: Vector2i) -> Vector3:
	return Vector3(c.x * CELL + 1.0 + d.x, 0, c.y * CELL + 1.0 + d.y)


## Поворот модуля так, чтобы его лицо (+Z) смотрело внутрь клетки c от ребра в сторону d.
func eyaw(d: Vector2i) -> float:
	if d == Vector2i(0, -1):
		return 0.0
	if d == Vector2i(0, 1):
		return PI
	if d == Vector2i(-1, 0):
		return PI / 2
	return -PI / 2


func inward(d: Vector2i) -> Vector3:
	return Vector3(-d.x, 0, -d.y)


# ---------------------------------------------------------------------------
# Геометрия: стены, проходы, полы, потолки
# ---------------------------------------------------------------------------

func _build_walls() -> void:
	for id in rooms:
		var r: Dictionary = rooms[id]
		var idx := 0
		for c in r.cells:
			for d in DIRS:
				var key := ekey(c, d)
				var n: Vector2i = c + d
				if features.has(key) or r.cells.has(n):
					continue
				var offset := 0.0
				for oid in cell_rooms.get(n, []):
					if oid != id and overlap(r, rooms[oid]):
						offset = 0.16       # соседняя комната вплотную: две стены спиной к спине
				var style := _style(r, c, d, key)
				var y: float = r.min
				var row := 0
				while y < r.ceil - 0.05:
					var s := style if row == 0 else "Wall_Stone"
					var node := _wall_piece(s, c, d, y, offset)
					walls.append({"room": id, "style": s, "xf": node.transform, "row": row, "idx": idx})
					y += WALL_H
					row += 1
				idx += 1


func _style(r: Dictionary, c: Vector2i, d: Vector2i, key: String) -> String:
	if r.overrides.has(key):
		return r.overrides[key]
	if r.wall is Array:
		var k := c.y if d.y == 0 else c.x
		return r.wall[posmod(k, r.wall.size())]
	return r.wall


func _wall_piece(style: String, c: Vector2i, d: Vector2i, y: float, offset: float) -> Node3D:
	var pos := epos(c, d) + inward(d) * offset + Vector3(0, y, 0)
	return _place("Walls", style, _xf(pos, eyaw(d)))


func _build_features() -> void:
	for key in features:
		for f in features[key]:
			var c: Vector2i = f.c
			var d: Vector2i = f.d
			var xf := _xf(epos(c, d) + Vector3(0, f.y, 0), eyaw(d))
			match f.kind:
				"arch":
					_place("Walls", "Wall_Arch", xf)
				"boarded":
					_place("Walls", "Wall_Arch", xf)
					_place("Props", "Boarded_Opening", xf)
				"breach":
					_place("Walls", "Wall_Breach", xf)
			var rs: Array = f.rooms
			var mh: float = f.get("module_h", WALL_H)
			# Заполнение под проходом, если полы по разные стороны на разной высоте
			if f.get("filler", true) and rs.size() == 2:
				var li := 0 if rooms[rs[0]].min <= rooms[rs[1]].min else 1
				var lo: Dictionary = rooms[rs[li]]
				if lo.min < f.y - 0.05:
					var cell: Vector2i = c if li == 0 else c + d
					var dd: Vector2i = d if li == 0 else -d
					var yy: float = f.y - WALL_H
					while yy + WALL_H > lo.min + 0.05:
						_wall_piece("Wall_Stone", cell, dd, yy, 0.0)
						yy -= WALL_H
			# Надстройка над проходом до потолка более высокой комнаты
			if f.get("header", true):
				var hi := 0
				for k in rs.size():
					if rooms[rs[k]].ceil > rooms[rs[hi]].ceil:
						hi = k
				var top: float = f.y + mh
				if rooms[rs[hi]].ceil > top + 0.05:
					var cell: Vector2i = c if hi == 0 else c + d
					var dd: Vector2i = d if hi == 0 else -d
					var yy := top
					while yy < rooms[rs[hi]].ceil - 0.05:
						_wall_piece("Wall_Stone", cell, dd, yy, 0.15)
						yy += WALL_H


func _build_floors_ceilings() -> void:
	for id in rooms:
		var r: Dictionary = rooms[id]
		for rc in r.rects:
			var along_x: bool = rc.size.x > rc.size.y
			if r.fkind == "checker":
				for i in range(rc.position.x, rc.end.x, 2):
					for j in range(rc.position.y, rc.end.y, 2):
						var pos := Vector3(i * CELL + 2, r.fy, j * CELL + 2)
						_place("Floors", "Floor_Checker", _xf(pos, rng.randi_range(0, 3) * PI / 2))
			else:
				for i in range(rc.position.x, rc.end.x):
					for j in range(rc.position.y, rc.end.y):
						var pos := Vector3(i * CELL + 1, cfloor(r, Vector2i(i, j)), j * CELL + 1)
						if r.fkind == "wood":
							_place("Floors", "Floor_Wood", _xf(pos, rng.randi_range(0, 1) * PI + (PI / 2 if along_x else 0.0)))
						else:
							_place("Floors", "Floor_Stone", _xf(pos, rng.randi_range(0, 3) * PI / 2))
			if r.ckind == "vault":
				for i in range(rc.position.x, rc.end.x, 2):
					for j in range(rc.position.y, rc.end.y, 2):
						_place("Ceilings", "Ceiling_Vault", _xf(Vector3(i * CELL + 2, r.ceil, j * CELL + 2), 0.0))
			else:
				for i in range(rc.position.x, rc.end.x):
					for j in range(rc.position.y, rc.end.y):
						var pos := Vector3(i * CELL + 1, r.ceil, j * CELL + 1)
						_place("Ceilings", "Ceiling_Beams", _xf(pos, PI / 2 if along_x else 0.0))
		for e in r.extra_floors:
			_place("Floors", e[2], _xf(Vector3(e[0].x * CELL + 1, e[1], e[0].y * CELL + 1), 0.0))


# ---------------------------------------------------------------------------
# Декор: по стенам (портреты, ниши, бра, надгробия) и расставленный вручную
# ---------------------------------------------------------------------------

func _decor_walls() -> void:
	var sarcophagus_z := -14.0          # у саркофага в склепе оставить проход
	for w in walls:
		if w.row != 0:
			continue
		var s: String = w.style
		var k: int = w.idx
		var xf: Transform3D = w.xf
		match w.room:
			"G":
				if s == "Wall_Panel":
					if absf(xf.origin.x - 22.0) < 0.1 and absf(xf.origin.z - 37.0) < 0.1:
						_on(xf, "Mirror_Tall", Vector3(0, 0.05, 0.03))
					else:
						_on(xf, "Portrait_Frame", Vector3(0, 1.9, 0.03))
				elif s == "Wall_Niche":
					_on(xf, "Candle", Vector3(rng.randf_range(-0.2, 0.2), 0.555, -0.3))
			"F1":
				if s == "Wall_Panel" and k % 2 == 0:
					_on(xf, "Portrait_Frame", Vector3(0, 1.95, 0.03))
			"D1", "D1a":
				if s == "Wall_Panel" and k % 2 == 0:
					_on(xf, "Portrait_Frame", Vector3(0, 1.9, 0.03), 0.0, {"tint": CHARRED})
			"U":
				if s == "Wall_Panel":
					if k % 3 == 0:
						_on(xf, "Portrait_Frame", Vector3(0, 1.95, 0.03))
					elif k % 3 == 1:
						_on(xf, "WallSconce_Lit", Vector3(0, 1.75, 0.03), 0.0, OFF)
			"F3":
				if s == "Wall_Panel" and k % 2 == 0:
					_on(xf, "WallSconce_Double_Lit", Vector3(0, 1.8, 0.03), 0.0, OFF)
			"R":
				if s == "Wall_Panel_Clean":
					if k % 2 == 0:
						_on(xf, "WallSconce_Double_Lit", Vector3(0, 1.8, 0.03), 0.0, OFF)
					else:
						_on(xf, "Portrait_Frame", Vector3(0, 1.95, 0.03))
			"K", "D2":
				if s == "Wall_Niche":
					_on(xf, "Candle_Cluster_Lit", Vector3(0, 0.555, -0.3), rng.randf_range(0, TAU), OFF)
				elif s == "Wall_Stone" and rng.randf() < 0.6:
					var p := xf * Vector3(0, 0, 0.5)
					if w.room == "D2" or (p.x < 7.0 and absf(p.z - sarcophagus_z) > 2.8):
						var g: String = ["Gravestone_A", "Gravestone_B", "Gravestone_C"][rng.randi_range(0, 2)]
						_on(xf, g, Vector3(rng.randf_range(-0.3, 0.3), 0, 0.5), deg_to_rad(rng.randf_range(-12, 12)))


func _props() -> void:
	# --- Старт: тесный коридор прислуги, за спиной обвал ---
	prop("Rubble_Pile", Vector3(41, 0, 71), 180)
	prop("Ceiling_Collapse", Vector3(41, 2.6, 71), 0)
	prop("Candle", Vector3(40.45, 0, 66.3), 0)
	prop("Chair_HighBack", Vector3(41.5, 0.26, 63), 95, {}, Vector3(0, 0, 90))
	prop("Debris_Scatter", Vector3(41, 0, 60), 37)
	prop("Cobweb_Sheet", Vector3(41, 2.55, 57.5), 0)
	prop("Cobweb_Corner", Vector3(40, 2.6, 54), -90)
	prop("Debris_Scatter", Vector3(33, 0, 55), 110)
	prop("Portrait_Frame", Vector3(30, 0.52, 54.28), 0, {"tint": Color(0.6, 0.55, 0.5)}, Vector3(-12, 0, 4))
	prop("Cobweb_Sheet", Vector3(28, 2.55, 55), 90)
	prop("Candle", Vector3(25.6, 0, 50.3), 0)
	prop("Chair_HighBack", Vector3(24.6, 0, 47.2), 160)
	prop("Cobweb_Corner", Vector3(24, 2.6, 44), -90)
	# --- Галерея портретов: старая дорожка ---
	for z in [41.0, 36.2, 31.4]:
		prop("Carpet_Runner", Vector3(24, 0, z), 0)
	# --- F1: ангел Leubner (скан) с поднятой рукой — первый ориентир на развилке ---
	prop("Statue_Angel_Leubner", Vector3(24, 0, 24), 0)
	prop("Chair_HighBack", Vector3(21.6, 0, 26.2), face(Vector3(21.6, 0, 26.2), Vector3(24, 0, 24)))
	prop("Chair_HighBack", Vector3(26.6, 0.26, 21.7), 200, {}, Vector3(0, 0, 90))
	prop("Candelabra_Lit", Vector3(23.1, 0, 25.3), 20, OFF)
	prop("Debris_Scatter", Vector3(26.5, 0, 21.4), 15)
	# --- Тупик 1: сгоревшая столовая ---
	prop("Cobweb_Sheet", Vector3(17, 2.5, 23), 90)
	prop("Sideboard_Burned", Vector3(10, 0, 18.31), 0)
	prop("Candle_Cluster_Lit", Vector3(10.3, 0.86, 18.35), 0, OFF)
	prop("Sideboard_Burned", Vector3(11, 0, 27.69), 180)
	prop("Chair_Burned", Vector3(11.5, 0.26, 21.2), 80, {}, Vector3(0, 0, 90))
	prop("Chair_Burned", Vector3(9.2, 0, 25.6), 200)
	prop("Chair_Burned", Vector3(12.4, 0.26, 25.1), 10, {}, Vector3(0, 0, 90))
	prop("Chair_Burned", Vector3(8.6, 0, 20.4), 30)
	prop("Chair_Burned", Vector3(12.2, 0, 19.8), -60)
	prop("Chandelier_Lit", Vector3(9.6, 0.75, 20.9), 0, {"lights_off": true, "tint": CHARRED}, Vector3(28, 0, -14))
	prop("Rubble_Pile", Vector3(7, 0, 23), 90)
	prop("Ceiling_Collapse", Vector3(7, 3.6, 23), 0)
	for p in [Vector3(9, 0, 20), Vector3(12, 0, 26), Vector3(8.6, 0, 26.2), Vector3(13, 0, 22.4)]:
		prop("Debris_Scatter", p, rng.randf_range(0, 360))
	# --- Колоннада: спуск на 6 ступеней, колонны нижнего яруса, подпорные стенки с перилами ---
	prop("Stairs_Short", Vector3(24, LOW, 12.2), 180)
	for x in [21.0, 27.0]:
		prop("Wall_Low", Vector3(x, LOW, 14), 180)
		prop("Railing_Segment", Vector3(x, 0, 14.15), 0)
	for p in [Vector3(22, LOW, 9), Vector3(26, LOW, 9), Vector3(22, LOW, 11.4), Vector3(26, LOW, 11.4)]:
		prop("Column_Gothic", p, 0)
	prop("Debris_Scatter", Vector3(20.9, LOW, 9.5), 60)
	prop("Cobweb_Corner", Vector3(20, 2.42, 8), -90)
	# --- Зал упавшей люстры: запертая дверь, пролом-лаз, заколоченный проход ---
	prop("Door_Locked_Massive", Vector3(22, LOW, -6), 0)
	prop("Chandelier_Lit", Vector3(24, LOW + 0.55, 0.2), 25, OFF, Vector3(78, 0, 8))
	for p in [Vector3(23, LOW, -1.2), Vector3(25.6, LOW, 1.6), Vector3(21.2, LOW, 2.2), Vector3(27.4, LOW, -3.8)]:
		prop("Debris_Scatter", p, rng.randf_range(0, 360))
	prop("Chair_HighBack", Vector3(20.2, LOW + 0.26, -2.6), 70, {}, Vector3(0, 0, 90))
	prop("Chair_HighBack", Vector3(27.8, LOW, 3.4), -140)
	prop("Mirror_Tall", Vector3(19.5, LOW + 0.05, 5.97), 180)
	prop("Sideboard", Vector3(26.4, LOW, -5.69), 0, {"tint": Color(0.7, 0.7, 0.7)})
	var chalk := Label3D.new()
	chalk.name = "ChalkMark"
	chalk.text = "→"
	chalk.font_size = 160
	chalk.pixel_size = 0.004
	chalk.modulate = Color(0.85, 0.83, 0.78, 0.55)
	chalk.shaded = true
	chalk.double_sided = false
	chalk.position = Vector3(27.6, LOW + 1.35, -5.96)
	_own(groups.Props, chalk)
	prop("Cobweb_Sheet", Vector3(29, 1.3, -9), 0)
	prop("Cobweb_Sheet", Vector3(29, 1.3, -12.5), 0)
	prop("Debris_Scatter", Vector3(29, LOW, -10.8), 90)
	# --- Винтовая лестница (срезка) ---
	prop("Stairs_Spiral", Vector3(34, LOW, -14), 185)
	# --- Склеп ---
	prop("Sarcophagus", Vector3(12, LOW, 0), 0)
	prop("Sarcophagus", Vector3(7.2, LOW, -0.1), 180)
	prop("Sarcophagus", Vector3(4, LOW, -14), 90)
	# --- «Ангел со сломанным крылом»: рука указывает на восток, к лестнице наверх ---
	prop("Statue_Angel_Miller", Vector3(4, LOW, -30), 0)       # сидящий ангел (скан Miller): лицом ко входу из склепа, венок — к лестнице
	prop("Candle_Cluster_Lit", Vector3(3.2, LOW, -29.2), 0, OFF)
	prop("Gravestone_C", Vector3(1.0, LOW, -33.1), 30)
	prop("Gravestone_A", Vector3(7.0, LOW, -33.2), -20)
	prop("Debris_Scatter", Vector3(1.4, LOW, -27.4), 45)
	# --- Тупик 2: фамильная часовня ---
	prop("Cobweb_Sheet", Vector3(-2, 1.9, -31), 90)
	for gx in [-12.2, -10.0]:
		for gz in [-36.0, -34.0, -28.0]:
			var g: String = ["Gravestone_A", "Gravestone_B", "Gravestone_C"][rng.randi_range(0, 2)]
			prop(g, Vector3(gx + rng.randf_range(-0.2, 0.2), LOW, gz), 90 + rng.randf_range(-15, 15))
	prop("Sarcophagus", Vector3(-10.5, LOW, -31), 90)
	prop("Sideboard", Vector3(-7.6, LOW, -37.69), 0, {"tint": Color(0.6, 0.6, 0.6)})
	prop("Candelabra_Lit", Vector3(-7.6, LOW + 0.86, -37.7), 0, OFF)
	prop("Candle_Cluster_Lit", Vector3(-8.2, LOW + 0.86, -37.6), 0, OFF)
	prop("Rubble_Pile", Vector3(-13, LOW, -27.2), 90)
	prop("Debris_Scatter", Vector3(-11.5, LOW, -26.8), 20)
	# --- Парадная лестница наверх ---
	prop("Stairs_Grand", Vector3(11.4, LOW, -31), -90)
	prop("Stairs_Short_Narrow", Vector3(17, 1.08, -32.2), 0)
	# --- Бельэтаж ---
	for z in [-30.0, -35.0]:
		prop("Carpet_Runner", Vector3(29, UP, z), 0)
	prop("Mirror_Tall", Vector3(25, UP + 0.05, -23.97), 0)
	prop("Mirror_Baroque", Vector3(25, UP + 0.05, -16.03), 180)   # живое зеркало в резной раме (реф 7)
	prop("Rug_Large", Vector3(28, UP, -20), 90)
	prop("Sideboard", Vector3(24.31, UP, -22.6), 90)
	prop("Candelabra_Lit", Vector3(24.31, UP + 0.86, -22.6), 90, OFF)
	# --- Ухоженный коридор: дорожки, погасшие канделябры, табличка у двери ---
	for x in [35.4, 40.2, 45.0]:
		prop("Carpet_Runner", Vector3(x, UP, -20), 90)
	prop("Sideboard", Vector3(36.5, UP, -21.69), 0)
	prop("Candelabra_Lit", Vector3(36.5, UP + 0.86, -21.69), 0, OFF)
	prop("Sideboard", Vector3(40, UP, -18.31), 180)
	prop("Candelabra_Lit", Vector3(40, UP + 0.86, -18.31), 180, OFF)
	prop("Sign_Plaque", Vector3(47.84, UP + 1.55, -21.62), -90)
	# --- «Своя комната» ---
	prop("Fireplace", Vector3(56, UP, -20), -90, {"light_energy": 3.0, "light_range": 9.0, "light_shadows": true})
	var clock := prop("Clock_Grandfather", Vector3(52.6, UP, -23.78), 0)
	clock.set_script(load("res://scripts/pendulum.gd"))
	prop("Rug_Large", Vector3(52.2, UP, -20), 90)
	prop("Chair_HighBack", Vector3(53.4, UP, -18.6), 115)
	prop("Chair_HighBack", Vector3(53.4, UP, -21.4), 65)
	prop("Sideboard", Vector3(51, UP, -16.31), 180)
	prop("Candelabra_Lit", Vector3(51, UP + 0.86, -16.31), 180, {"light_energy": 1.4, "light_range": 6.0, "light_shadows": true})
	prop("Portrait_Frame", Vector3(50, UP + 1.95, -23.97), 0)
	prop("WallSconce_Double_Lit", Vector3(54.5, UP + 1.8, -16.03), 180, {"light_energy": 0.8, "light_range": 4.0})


## Невидимые перила: открытые края маршей, с которых игрок падал (проверка — автотест rails).
## Коллизия у ассетов лестниц есть только на пандусе, поэтому вдоль края ставятся наклонные «стенки».
func _stair_rails() -> void:
	var body := StaticBody3D.new()
	body.name = "StairRails"
	_own(groups.Gameplay, body)
	# Колоннада: марш 4 м шириной (x 22..26) спускается с террасы (z 14, y 0) на нижний ярус (z 12.2)
	for x in [21.95, 26.05]:
		_rail(body, Vector3(x, LOW, 12.1), Vector3(x, 0.0, 14.05))
	# Винтовая лестница: внешний край пандуса (радиус 1.15) на полном обороте. Начало и конец оборота
	# свободны — там вход снизу из лаза и выход на площадку бельэтажа.
	var center := Vector2(34.0, -14.0)
	var r := 1.2
	for a in range(225, 530, 10):
		_rail(body, _spiral_point(center, r, a), _spiral_point(center, r, a + 10))


## Точка внешнего края винтовой лестницы на азимуте a° (пандус поднимается на 3.24 м за оборот от 185°).
func _spiral_point(center: Vector2, r: float, a: float) -> Vector3:
	var rad := deg_to_rad(a)
	var h := LOW + (a - 185.0) / 360.0 * (UP - LOW)
	return Vector3(center.x + r * cos(rad), h, center.y - r * sin(rad))


## Наклонная стенка вдоль отрезка p0 → p1 (по поверхности марша): на 1.05 м вверх и 0.35 м вниз.
func _rail(body: StaticBody3D, p0: Vector3, p1: Vector3) -> void:
	var up := 1.05
	var down := 0.35
	var z := (p1 - p0).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, up + down, p0.distance_to(p1) + 0.04)
	cs.shape = box
	cs.transform = Transform3D(Basis(x, y, z), (p0 + p1) * 0.5 + y * (up - down) * 0.5)
	_own(body, cs)


# ---------------------------------------------------------------------------
# Геймплей: зоны, дверь, звук, свет из-под двери; игрок; окружение; интерфейс
# ---------------------------------------------------------------------------

func _gameplay() -> void:
	var gp: Node3D = groups.Gameplay
	_area("SafeZone", Vector3(52.6, UP + 1.5, -20), Vector3(6.6, 3.0, 7.4))
	_area("DoorTrigger", Vector3(46.4, UP + 1.5, -20), Vector3(3.2, 3.0, 4.0))
	var door := _inst("Door_SafeRoom")
	door.name = "SafeDoor"
	door.set_script(load("res://scripts/safe_door.gd"))
	door.transform = _xf(Vector3(48, UP, -20), -PI / 2)
	_own(gp, door)
	# Позиционный звуковой ориентир «Своей комнаты»: часы слышны издалека, камин — вблизи
	_audio3d("ClockTick", Vector3(52.6, UP + 1.7, -23.5), 0.0, 9.0, 90.0)
	_audio3d("FireCrackle", Vector3(55.4, UP + 0.5, -20), -2.0, 4.0, 40.0)
	_audio3d("Creak", Vector3(48, UP + 1.5, -20), 0.0, 4.0, 40.0)
	_audio3d("Stalker", Vector3.ZERO, 4.0, 3.0, 60.0)
	_audio3d("StalkerBreath", Vector3.ZERO, 0.0, 2.0, 30.0)
	_audio2d("Ambience", -16.0)
	_audio2d("Heartbeat", -14.0)
	_audio2d("CandleOut", -4.0)
	# Тёплый свет из-под двери: подсветка щели со стороны коридора
	var leak := OmniLight3D.new()
	leak.name = "DoorLeakLight"
	leak.position = Vector3(47.75, UP + 0.05, -20)
	leak.light_color = Color(1.0, 0.6, 0.28)
	leak.light_energy = 1.4
	leak.omni_range = 1.6
	leak.omni_attenuation = 2.0
	leak.light_volumetric_fog_energy = 0.0
	_own(groups.Lights, leak)
	# Латунь таблички ловит отсвет из-под двери — знак виден, когда подходишь к порталу
	var plaque_glow := OmniLight3D.new()
	plaque_glow.name = "PlaqueGlow"
	plaque_glow.position = Vector3(47.3, UP + 1.45, -21.62)
	plaque_glow.light_color = Color(1.0, 0.66, 0.36)
	plaque_glow.light_energy = 0.5
	plaque_glow.omni_range = 0.9
	plaque_glow.light_volumetric_fog_energy = 0.0
	_own(groups.Lights, plaque_glow)
	var strip := MeshInstance3D.new()
	strip.name = "DoorGapGlow"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.02, 1.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.22)
	mat.emission_energy_multiplier = 4.0
	bm.material = mat
	strip.mesh = bm
	strip.position = Vector3(48.02, UP + 0.012, -20)
	_own(groups.Lights, strip)


func _player() -> void:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player.gd"))
	p.position = Vector3(41, 0.05, 67)
	p.add_to_group("player", true)
	_own(level, p)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	_own(p, cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.62
	_own(p, head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.near = 0.05            # ближе 5 см к глазу геометрии нет: FP-костюм срезан по грудь, руки — от 0.2 м
	cam.fov = 72.0
	cam.current = true
	cam.cull_mask = 0xFFFFF & ~((1 << 10) | (1 << 11) | (1 << 14))   # слои 11, 12, 15 — только для отражения в зеркале
	_own(head, cam)
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.set_script(load("res://scripts/held_candle.gd"))
	hand.position = Vector3(0.22, -0.47, -0.5)
	_own(cam, hand)
	var model := _inst("Candlestick_Hand")      # ручной подсвечник: держат за ножку
	model.name = "Candle"
	_own(hand, model)
	# Перчатки от первого лица: правая держит свечу, левая прикрывает пламя (ПКМ); позы — в held_candle.gd
	for g in ["FP_Glove_Hold_R", "FP_Glove_Shield_L"]:
		var glove := _inst(g)
		glove.name = g
		_own(hand, glove)
	var light := OmniLight3D.new()
	light.name = "CandleLight"
	light.position = Vector3(0, 0.33, 0)
	light.light_color = Color(1.0, 0.62, 0.32)
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE        # ладонь в сантиметрах от огня — параболоид её искажает
	light.shadow_bias = 0.015                                # ближний заслон не «отрывается» от тени
	light.shadow_normal_bias = 0.6
	light.shadow_blur = 0.6
	light.light_size = 0.0                                   # точечное пламя: тень ладони глухая, без полутени-просвета
	_own(hand, light)
	# Тело персонажа (вид от первого лица — торс и ноги, в зеркале — целиком). Модель смотрит в +Z.
	var body := _inst(CHARACTER)
	body.name = "Body"
	body.rotation.y = PI
	body.set_script(load("res://scripts/player_body.gd"))
	_own(p, body)
	# Неявная навигация: пламя клонится к верному пути
	var guide := Node.new()
	guide.name = "RouteGuide"
	guide.set_script(load("res://scripts/route_guide.gd"))
	_own(p, guide)
	# Шаги — 3D-источник у ног: зоны комнат добавляют им реверберацию коридора, зала или склепа
	var steps := AudioStreamPlayer3D.new()
	steps.name = "Steps"
	steps.position = Vector3(0, 0.15, 0)
	steps.volume_db = -7.0
	steps.unit_size = 3.0
	steps.bus = "SFX"
	_own(p, steps)


func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.36, 0.5)
	e.ambient_light_energy = 0.035
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.04
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.8
	e.ssil_enabled = true
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.9
	e.ssr_enabled = true
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.03
	e.volumetric_fog_albedo = Color(0.55, 0.55, 0.6)
	e.volumetric_fog_length = 40.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.85
	e.adjustment_contrast = 1.06
	we.environment = e
	_own(level, we)


func _ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	_own(level, ui)
	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(fade)
	_own(ui, fade)
	var msg := Label.new()
	msg.name = "Message"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 34)
	msg.add_theme_color_override("font_color", Color(0.9, 0.82, 0.68))
	msg.modulate.a = 0.0
	_full(msg)
	_own(ui, msg)
	var hint := Label.new()
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	_full(hint)
	hint.offset_bottom = -40.0
	_own(ui, hint)


# ---------------------------------------------------------------------------
# Хелперы
# ---------------------------------------------------------------------------

func _index_models() -> void:
	var d := DirAccess.open(MODELS)
	for cat in d.get_directories():
		var sub := DirAccess.open(MODELS + "/" + cat)
		if sub == null:
			continue
		for f in sub.get_files():
			if f.ends_with(".gltf"):
				paths[f.get_basename()] = MODELS + "/" + cat + "/" + f


func _inst(asset_name: String) -> Node3D:
	if not cache.has(asset_name):
		if not paths.has(asset_name):
			push_error("[BUILD] Нет ассета " + asset_name)
		cache[asset_name] = load(paths[asset_name])
	count += 1
	return cache[asset_name].instantiate()


func _group(n: String, parent: Node) -> Node3D:
	var g := Node3D.new()
	g.name = n
	_own(parent, g)
	groups[n] = g
	return g


func _own(parent: Node, n: Node) -> void:
	parent.add_child(n, true)
	n.owner = level


func _xf(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _place(group: String, asset_name: String, xf: Transform3D, tweak := {}) -> Node3D:
	var n := _inst(asset_name)
	n.transform = xf
	if not tweak.is_empty():
		n.set_script(TWEAK)
		for k in tweak:
			n.set(k, tweak[k])
	_own(groups[group], n)
	return n


func _on(wall_xf: Transform3D, asset_name: String, local: Vector3, yaw := 0.0, tweak := {}) -> Node3D:
	return _place("Props", asset_name, wall_xf * Transform3D(Basis(Vector3.UP, yaw), local), tweak)


## Ручная расстановка: позиция, поворот вокруг Y в градусах, доп. наклоны (x, -, z) в градусах.
func prop(asset_name: String, pos: Vector3, yaw_deg := 0.0, tweak := {}, tilt := Vector3.ZERO) -> Node3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(yaw_deg), deg_to_rad(tilt.z)))
	return _place("Props", asset_name, Transform3D(b, pos), tweak)


## Угол поворота (в градусах), при котором лицо модели (+Z) смотрит из from в to.
func face(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, to.z - from.z))


func _area(n: String, pos: Vector3, size: Vector3) -> void:
	var a := Area3D.new()
	a.name = n
	a.position = pos
	_own(groups.Gameplay, a)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	_own(a, cs)


func _audio3d(n: String, pos: Vector3, vol: float, unit: float, max_dist: float) -> void:
	var a := AudioStreamPlayer3D.new()
	a.name = n
	a.position = pos
	a.volume_db = vol
	a.unit_size = unit
	a.max_distance = max_dist
	_own(groups.Gameplay, a)


func _audio2d(n: String, vol: float) -> void:
	var a := AudioStreamPlayer.new()
	a.name = n
	a.volume_db = vol
	_own(groups.Gameplay, a)


func _full(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
