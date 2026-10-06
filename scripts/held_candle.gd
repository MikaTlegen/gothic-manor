extends Node3D
## Свеча в руке — главный таймер уровня.
## Горит burn_time секунд (бег ускоряет сгорание). Воск укорачивается, пламя опускается вместе с ним,
## радиус и яркость света угасают по фазам, но до конца остаются читаемыми (~3 м): пламя мельчает, мерцает
## и «захлёбывается», а окружение всё ещё видно. Догорела — свет выключается полностью (кромешная тьма).
##
## Бег без защиты: пламя рвётся и тускнеет, через RUN_LIMIT секунд непрерывного бега свеча гаснет (Game Over).
## Защита ладонью (ПКМ): левая ладонь встаёт перед пламенем. Свет не подкручивается — ладонь физически
## заслоняет огонь: перекрывает часть кадра и отбрасывает тень от свечи (теневой двойник перчатки на
## основном слое), впереди становится темнее. Под ладонью пламя не боится ни бега, ни сквозняка.
## Свеча стоит в ручном подсвечнике (Candlestick_Hand): правая рука держит его за ножку.
## Руки — готовый ассет «FPS arms» (GoldGryphon, CC BY) в старых кожаных перчатках, пальцы согнуты в Blender
## (FP_Glove_*.gltf, build_fp_arms.py; точка хвата — ось «туннеля» кулака): начало координат — запястье,
## пальцы → -Z, большой палец → +Y, ладонь правой → -X, левой → +X.

signal extinguished
signal phase_changed(phase: int)

const FLAME_HEIGHT := 0.13           ## Высота воска свечи в подсвечнике, м (пламя стоит на его верхушке)
const MIN_WAX := 0.15                ## Доля воска к моменту угасания
## Ключевые точки угасания: [доля сгоревшего, радиус света м, яркость]
const CURVE := [
	[0.00, 7.0, 2.0],
	[0.35, 6.2, 1.8],
	[0.70, 5.0, 1.5],
	[0.90, 3.8, 1.2],
	[1.00, 3.2, 1.0],          ## финал: пламя мельчает, но комнату ещё видно
]
const GUTTER_DIP := 0.6              ## провал света, когда пламя «захлёбывается» в агонии (доля яркости)
const PHASE_EDGES := [0.35, 0.70, 0.90]   ## Фазы: 0 ровный свет, 1 сужение, 2 тревога, 3 агония
const HAND_LAYER := 2                      ## Слой рендера свечи в руке (бит 2)
const FP_LAYER := 1 << 15                  ## Перчатки от первого лица: видит только основная камера
const RUN_LIMIT := 4.0               ## Секунд непрерывного бега без защиты до угасания
const RUN_RECOVER := 1.5             ## За сколько секунд шага пламя полностью успокаивается
const SHIELD_TIME := 0.25            ## Ладонь поднимается/опускается, с
## Позы рук (оси руки со свечой): [куда смотрят пальцы, куда смотрит большой палец,
##  точка кисти в её осях, куда эта точка встаёт]
## Правая: «туннель» кулака — на оси ножки подсвечника (ножка 6–13 см от основания), большой палец вверх,
## предплечье уходит назад-вниз к правому краю кадра.
## Левая: ладонь стоит почти вертикально слева-спереди от пламени (пламя на ~0.32 м), пальцы вверх и чуть
## вперёд, ладонь к огню — заслон от ветра: центр кадра свободен, тень ладони ложится вперёд-влево;
## в покое — внизу слева за кадром.
const HOLD_POSE := [Vector3(-0.45, 0.25, -0.86), Vector3(0.0, 1.0, 0.0), Vector3(-0.02, 0.004, -0.097), Vector3(0.0, 0.095, 0.0)]
const SHIELD_UP := [Vector3(0.12, 0.88, -0.45), Vector3(0.1, 0.1, 1.0), Vector3(0.012, -0.004, -0.055), Vector3(-0.065, 0.33, -0.035)]
const SHIELD_DOWN := [Vector3(0.12, 0.88, -0.45), Vector3(0.1, 0.1, 1.0), Vector3(0.012, -0.004, -0.055), Vector3(-0.24, -0.3, 0.1)]
const SHADOW_SCALE := 1.15           ## Теневой двойник ладони чуть крупнее видимой: без просветов по контуру
const WICK_LIGHT_UP := 0.012         ## Свет — чуть выше основания язычка, в его ядре
const GLOVE_SCALE := 1.0

