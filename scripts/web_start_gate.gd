class_name WebStartGate
extends CanvasLayer
## Стартовый экран веб-версии: «Кликни, чтобы войти».
## Браузер разрешает звук и захват мыши только после жеста пользователя, поэтому до клика
## игра стоит на паузе (свеча не горит), а по клику — захват мыши, снятие паузы и интро.
## На ПК не используется: там игра стартует сразу (см. game.gd).

signal started

const TITLE := "Gothic Manor — Догорающая свеча"
const PROMPT := "Кликни, чтобы войти"
const CONTROLS := "WASD — идти · Shift — бежать (свеча сгорает быстрее) · ПКМ — прикрыть пламя ладонью\nEsc — отпустить мышь · R — заново после конца"
const CREDITS := "Статуи ангелов: «Cemetery Angel — Leubner / Miller» © misterdevious (Sketchfab), CC BY-NC-SA 4.0 · " \
	+ "Руки: «Hands first person view FPS arms» © GoldGryphon (Sketchfab), CC BY 4.0, изменены\n" \
	+ "Звуки: BigSoundBank (CC0), Pixabay · Картины: Wikimedia Commons (общественное достояние) · " \
	+ "Персонаж: MakeHuman/MPFB (CC0) · Полный список — CREDITS.md в репозитории"
const BLINK_PERIOD := 1.6            ## Период мерцания приглашения, с

var _prompt: Label
var _t := 0.0


## Ставит игру на паузу и показывает экран поверх; on_start вызывается после клика.
static func show_over(host: Node, on_start: Callable) -> void:
	var gate := WebStartGate.new()
	gate.started.connect(on_start, CONNECT_ONE_SHOT)
	host.add_child(gate)
	host.get_tree().paused = true


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	bg.add_child(box)
	box.add_child(_label(TITLE, 44, Color(0.85, 0.78, 0.62)))
	_prompt = _label(PROMPT, 30, Color(1.0, 0.86, 0.55))
	box.add_child(_prompt)
	box.add_child(_label(CONTROLS, 18, Color(0.6, 0.6, 0.6)))
	var credits := _label(CREDITS, 13, Color(0.42, 0.42, 0.42))
	credits.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	credits.offset_top = -64.0
	credits.offset_bottom = -16.0
	bg.add_child(credits)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _process(delta: float) -> void:
	_t += delta
	_prompt.modulate.a = 0.55 + 0.45 * cos(_t * TAU / BLINK_PERIOD)


func _input(event: InputEvent) -> void:
	# Колесо мыши тоже приходит как нажатие кнопки, но браузер не считает его жестом — только клик или клавиша
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if not (clicked or key):
		return
	get_viewport().set_input_as_handled()
	# Захват мыши должен идти прямо в обработчике жеста — иначе браузер откажет в pointer lock
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	print("[web] старт по жесту пользователя: ", event.as_text())
	started.emit()
	queue_free()
