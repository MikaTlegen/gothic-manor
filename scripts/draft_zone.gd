extends Area3D
## Сквозняк в узкой арке: при первом входе пламя свечи сильно тускнеет и прижимается,
## в арке гудит порыв ветра, а у самого уха (слева или справа) — тихий шёпот. Один раз.

const GUST_TIME := 2.2

@export var whisper := "whisper_1"

var fired := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if fired or not body.is_in_group("player"):
		return
	fired = true
	var candle := body.get_node_or_null("Head/Camera3D/Hand")
	if candle and candle.has_method("gust"):
		candle.gust(GUST_TIME)
	var gust := get_node_or_null("Gust") as AudioStreamPlayer3D
	if gust:
		gust.play()
	print("[SCARE] сквозняк %s" % name)
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(body):
		_whisper(body.get_node("Head"))


## Шёпот «в наушниках»: источник в полуметре от головы — панорама уводит его в одно ухо.
func _whisper(head: Node3D) -> void:
	var w := AudioStreamPlayer3D.new()
	w.stream = HorrorAudio.one(whisper)
	w.volume_db = -16.0
	w.unit_size = 0.6
	w.max_distance = 6.0
	w.bus = "Scare"
	w.position = Vector3(0.45 if randf() < 0.5 else -0.45, 0.05, 0.1)
	head.add_child(w)
	w.finished.connect(w.queue_free)
	w.play()
