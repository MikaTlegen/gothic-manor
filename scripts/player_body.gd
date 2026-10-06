extends Node3D
## Тело игрока (персонаж из Blender, Character_*.gltf) при виде от первого лица.
## Основная камера видит FP-костюм (Character_FP_Suit: без рукавов, срезан по грудь, срез закрыт тёмной
## «крышкой»), полы сюртука и обувь — при взгляде вниз видны грудь, ноги и одежда, но не изнанка модели.
## Полный костюм, торс, голова, руки, перчатки и трость — только камера зеркала (слой BODY_LAYER).
## При наклоне взгляда тело отъезжает назад (BACK_SHIFT), чтобы срез у груди оставался за краем кадра.
## Тени тело не отбрасывает (свеча у самого лица — дёшево и без артефактов).
## Каждый кадр: голова наклоняется вслед за камерой, правая рука тянется к свече, левая — к ладони-щиту,
## ноги шагают в такт покачиванию камеры. Сцена персонажа меняется в build_level.gd (задел под выбор персонажа).

const BODY_LAYER := 1 << 10          ## только отражение в зеркале
const PLAYER_LAYER := 1 << 13        ## основная камера + зеркало (зеркало может его отключить)
const FP_BODY_LAYER := 1 << 16       ## только основная камера (FP-костюм), свет свечи на него падает
const FP_PART := "_FP_"              ## метка частей тела только для вида от первого лица
const MIRROR_ONLY := ["Head", "Torso", "Arms", "Gloves", "Cane", "Suit"]   ## части тела, скрытые от камеры от первого лица
const BACK_SHIFT := Vector2(0.04, 0.2)   ## сдвиг тела назад, м: взгляд прямо → взгляд в пол
const STRIDE_SWING := 0.42           ## размах бедра при шаге, рад
const SHIELD_REACH := Vector3(-0.06, 0.14, -0.04)        ## точка ладони-щита относительно свечи (оси руки)
## Роли костей → имена в риге персонажа (MPFB game_engine; для другого рига — своя таблица)
const BONE_NAMES := {
	"neck": "neck_01", "head": "head",
	"upper_arm.L": "upperarm_l", "forearm.L": "lowerarm_l", "hand.L": "hand_l",
	"upper_arm.R": "upperarm_r", "forearm.R": "lowerarm_r", "hand.R": "hand_r",
	"thigh.L": "thigh_l", "shin.L": "calf_l", "thigh.R": "thigh_r", "shin.R": "calf_r",
}
const FINGERS := ["index", "middle", "ring", "pinky"]
const ALPHA_PARTS := ["Hair", "Brows", "Lashes"]           ## волосы и ресницы — альфа-отсечение без сортировки

@export var show_cane := false       ## трость в руке со свечой выглядит странно — по умолчанию убрана
@export var animate := true          ## false — поза застыла (клон-отражение в скримере зеркала)

var skeleton: Skeleton3D
var _player: CharacterBody3D
var _camera: Camera3D
var _candle: Node3D
var _bones := {}


func _ready() -> void:
	var found := find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if skeleton == null:
		push_warning("[BODY] нет скелета в теле персонажа")
		set_process(false)
		return
	for role in BONE_NAMES:
		_bones[role] = skeleton.find_bone(BONE_NAMES[role])
		if _bones[role] < 0:
			_bones[role] = skeleton.find_bone(role)       # прежний риг (build_character.py)
	_curl_fingers()
	_player = get_parent() as CharacterBody3D
	if _player == null or not animate:
		set_process(false)
		return
	_camera = _player.get_node("Head/Camera3D") as Camera3D
	_candle = _player.get_node_or_null("Head/Camera3D/Hand") as Node3D
	set_layers(true)


## Раскладка частей тела по слоям. with_main = false — тело видно только в зеркале (клон-отражение).
func set_layers(with_main: bool, mirror_layer := BODY_LAYER) -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mi.name).contains(FP_PART):
			mi.layers = FP_BODY_LAYER
			mi.visible = with_main
			continue
		var mirror_only := not with_main
		for part in MIRROR_ONLY:
			if String(mi.name).contains(part):
				mirror_only = true
		mi.layers = mirror_layer if mirror_only else PLAYER_LAYER
		if String(mi.name).contains("Cane"):
			mi.visible = show_cane
		for part in ALPHA_PARTS:
			if String(mi.name).contains(part) and mi.mesh:
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
					if m:
						var mm := m.duplicate() as BaseMaterial3D
						mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						mm.alpha_scissor_threshold = 0.45
						mm.cull_mode = BaseMaterial3D.CULL_DISABLED
						mi.set_surface_override_material(i, mm)


