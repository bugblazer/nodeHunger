extends Area2D

const Scene := preload("res://objects/spore/spore.tscn")
const Spore := preload("res://objects/spore/spore.gd")
const Actor := preload("res://objects/actor/actor.gd")

## Seconds a thrown or burst spore takes to fly from its blob to where it lands.
const FLIGHT_TIME := 0.3

@onready var _collision_shape: CircleShape2D = $CollisionShape2D.shape

var spore_id: int
var x: float
var y: float
var radius: float
var color := Color(0, 0, 0, 0) # left transparent = pick a random colour
var underneath_player : bool

## Thrown with W or burst out of a blob by a virus: it flies out from from_position.
var ejected := false
var from_position: Vector2
## The blob it came from can't eat it back until lock_until_msec (Time.get_ticks_msec).
var owner_id := 0
var lock_until_msec := 0

var _flying := false

static func instantiate(spore_id: int, x: float, y: float, radius: float, underneath_player: bool) -> Spore:
	var spore := Scene.instantiate()
	spore.spore_id = spore_id
	spore.x = x
	spore.y = y
	spore.radius = radius
	spore.underneath_player = underneath_player

	return spore

func _ready() -> void:
	if underneath_player:
		area_exited.connect(_on_area_exited)

	position.x = x
	position.y = y
	_collision_shape.radius = radius
	if color.a == 0:
		color = Color.from_hsv(randf(), 1, 1, 1)

	if ejected:
		# Nobody can eat it mid-air: the server only knows where it lands.
		_flying = true
		position = from_position
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", Vector2(x, y), FLIGHT_TIME)
		tween.tween_callback(func(): _flying = false)

## Whether the blob with this id may eat this spore right now.
func can_be_eaten_by(actor_id: int) -> bool:
	if underneath_player or _flying:
		return false
	return not (actor_id == owner_id and Time.get_ticks_msec() < lock_until_msec)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)

func _on_area_exited(area: Area2D) -> void:
	if area is Actor:
		underneath_player = false
