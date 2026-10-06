extends Node
## ScareLedger (автолоад): учёт гарантированных скримеров уровня.
## Каждый гарантированный скример регистрируется при старте уровня и отмечается при срабатывании.
## При победе несработавшие (игрок не прошёл через их узкий проход — например, ушёл срезкой)
## переносятся в очередь следующего уровня: user://scare_ledger.json
##   {"from_level": 1, "carry_over": ["door_slam", "statue_head"], "saved_at": "2026-10-05T21:00:00"}
## Перезапуск уровня (R) начинает учёт заново; файл переписывается только при прохождении.
##
## Темп (pacing): каждый скример — гарантированный или фоновый — отмечается note_scare(); can_fire() не даёт
## следующему сработать раньше передышки (фоновым — REST_AMBIENT, гарантированным — REST_GUARANTEED).
## Скримеры, которые ждут взгляда игрока, просто ждут дольше. В лог — хронология «[PACE] t=…».

const SAVE_PATH := "user://scare_ledger.json"
const REST_AMBIENT := 18.0           ## фоновый скример — не раньше, чем через столько секунд после прошлого
const REST_GUARANTEED := 9.0         ## гарантированный в узком проходе ждёт меньше: его нельзя потерять

var level := 1
var _registered: Array[String] = []
var _fired: Array[String] = []
var pacing := true                  ## автотест скримеров выключает передышку (ставит камеру к каждому подряд)
var _time := 0.0                    ## игровое время уровня, с (учитывает Engine.time_scale)
var _last := -1000.0


## Начало уровня: сброс учёта (вызывается из game.gd при загрузке сцены).
func begin_level(level_id: int) -> void:
	level = level_id
	_registered.clear()
	_fired.clear()
	_time = 0.0
	_last = -1000.0


func _process(delta: float) -> void:
	_time += delta


func register(id: String) -> void:
	if not _registered.has(id):
		_registered.append(id)


func mark_fired(id: String) -> void:
	if not _fired.has(id):
		_fired.append(id)
	note_scare(id)
	print("[LEDGER] сработал гарантированный скример %s (%d/%d)" % [id, _fired.size(), _registered.size()])


## Скример сработал (любой): время для передышки и строка хронологии.
func note_scare(id: String) -> void:
	print("[PACE] t=%.1f с %s (пауза %.1f с)" % [_time, id, _time - _last])
	_last = _time


## Можно ли сработать сейчас: прошла передышка после прошлого скримера.
func can_fire(_id: String, rest := REST_AMBIENT) -> bool:
	return not pacing or _time - _last >= rest


func is_fired(id: String) -> bool:
	return _fired.has(id)


func missed() -> Array[String]:
	var out: Array[String] = []
	for id in _registered:
		if not _fired.has(id):
			out.append(id)
	return out


## Уровень пройден: несработавшие скримеры — в очередь следующего уровня (файл).
func level_completed() -> Array[String]:
	var carry := missed()
	var data := {"from_level": level, "carry_over": carry, "saved_at": Time.get_datetime_string_from_system()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[LEDGER] не удалось записать %s: %s" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return carry
	f.store_string(JSON.stringify(data, "\t"))
	print("[LEDGER] уровень %d пройден, на следующий перенесено: %s" % [level, carry])
	return carry


## Очередь для уровня level_id (для будущего Уровня 2): список id скримеров, не сработавших на прошлом.
func pending_for(level_id: int) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or int(parsed.get("from_level", 0)) != level_id - 1:
		return out
	for id in parsed.get("carry_over", []):
		out.append(String(id))
	return out