## Хват: правая кисть сжата вокруг ножки подсвечника, левая — расслабленно согнута (лодочкой при защите).
func _curl_fingers() -> void:
	for side in ["r", "l"]:
		var amount := 1.15 if side == "r" else 0.35
		for f in FINGERS:
			for k in 3:
				var i := skeleton.find_bone("%s_0%d_%s" % [f, k + 1, side])
				if i >= 0:
					var rest := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
					skeleton.set_bone_pose_rotation(i, rest * Quaternion(Vector3.RIGHT, amount * (0.8 if k == 0 else 1.0)))
		var t := skeleton.find_bone("thumb_02_%s" % side)
		if t >= 0:
			var rest_t := skeleton.get_bone_rest(t).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(t, rest_t * Quaternion(Vector3.RIGHT, amount * 0.6))


func _process(_delta: float) -> void:
	_head_follow()
	if _candle:
		var hand := _candle.global_transform
		_aim_arm("R", hand.origin + hand.basis.y * 0.03, hand.origin + hand.basis.x * 0.4 - hand.basis.y * 0.3)
		var shield: float = _candle.get("_shield")
		var rest_target := global_transform * Vector3(0.26, 0.86, 0.05)   # левая кисть у бедра (модель смотрит в +Z)
		var shield_target := hand * SHIELD_REACH
		_aim_arm("L", rest_target.lerp(shield_target, shield), hand.origin - hand.basis.x * 0.5 - hand.basis.y * 0.3)
	_legs()


## Наклон головы вслед за взглядом камеры (в отражении видно, куда смотрит игрок);
## при взгляде вниз тело отъезжает назад — камера смотрит на грудь и ноги спереди, а не в срез костюма.
func _head_follow() -> void:
	var pitch := (_camera.get_parent() as Node3D).rotation.x
	turn_head(0.0, -pitch * 0.8)
	var down := smoothstep(0.15, 1.3, -pitch)
	position.z = lerpf(BACK_SHIFT.x, BACK_SHIFT.y, down)


## Поворот головы: yaw — влево-вправо, pitch — вверх-вниз (рад, оси модели).
func turn_head(yaw: float, pitch: float) -> void:
	var i: int = _bones.head
	var neck_g := skeleton.get_bone_global_pose(_bones.neck)
	var rest_g := neck_g * skeleton.get_bone_rest(i)
	var want := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * rest_g.basis
	skeleton.set_bone_pose_rotation(i, (neck_g.basis.inverse() * want).get_rotation_quaternion())


## Ноги: бедро качается по фазе шага, колено сгибается на выносе ноги.
func _legs() -> void:
	var phase: float = _player.get("stride_phase")
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var amount := clampf(speed / 1.5, 0.0, 1.4)
	for side in ["L", "R"]:
		var s := sin(phase + (0.0 if side == "L" else PI))
		_swing(_bones["thigh." + side], s * STRIDE_SWING * amount)
		_swing(_bones["shin." + side], maxf(0.0, -s) * 0.7 * amount)


## Поворот кости вокруг оси X модели (вперёд-назад) от позы покоя.
func _swing(i: int, angle: float) -> void:
	var parent_g := skeleton.get_bone_global_pose(skeleton.get_bone_parent(i))
	var rest_g := parent_g * skeleton.get_bone_rest(i)
	var want := Basis(Vector3.RIGHT, angle) * rest_g.basis
	skeleton.set_bone_pose_rotation(i, (parent_g.basis.inverse() * want).get_rotation_quaternion())


## Аналитический IK двух костей (плечо → предплечье) к цели в мире; pole — куда отводится локоть.
func _aim_arm(side: String, target_world: Vector3, pole_world: Vector3) -> void:
	var upper: int = _bones["upper_arm." + side]
	var fore: int = _bones["forearm." + side]
	var hand: int = _bones["hand." + side]
	var to_skel := skeleton.global_transform.affine_inverse()
	var target := to_skel * target_world
	var pole := to_skel * pole_world
	var chest_g := skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper))
	var up_g0 := chest_g * skeleton.get_bone_rest(upper)
	var fore_rest := skeleton.get_bone_rest(fore)
	var hand_rest := skeleton.get_bone_rest(hand)
	var s := up_g0.origin
	var l1 := fore_rest.origin.length()
	var l2 := hand_rest.origin.length()
	var to := target - s
	var d := clampf(to.length(), 0.05, l1 + l2 - 0.002)
	var dir := to.normalized()
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := pole - s
	bend = (bend - dir * bend.dot(dir)).normalized()
	var elbow := s + dir * a + bend * h
	var wrist := s + dir * d
	var rest_elbow := up_g0 * fore_rest.origin
	var q1 := Quaternion((rest_elbow - s).normalized(), (elbow - s).normalized())
	var up_g := Transform3D(Basis(q1) * up_g0.basis, s)
	skeleton.set_bone_pose_rotation(upper, (chest_g.basis.inverse() * up_g.basis).get_rotation_quaternion())
	var fore_g0 := up_g * fore_rest
	var rest_wrist := fore_g0 * hand_rest.origin
	var q2 := Quaternion((rest_wrist - elbow).normalized(), (wrist - elbow).normalized())
	var fore_basis := Basis(q2) * fore_g0.basis
	skeleton.set_bone_pose_rotation(fore, (up_g.basis.inverse() * fore_basis).get_rotation_quaternion())
