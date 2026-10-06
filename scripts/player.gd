extends CharacterBody3D
## Игрок от первого лица: ходьба 1.5 м/с (осторожный шаг в темноте), бег 2.6 м/с.
## Бег ускоряет сгорание свечи и рвёт пламя (см. held_candle.gd); ПКМ — прикрыть пламя ладонью.
## Есть автопилот для проверки маршрута по времени.

signal step_taken

const WALK_SPEED := 1.5
const RUN_SPEED := 2.6
const ACCEL := 10.0
const GRAVITY := 9.8
const MOUSE_SENS := 0.0022
const STEP_LENGTH := 0.75            ## Длина шага, м — для звука и покачивания камеры
const BOB_AMP := 0.03
const WAYPOINT_RADIUS := 0.35

@export var input_enabled := true    ## Ходьба (обзор мышью работает, пока look_enabled)
@export var look_enabled := true

var is_running := false
var is_shielding := false
var force_run := false               ## автотест: бежать без клавиш
var force_shield := false            ## автотест: держать ладонь у пламени
var stride_phase := 0.0              ## фаза шага (для ног персонажа в зеркале)
var surface := "wood"                ## пол под ногами (stone | wood) — задают зоны комнат room_zone.gd
var autopilot: PackedVector3Array = PackedVector3Array()
var autopilot_index := 0
var autopilot_done := false
var distance_walked := 0.0

var _step_acc := 0.0
var _bob_phase := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _ap_prev := Vector3.INF

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var candle: Node = $Head/Camera3D/Hand


func _ready() -> void:
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	_last_pos = global_position
	# В браузере захват мыши без жеста отклоняется — там его делает экран старта (web_start_gate.gd)
	if not OS.get_cmdline_user_args().has("--autotest") and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and look_enabled:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.45, 1.45)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	is_running = false
	if not autopilot.is_empty() and not autopilot_done:
		wish = _autopilot_dir()
		is_running = force_run
	elif input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = transform.basis * Vector3(v.x, 0, v.y)
		wish.y = 0
		if wish.length() > 1.0:
			wish = wish.normalized()
		is_running = Input.is_action_pressed("sprint") and v.y < 0.0
	var target := wish * (RUN_SPEED if is_running else WALK_SPEED)
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	is_shielding = force_shield or (input_enabled and Input.is_action_pressed("shield"))
	if candle and candle.has_method("set_running"):
		candle.set_running(is_running)
		candle.set_shielded(is_shielding)
	_update_steps(delta)


## Автопилот: идёт по точкам маршрута со скоростью ходьбы; при застревании переходит к следующей точке.
func _autopilot_dir() -> Vector3:
	var p := global_position
	var target := autopilot[autopilot_index]
	var to := Vector3(target.x - p.x, 0, target.z - p.z)
	if to.length() < WAYPOINT_RADIUS:
		autopilot_index += 1
		_stuck_time = 0.0
		if autopilot_index >= autopilot.size():
			autopilot_done = true
			return Vector3.ZERO
		return _autopilot_dir()
	var progressed := Vector2(p.x - _ap_prev.x, p.z - _ap_prev.z).length()
	_ap_prev = p
	if progressed < 0.001:
		_stuck_time += get_physics_process_delta_time()
		if _stuck_time > 3.0:
			push_warning("[AUTOTEST] Застрял у точки %d %s, позиция %s" % [autopilot_index, target, p])
			autopilot_index = mini(autopilot_index + 1, autopilot.size() - 1)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
	rotation.y = atan2(-to.x, -to.z)
	return to.normalized()


func _update_steps(delta: float) -> void:
	var p := global_position
	var moved := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	if not is_on_floor() or moved < 0.0005:
		camera.position.y = lerpf(camera.position.y, 0.0, delta * 6.0)
		return
	distance_walked += moved
	_step_acc += moved
	_bob_phase += moved / STEP_LENGTH * PI
	stride_phase = _bob_phase
	camera.position.y = sin(_bob_phase * 2.0) * BOB_AMP * (1.6 if is_running else 1.0)
	camera.position.x = cos(_bob_phase) * BOB_AMP * 0.5
	if _step_acc >= STEP_LENGTH:
		_step_acc = 0.0
		step_taken.emit()
