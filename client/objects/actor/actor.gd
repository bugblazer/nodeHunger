extends Area2D

const packets := preload("res://packets.gd")

const Actor := preload("res://objects/actor/actor.gd")
const Scene := preload("res://objects/actor/actor.tscn")
const MapBorder := preload("res://objects/map_border/map_border.gd")

@onready var _nameplate: Label = $Nameplate
@onready var _camera: Camera2D = $Camera2D
@onready var _collision_shape: CircleShape2D = $CollisionShape2D.shape

var actor_id :int
var actor_name : String
var start_x: float
var start_y: float
var start_rad: float
var speed: float
var color: Color
var is_player: bool
var server_position: Vector2

var _sent_direction := false
var _target_zoom := 2.0 #when the game starts, we'll be zoomed in at x2
var _furthest_zoom_allowed := _target_zoom

var velocity: Vector2
var radius: float:
	set(new_radius):
		radius = new_radius
		_collision_shape.radius = new_radius
		_update_zoom()
		queue_redraw()

#Constructor for the class
static func instantiate(actor_id: int, actor_name: String, x: float, y: float, radius: float, speed: float, color: Color, is_player: bool) -> Actor:
	var actor := Scene.instantiate()
	actor.actor_id = actor_id
	actor.actor_name = actor_name
	actor.start_x = x
	actor.start_y = y
	actor.start_rad = radius
	actor.speed = speed
	actor.color = color
	actor.is_player = is_player
	
	return actor

func _ready() -> void:
	position.x = start_x
	position.y = start_y
	# Start the server position where the blob spawns. Left at (0, 0), every new blob
	# slid towards the middle of the map until its first position update arrived.
	server_position = position
	velocity = Vector2.RIGHT * speed
	radius = start_rad
	
	_collision_shape.radius = radius
	_nameplate.text = actor_name
	# The scene's LabelSettings resource is shared by every blob, and it overrides
	# theme font sizes. Give each blob its own copy so its name can grow with it.
	_nameplate.label_settings = _nameplate.label_settings.duplicate()
	_update_nameplate()

func _process(delta: float) -> void:
	if not is_equal_approx(_camera.zoom.x, _target_zoom):
		_camera.zoom -= Vector2(1,1) * (_camera.zoom.x - _target_zoom) * 0.05
	
#Zooming in and out:
func _input(event: InputEvent) -> void:
	if is_player and event is InputEventMouseButton and event.is_pressed():
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = min(4, _target_zoom + 0.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = max(_furthest_zoom_allowed, _target_zoom - 0.1)
	
func _physics_process(delta: float) -> void:
	position += velocity * delta
	server_position += velocity * delta
	position += (server_position - position) * 0.05
	# Stop at the map walls like the server does, so blobs slide along the wall
	# instead of drifting past it and snapping back on the next server update.
	position = MapBorder.clamp_to_map(position, radius)
	server_position = MapBorder.clamp_to_map(server_position, radius)
	#^ Multiplying by delta as it's the time passed since last frame refresh
	#delta will be small if the game is not laggy, it'll be large if the game
	#is laggy
	
	if not is_player:
		return
	#returns out of the func if it's not the client as below we're going to
	#take input from the user
	
	var mouse_pos := get_global_mouse_position()
	
	var input_vec := position.direction_to(mouse_pos).normalized()
	#The above line is reading the mouse position for every change in it
	#but we don't want to spam the server with every little change  in the 
	#mouse pos. So we'll divide our circle(circle = 2*PI which is equal to TAU)
	#into 15 parts, and the position will not change long as the player remains
	#in one part
	#Always send the first direction: the server only starts moving the player once it
	#has one, and a mouse already within 12 degrees of the starting heading (right)
	#never triggered a send, so the blob drifted off on screen while staying still
	#on the server.
	if abs(velocity.angle_to(input_vec)) > TAU / 15 or not _sent_direction: #12 degrees
		_sent_direction = true
		velocity = input_vec * speed
		var packet := packets.Packet.new()
		var player_direction_message := packet.new_player_direction()
		player_direction_message.set_direction(velocity.angle())
		WS.send(packet)

func _update_zoom() -> void:
	if is_node_ready():
		_update_nameplate()

	if not is_player:
		return
	
	var new_furthest_zoom_allowed := 2 * start_rad / radius
	if is_equal_approx(_target_zoom, _furthest_zoom_allowed):
		_target_zoom = new_furthest_zoom_allowed
	_furthest_zoom_allowed = new_furthest_zoom_allowed

#drawing the player blob
func _draw() -> void:
	draw_circle(Vector2.ZERO, _collision_shape.radius, color)

## The name grows with the blob: half the radius, never smaller than 16. The
## outline grows too, so big names stay readable over other blobs.
func _update_nameplate() -> void:
	var settings := _nameplate.label_settings
	settings.font_size = int(max(16.0, radius / 2.0))
	settings.outline_size = int(max(4.0, settings.font_size / 6.0))
