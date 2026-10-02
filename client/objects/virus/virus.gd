extends Node2D
## A virus, drawn like Agar.io's: a green spiky circle. The server does all the
## virus rules (bursting blobs, being fed, shooting new viruses); this only shows
## where each one is and how big. Blobs small enough to hide under a virus are
## drawn below it, bigger ones above (see the in-game state's _set_actor_mass).

const Virus := preload("res://objects/virus/virus.gd")

## Must match VirusRadius and VirusPopRatio on the server (internal/server/viruses.go).
const RADIUS := 50.0
const POP_RATIO := 1.15

const FILL := Color(0.2, 0.85, 0.3, 0.92)
const EDGE := Color(0.08, 0.5, 0.15)
const SPIKE := 5.0 # how far the spikes stick out

var virus_id: int
var server_position: Vector2
var radius: float:
	set(value):
		radius = value
		queue_redraw()

static func instantiate(virus_id: int, x: float, y: float, radius: float) -> Virus:
	var virus := Virus.new()
	virus.virus_id = virus_id
	virus.server_position = Vector2(x, y)
	virus.position = virus.server_position
	virus.radius = radius
	virus.z_index = 2
	return virus

func update_from_server(x: float, y: float, new_radius: float) -> void:
	server_position = Vector2(x, y)
	if not is_equal_approx(radius, new_radius):
		radius = new_radius

func _process(delta: float) -> void:
	# Shot viruses send a position 20 times a second; glide between them.
	position = position.lerp(server_position, minf(1.0, delta * 15.0))

func _draw() -> void:
	var spikes := int(clampf(radius * 0.5, 20.0, 60.0))
	var points := PackedVector2Array()
	for i in spikes * 2:
		var r := radius + SPIKE if i % 2 == 0 else radius - SPIKE * 0.4
		points.append(Vector2.from_angle(TAU * i / (spikes * 2)) * r)
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, EDGE, 3.0, true)
