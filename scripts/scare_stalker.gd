extends Area3D
## «Шаги из темноты» (склеп): когда игрок входит в зону, впереди во тьме кто-то срывается на бег и мчится
## к нему — шаги всё чаще и громче, но обрываются у самой границы света свечи. Тишина. Один раз.
## Темп: пока не прошла передышка после прошлого скримера (ScareLedger), ждёт, пока игрок в зоне.

const FIRST_INTERVAL := 0.34
const MIN_INTERVAL := 0.2
const LIGHT_MARGIN := 0.9            ## шаги стихают на этой доле радиуса света свечи
const MIN_STOP := 4.0                ## но не ближе, м

@export var start_point := Vector3.ZERO    ## откуда начинается бег (мировые координаты)
@export var step_length := 1.15

var fired := false
var _player: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not fired and body.is_in_group("player"):
		_player = body as Node3D


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null


func _process(_delta: float) -> void:
	if not fired and _player and ScareLedger.can_fire("stalker_steps"):
		fire(_player)


func fire(player: Node3D) -> void:
	fired = true
	print("[SCARE] шаги из темноты")
	ScareLedger.note_scare("stalker_steps")
	var sfx := $Steps as AudioStreamPlayer3D
	var light := player.get_node("Head/Camera3D/Hand/CandleLight") as OmniLight3D
	var pos := start_point
	var interval := FIRST_INTERVAL
	for i in 40:
		if not is_instance_valid(player) or not light.visible:
			break           # уровень перезапущен или свеча погасла — у Game Over свои шаги
		var to_player := player.global_position - pos
		to_player.y = 0.0
		var stop := maxf(light.omni_range * LIGHT_MARGIN, MIN_STOP)
		if to_player.length() - step_length < stop:
			break
		pos += to_player.normalized() * step_length
		sfx.global_position = Vector3(pos.x, start_point.y + 0.1, pos.z)
		sfx.play()
		await get_tree().create_timer(interval).timeout
		interval = maxf(interval * 0.92, MIN_INTERVAL)
	print("[SCARE] шаги оборвались у границы света")
