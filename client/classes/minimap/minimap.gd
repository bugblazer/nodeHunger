class_name Minimap
extends Control
## A small map of the whole arena in a corner of the screen: the walls, and every
## blob as a dot in its own colour, roughly to scale. Your blob has a white ring.
## Viruses are small green dots underneath.

const MapBorder := preload("res://objects/map_border/map_border.gd")
const REDRAW_EVERY := 1.0 / 15.0 # seconds; plenty for a map this small

## Blobs to show, keyed by id (the in-game state's actor dictionary).
var players: Dictionary
## Viruses to show, keyed by id (the in-game state's virus dictionary).
var viruses: Dictionary
## The local player's id, highlighted on the map.
var my_id: int = -1

var _since_redraw := 0.0

func _process(delta: float) -> void:
	_since_redraw += delta
	if _since_redraw >= REDRAW_EVERY:
		_since_redraw = 0.0
		queue_redraw()

func _to_map(world: Vector2) -> Vector2:
	var half := MapBorder.MAP_HALF_SIZE
	return (world + Vector2(half, half)) / (2.0 * half) * size

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.55))
	# Faint 3x3 grid so positions are easier to read.
	for i in range(1, 3):
		var x := size.x * i / 3.0
		var y := size.y * i / 3.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.08), 1.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.08), 1.0)
	draw_rect(rect, MapBorder.WALL_COLOR, false, 2.0)

	var world_to_map := size.x / (2.0 * MapBorder.MAP_HALF_SIZE)
	for id in viruses:
		var virus = viruses[id]
		if is_instance_valid(virus):
			draw_circle(_to_map(virus.position), maxf(virus.radius * world_to_map, 2.0), Color(0.2, 0.85, 0.3, 0.75))
	var me: Node2D = null
	for id in players:
		var actor = players[id]
		if not is_instance_valid(actor):
			continue
		if id == my_id:
			me = actor
			continue
		var r: float = clampf(actor.radius * world_to_map, 2.5, 18.0)
		draw_circle(_to_map(actor.position), r, actor.color)
	# Draw yourself last so you're always on top.
	if me != null:
		var r: float = clampf(me.radius * world_to_map, 3.5, 18.0)
		var at := _to_map(me.position)
		draw_circle(at, r, me.color)
		draw_arc(at, r + 1.5, 0, TAU, 24, Color.WHITE, 2.0, true)
