class_name Log
extends RichTextLabel

## Seconds a message stays on screen. 0 keeps every message (in-game chat history);
## the login and sign-up screens use a few seconds so old errors don't pile up.
@export var message_lifetime := 0.0
## With a lifetime set, only this many recent messages are shown at once.
@export var max_messages := 3

var _entries: Array = [] # [bbcode line, expiry in msec]

func _message(message: String, color: Color = Color.WHITE) -> void:
	var line := "[color=#%s]%s[/color]" % [color.to_html(false), message]
	if message_lifetime <= 0.0:
		append_text(line + "\n")
		return
	_entries.append([line, Time.get_ticks_msec() + int(message_lifetime * 1000.0)])
	while _entries.size() > max_messages:
		_entries.pop_front()
	_render()

func _process(_delta: float) -> void:
	if message_lifetime <= 0.0 or _entries.is_empty():
		return
	var now := Time.get_ticks_msec()
	var before := _entries.size()
	_entries = _entries.filter(func(e): return e[1] > now)
	if _entries.size() != before:
		_render()

func _render() -> void:
	clear()
	for e in _entries:
		append_text(e[0] + "\n")

## Removes every message now (e.g. when switching between login and sign-up).
func clear_messages() -> void:
	_entries.clear()
	clear()

func info(message: String) -> void:
	_message(message, Color.WHITE)

func warning(message: String) -> void:
	_message(message, Color.YELLOW)

func error(message: String) -> void:
	_message(message, Color.ORANGE_RED)

func success(message: String) -> void:
	_message(message, Color.LAWN_GREEN)

func chat(sender_name: String, message: String) -> void:
	_message("[color=#%s]%s:[/color] [i]%s[/i]" % [Color.CORNFLOWER_BLUE.to_html(false), sender_name, message])