@export var burn_time := 285.0
@export var run_burn_multiplier := 1.6

var burned := 0.0
var burning := true
var lit := true
var phase := 0
var run_strain := 0.0                ## 0..1: доля RUN_LIMIT, пробеганная без защиты
var out_reason := ""                 ## "burned" | "run" — почему погасла
var shielded := false
var lean := Vector3.ZERO             ## куда клонится язычок пламени (в осях руки, задаёт навигация)

var _running := false
var _shield := 0.0
var _snuffed := 0.0                  ## секунд до повторного вспыхивания после задувания
var _t := 0.0
var _noise := FastNoiseLite.new()
var _body: Node3D
var _flame: Node3D
var _flame_y0 := 0.0
var _light_y0 := 0.0
var _light_base := Vector3.ZERO     ## точка света над фитилём (оси руки)
var _gust_left := 0.0
var _gust_time := 1.0
var _shield_shadow: Node3D             ## невидимый двойник ладони: только тень от свечи
var _glove_shield: Node3D

@onready var _model: Node3D = $Candle
@onready var _light: OmniLight3D = $CandleLight


func _ready() -> void:
	_body = _model.find_child("*_Body", true, false)
	_flame = _make_flame_pivot(_model.find_child("*_Flame", true, false) as MeshInstance3D)
	# Свой источник света — с тенями и угасанием; импортированный убираем
	for n in _model.find_children("*", "OmniLight3D", true, false):
		n.queue_free()
	# Воск в сантиметрах от источника пересвечивается: свеча живёт на слое 2, основной свет его не трогает,
	# а слабая подсветка WaxLight освещает только этот слой и перчатки
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = HAND_LAYER
	_light.light_cull_mask = ~(HAND_LAYER | FP_LAYER) & 0xFFFFF
	var wax_light := OmniLight3D.new()
	wax_light.name = "WaxLight"
	wax_light.light_cull_mask = HAND_LAYER | FP_LAYER
	wax_light.light_color = Color(1.0, 0.62, 0.32)
	wax_light.light_energy = 0.45
	wax_light.omni_range = 0.45
	wax_light.position = Vector3(0.04, 0.2, 0.06)
	add_child(wax_light)
	# Отсвет пламени от стен на перчатки со стороны глаз: без него тыльная сторона ладони — сплошной силуэт
	var fill := OmniLight3D.new()
	fill.name = "HandFill"
	fill.light_cull_mask = FP_LAYER
	fill.light_color = Color(1.0, 0.66, 0.4)
	fill.light_energy = 0.25
	fill.omni_range = 0.9
	fill.position = Vector3(-0.15, 0.45, 0.3)
	add_child(fill)
	_setup_glove("FP_Glove_Hold_R", _pose(HOLD_POSE))
	_glove_shield = _setup_glove("FP_Glove_Shield_L", _pose(SHIELD_DOWN))
	_make_shield_shadow()
	if _flame:
		_flame_y0 = _flame.position.y
		_light_base = _model.transform * (_flame.position + Vector3.UP * WICK_LIGHT_UP)
	else:
		_light_base = _light.position
	_light_y0 = _light_base.y
	_noise.seed = randi()
	_noise.frequency = 0.9
	_apply(0.0)


## Шарнир пламени ровно на фитиле: у импортированного узла *_Flame начало координат — у основания свечи,
## и наклон/масштаб уносили язычок с фитиля. Шарнир встаёт в основание язычка (низ его меша по центру),
## меш переносится внутрь без изменения вида; наклон, масштаб и опускание воска применяются к шарниру.
func _make_flame_pivot(mesh: MeshInstance3D) -> Node3D:
	if mesh == null:
		return null
	var box := mesh.get_aabb()
	var base_local := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var pivot := Node3D.new()
	pivot.name = "FlamePivot"
	var parent := mesh.get_parent()
	parent.add_child(pivot)
	pivot.transform = Transform3D(Basis.IDENTITY, mesh.transform * base_local)
	var xf := mesh.transform
	parent.remove_child(mesh)
	pivot.add_child(mesh)
	mesh.transform = pivot.transform.affine_inverse() * xf
	return pivot


## Поза кисти: пальцы (её -Z) — по p[0], большой палец (её +Y) — к p[1]; сдвиг так, чтобы точка
## кисти p[2] встала в точку p[3] (оси руки).
static func _pose(p: Array) -> Transform3D:
	var z: Vector3 = -(p[0] as Vector3).normalized()
	var y: Vector3 = ((p[1] as Vector3) - z * z.dot(p[1])).normalized()
	var basis := Basis(y.cross(z), y, z)
	return Transform3D(basis, p[3] - basis * p[2])


