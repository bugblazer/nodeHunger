class_name Toast
extends PanelContainer
## A message pill at the top of the screen (login and sign-up results, errors).
## Shows the latest message and hides itself after `lifetime` seconds.

@export var lifetime := 5.0

var _label: Label
var _timer: Timer

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide)
	add_child(_timer)

func _show_message(message: String, color: Color) -> void:
	_label.text = message
	_label.add_theme_color_override("font_color", color)
	reset_size() # shrink back if the previous message was longer
	position.x = (get_viewport_rect().size.x - get_combined_minimum_size().x) / 2.0
	show()
	_timer.start(lifetime)

func info(message: String) -> void:
	_show_message(message, Color.WHITE)

func warning(message: String) -> void:
	_show_message(message, Color.YELLOW)

func error(message: String) -> void:
	_show_message(message, Color(1.0, 0.45, 0.35))

func success(message: String) -> void:
	_show_message(message, Color.LAWN_GREEN)

## Hides the toast now (e.g. when switching between login and sign-up).
func clear_messages() -> void:
	_timer.stop()
	hide()
