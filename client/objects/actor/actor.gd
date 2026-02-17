extends Area2D

const packets := preload("res://packets.gd")

const Actor := preload("res://objects/actor/actor.gd")
const Scene := preload("res://objects/actor/actor.tscn")

@onready var _nameplate: Label = $Nameplate
@onready var _camera: Camera2D = $Camera2D
@onready var _collision_shape: CircleShape2D = $CollisionShape2D.shape

var actor_id :int
var actor_name : String
var start_x: float
var start_y: float
var start_rad: float
var speed: float
var is_player: bool

var velocity: Vector2
var radius: float:
	set(new_radius):
		radius = new_radius
		_collision_shape.radius = new_radius
		queue_redraw()

#Constructor for the class
static func instantiate(actor_id: int, actor_name: String, x: float, y: float, radius: float, speed: float, is_player: bool) -> Actor:
	var actor := Scene.instantiate()
	actor.actor_id = actor_id
	actor.actor_name = actor_name
	actor.start_x = x
	actor.start_y = y
	actor.start_rad = radius
	actor.speed = speed
	actor.is_player = is_player
	
	return actor

func _ready() -> void:
	position.x = start_x
	position.y = start_y
	velocity = Vector2.RIGHT * speed
	radius = start_rad
	
	_collision_shape.radius = radius
	_nameplate.text = actor_name
	
#Zooming in and out:
func _input(event: InputEvent) -> void:
	if is_player and event is InputEventMouseButton and event.is_pressed():
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom.x = min(4, _camera.zoom.x + 0.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom.x = max(0.1, _camera.zoom.x - 0.1)
		
		_camera.zoom.y = _camera.zoom.x
	
func _physics_process(delta: float) -> void:
	position += velocity * delta
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
	if abs(velocity.angle_to(input_vec)) > TAU / 15: #12 degrees
		velocity = input_vec * speed
		var packet := packets.Packet.new()
		var player_direction_message := packet.new_player_direction()
		player_direction_message.set_direction(velocity.angle())
		WS.send(packet)
		
#drawing the player blob
func _draw() -> void:
	draw_circle(Vector2.ZERO, _collision_shape.radius, Color.BURLYWOOD)