## Теневой двойник ладони: та же перчатка на основном слое, «только тень» — свеча отбрасывает
## от ладони настоящую тень на стены и пол (видимая перчатка живёт на слое первого лица).
func _make_shield_shadow() -> void:
	if _glove_shield == null:
		return
	_shield_shadow = _glove_shield.duplicate() as Node3D
	_shield_shadow.name = "ShieldShadow"
	add_child(_shield_shadow)
	# Двусторонний непрозрачный материал: тень отбрасывают обе стороны перчатки и рукава
	var solid := StandardMaterial3D.new()
	solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	for n in _shield_shadow.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = 1
		mi.material_override = solid
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# «Перепонка» между пальцами и по ладони: свет не пробивается в щели (ладонь — плоскость YZ кисти)
	var web := MeshInstance3D.new()
	web.name = "PalmWeb"
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.085, 0.16)
	web.mesh = box
	web.position = Vector3(0.01, 0.0, -0.095)
	web.material_override = solid
	web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_shield_shadow.add_child(web)


## Перчатки от первого лица (сцены из Blender): только для основной камеры, без теней.
func _setup_glove(node_name: String, xf: Transform3D) -> Node3D:
	var g := get_node_or_null(node_name) as Node3D
	if g == null:
		return null
	g.transform = xf
	g.scale = Vector3.ONE * GLOVE_SCALE
	for n in g.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = FP_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func set_running(value: bool) -> void:
	_running = value


func set_shielded(value: bool) -> void:
	shielded = value


func remaining() -> float:
	return 1.0 - burned


func stop() -> void:
	burning = false


## Порыв сквозняка: пламя прижимается и тускнеет на duration секунд (не гаснет). Ладонь гасит порыв.
func gust(duration: float) -> void:
	_gust_time = duration
	_gust_left = duration


## Пламя сдуло (хлопнула дверь): полная темнота на duration секунд, затем фитиль вспыхивает снова.
## Таймер свечи при этом идёт. Ладонь не спасает — порыв слишком резкий.
func snuff(duration: float) -> void:
	if not lit:
		return
	_snuffed = duration
	_set_visible_light(false)


func is_snuffed() -> bool:
	return _snuffed > 0.0


func _process(delta: float) -> void:
	_t += delta
	_shield = move_toward(_shield, 1.0 if shielded and lit else 0.0, delta / SHIELD_TIME)
	if _glove_shield:
		_glove_shield.visible = _shield > 0.0
		_glove_shield.transform = _pose(SHIELD_DOWN).interpolate_with(_pose(SHIELD_UP), smoothstep(0.0, 1.0, _shield))
		_glove_shield.scale = Vector3.ONE * GLOVE_SCALE
		if _shield_shadow:
			_shield_shadow.visible = _shield > 0.3
			_shield_shadow.transform = _glove_shield.transform.scaled_local(Vector3.ONE * SHADOW_SCALE)
	if burning and lit:
		var rate := (run_burn_multiplier if _running else 1.0) / burn_time
		burned = minf(burned + rate * delta, 1.0)
		var p := 0
		for edge in PHASE_EDGES:
			if burned >= edge:
				p += 1
		if p != phase:
			phase = p
			phase_changed.emit(phase)
		_update_strain(delta)
		if burned >= 1.0:
			_go_out("burned")
			return
		if run_strain >= 1.0:
			_go_out("run")
			return
	_gust_left = maxf(_gust_left - delta, 0.0)
	if _snuffed > 0.0:
		_snuffed -= delta
		if _snuffed <= 0.0 and lit:
			_set_visible_light(true)
	elif lit:
		_apply(delta)
	# Позиция и яркость пламени — глобальные параметры шейдеров (паутина вспыхивает рядом со свечой)
	var energy := 0.0
	if lit and _snuffed <= 0.0:
		energy = _light.light_energy
	RenderingServer.global_shader_parameter_set("candle_pos", _light.global_position)
	RenderingServer.global_shader_parameter_set("candle_energy", energy)


## Бег без защиты копит «надрыв» пламени, шаг или ладонь его снимают.
func _update_strain(delta: float) -> void:
	if _running and _shield < 0.5:
		run_strain = minf(run_strain + delta / RUN_LIMIT, 1.0)
	else:
		run_strain = maxf(run_strain - delta / RUN_RECOVER, 0.0)


