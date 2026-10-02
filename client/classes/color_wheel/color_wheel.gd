class_name ColorWheel
extends Control
## A ring of bright, saturated colours to pick your blob colour from, with a preview
## blob in the middle. Only vivid colours are on the ring (full brightness, at least
## MIN_SATURATION), so nobody can pick a dark grey that blends into the map.
## The server enforces the same rule when an account is created (states/connected.go).

signal color_changed(color: Color)

const MIN_SATURATION := 0.45
const HUE_STEPS := 96          # segments around the ring
const SATURATION_STEPS := 4    # rings from inner (paler) to outer (stronger)
const RING_WIDTH := 34.0

var hue := randf()
var saturation := 0.85
var color: Color:
	get:
		return Color.from_hsv(hue, saturation, 1.0)

var _dragging := false

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(200, 200)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Pick your blob colour"

func _outer_radius() -> float:
	return min(size.x, size.y) / 2.0 - 6.0

func _inner_radius() -> float:
	return _outer_radius() - RING_WIDTH

func _ring_point(h: float, radius: float) -> Vector2:
	var angle := h * TAU - PI / 2.0 # red at the top, going clockwise
	return size / 2.0 + Vector2(cos(angle), sin(angle)) * radius

func _draw() -> void:
	var inner := _inner_radius()
	var outer := _outer_radius()
	# The ring: quads with per-vertex colours, so hue and saturation blend smoothly.
	for i in HUE_STEPS:
		var h0 := float(i) / HUE_STEPS
		var h1 := float(i + 1) / HUE_STEPS
		for j in SATURATION_STEPS:
			var t0 := float(j) / SATURATION_STEPS
			var t1 := float(j + 1) / SATURATION_STEPS
			var r0: float = lerp(inner, outer, t0)
			var r1: float = lerp(inner, outer, t1)
			var s0: float = lerp(MIN_SATURATION, 1.0, t0)
			var s1: float = lerp(MIN_SATURATION, 1.0, t1)
			draw_polygon(
				PackedVector2Array([_ring_point(h0, r0), _ring_point(h1, r0), _ring_point(h1, r1), _ring_point(h0, r1)]),
				PackedColorArray([Color.from_hsv(h0, s0, 1), Color.from_hsv(h1, s0, 1), Color.from_hsv(h1, s1, 1), Color.from_hsv(h0, s1, 1)]))

	# Selector on the ring.
	var t := (saturation - MIN_SATURATION) / (1.0 - MIN_SATURATION)
	var at := _ring_point(hue, lerp(inner, outer, t))
	draw_circle(at, 9.0, color)
	draw_arc(at, 9.0, 0, TAU, 24, Color.WHITE, 3.0, true)
	draw_arc(at, 11.5, 0, TAU, 24, Color(0, 0, 0, 0.6), 1.5, true)

	# Preview blob in the middle, drawn the way blobs look in game.
	var blob_radius := inner - 18.0
	draw_circle(size / 2.0, blob_radius, color)
	if has_focus():
		draw_arc(size / 2.0, outer + 3.0, 0, TAU, 64, Color(1, 1, 1, 0.5), 2.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _pick(event.position, true)
	elif event is InputEventMouseMotion and _dragging:
		_pick(event.position, false)
	elif event is InputEventScreenTouch:
		_dragging = event.pressed and _pick(event.position, true)
	elif event is InputEventScreenDrag and _dragging:
		_pick(event.position, false)
	elif event.is_action_pressed("ui_left"):
		_set_hue_saturation(fposmod(hue - 1.0 / 48.0, 1.0), saturation)
	elif event.is_action_pressed("ui_right"):
		_set_hue_saturation(fposmod(hue + 1.0 / 48.0, 1.0), saturation)
	elif event.is_action_pressed("ui_up"):
		_set_hue_saturation(hue, min(saturation + 0.05, 1.0))
	elif event.is_action_pressed("ui_down"):
		_set_hue_saturation(hue, max(saturation - 0.05, MIN_SATURATION))
	else:
		return
	accept_event()

## Sets the colour from a point on (or near) the ring. Clicks in the middle are ignored
## when starting a drag; once dragging, any position maps to the nearest ring colour.
func _pick(at: Vector2, starting: bool) -> bool:
	var offset := at - size / 2.0
	var distance := offset.length()
	if starting and (distance < _inner_radius() - 12.0 or distance > _outer_radius() + 12.0):
		return false
	var h := fposmod((offset.angle() + PI / 2.0) / TAU, 1.0)
	var t := clampf((distance - _inner_radius()) / RING_WIDTH, 0.0, 1.0)
	_set_hue_saturation(h, lerp(MIN_SATURATION, 1.0, t))
	return true

func _set_hue_saturation(h: float, s: float) -> void:
	hue = h
	saturation = s
	queue_redraw()
	color_changed.emit(color)