## Сила порыва 0..1: быстрый набег и медленное отпускание; ладонь гасит большую часть.
func _gust_amount() -> float:
	if _gust_left <= 0.0:
		return 0.0
	var t := 1.0 - _gust_left / _gust_time
	return smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.55, 1.0, t)) * (1.0 - 0.75 * _shield)


func _sample(col: int) -> float:
	for i in range(1, CURVE.size()):
		if burned <= CURVE[i][0]:
			var a: Array = CURVE[i - 1]
			var b: Array = CURVE[i]
			return lerpf(a[col], b[col], (burned - a[0]) / (b[0] - a[0]))
	return CURVE[-1][col]


func _apply(delta: float) -> void:
	var wax := lerpf(1.0, MIN_WAX, burned)
	if _body:
		_body.scale.y = wax
	var drop := FLAME_HEIGHT * (1.0 - wax)
	var agony := smoothstep(0.85, 1.0, burned)
	var g := _gust_amount()
	var strain := run_strain * (1.0 - _shield)
	if _flame:
		_flame.position.y = _flame_y0 - drop
		var shake := 1.0 + _noise.get_noise_1d(_t * (9.0 + 30.0 * strain)) * (0.12 + 0.45 * strain)
		_flame.scale = Vector3.ONE * lerpf(1.0, 0.5, agony) * lerpf(1.0, 0.55, strain) * shake
		_flame.scale *= Vector3(1.0 + 0.35 * g, 1.0 - 0.55 * g, 1.0 + 0.2 * g)
		# Наклон: сквозняк — вбок, бег — назад (встречный поток), навигация — слегка к верному пути
		var lean_target := Vector3(
			lean.z * 0.2 + strain * deg_to_rad(35.0) * (1.0 + 0.4 * _noise.get_noise_1d(_t * 21.0)),
			0.0,
			g * deg_to_rad(28.0) * (1.0 + 0.3 * _noise.get_noise_1d(_t * 14.0)) - lean.x * 0.2)
		var k := minf(delta * 6.0, 1.0) if delta > 0.0 else 1.0
		_flame.rotation = _flame.rotation.lerp(lean_target, k)
	# Мерцание: слабое в начале, рваное в конце, при беге и на надрыве; под ладонью — ровнее
	var amp := lerpf(0.06, 0.4, smoothstep(0.7, 1.0, burned)) + (0.12 if _running else 0.0) + 0.5 * strain
	amp *= lerpf(1.0, 0.4, _shield)
	var n := _noise.get_noise_1d(_t * 7.0) + 0.5 * _noise.get_noise_1d(_t * 23.0 + 50.0)
	var gutter := 1.0
	if burned > 0.9 and _noise.get_noise_1d(_t * 3.0 + 99.0) > 0.35:
		gutter = GUTTER_DIP      # пламя «захлёбывается» — короткие провалы света (окружение остаётся видно)
	if strain > 0.5 and _noise.get_noise_1d(_t * 11.0 + 7.0) > 0.6 - 0.5 * strain:
		gutter *= 0.3            # на бегу пламя срывается и почти гаснет
	var draft := lerpf(1.0, 0.28 + 0.12 * absf(_noise.get_noise_1d(_t * 17.0)), g)
	var energy := maxf(_sample(2) * (1.0 + n * amp) * gutter * draft * lerpf(1.0, 0.45, strain), 0.02)
	var radius := _sample(1)
	_light.omni_range = radius
	_light.light_energy = energy
	# Свет держится над фитилём и следует за наклоном язычка; дрожание — в пределах пламени (±3 мм)
	var pos := _light_base + Vector3(0.0, -drop, 0.0)
	if _flame:
		pos = _model.transform * (_flame.position + _flame.basis * (Vector3.UP * WICK_LIGHT_UP))
	pos += Vector3(_noise.get_noise_1d(_t * 5.0 + 11.0), 0.0, _noise.get_noise_1d(_t * 5.0 + 37.0)) * 0.003
	_light.position = pos


func _set_visible_light(on: bool) -> void:
	_light.visible = on
	if _flame:
		_flame.visible = on
	for n in ["WaxLight", "HandFill"]:
		var l := get_node_or_null(n) as Light3D
		if l:
			l.visible = on       # без пламени не светятся ни воск, ни перчатки


func _go_out(reason: String) -> void:
	lit = false
	burning = false
	out_reason = reason
	_set_visible_light(false)
	RenderingServer.global_shader_parameter_set("candle_energy", 0.0)
	extinguished.emit()
