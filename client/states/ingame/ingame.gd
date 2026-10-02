extends Node

const packets := preload("res://packets.gd")

const Actor := preload("res://objects/actor/actor.gd")
const Spore := preload("res://objects/spore/spore.gd")
const MapBorder := preload("res://objects/map_border/map_border.gd")
const Virus := preload("res://objects/virus/virus.gd")

## Holding W throws mass this often (the server allows one throw per 90 ms).
const FEED_REPEAT := 0.1
## Must match feedMinRadius on the server: smaller blobs can't feed.
const FEED_MIN_RADIUS := 35.0
## How often to look again for spores the player is already touching but couldn't
## eat when it first touched them (still flying, or its own burst spores).
const RECHECK_SPORES_EVERY := 0.1

@onready var _logout_button: Button = $UI/HUD/LogoutButton
@onready var _line_edit: LineEdit = $UI/HUD/Chat/LineEdit
@onready var _log: Log = $UI/HUD/Chat/Log
@onready var _hiscores: Hiscores = $UI/HUD/Hiscores
@onready var _minimap: Minimap = $UI/HUD/Minimap
@onready var _world: Node2D = $World

var _players: Dictionary[int, Actor]
var _spores: Dictionary[int, Spore]
var _viruses: Dictionary[int, Virus]
var _feed_timer := 0.0
var _recheck_timer := 0.0

func _ready() -> void:
	_world.add_child(MapBorder.new()) # drawn over the floor, under spores and players
	WS.connection_closed.connect(_on_ws_connection_closed)
	WS.packet_received.connect(_on_ws_packet_received)
	
	_logout_button.pressed.connect(_on_logout_button_pressed)
	_line_edit.text_submitted.connect(_on_line_edit_text_submitted)
	_line_edit.gui_input.connect(_on_line_edit_gui_input)
	_minimap.players = _players
	_minimap.viruses = _viruses
	_minimap.my_id = GameManager.client_id

# Enter opens the chat box; Enter again sends (see _on_line_edit_text_submitted).
func _unhandled_input(event: InputEvent) -> void:
	var is_enter: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if is_enter and not _line_edit.has_focus():
		_line_edit.grab_focus()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if GameManager.client_id not in _players:
		return
	var player := _players[GameManager.client_id]
	_process_feed(player, delta)

	_recheck_timer -= delta
	if _recheck_timer <= 0.0:
		_recheck_timer = RECHECK_SPORES_EVERY
		for area in player.get_overlapping_areas():
			if area is Spore:
				_consume_spore(area as Spore)

# W throws a bit of mass towards the mouse; holding it keeps throwing.
func _process_feed(player: Actor, delta: float) -> void:
	var holding_w := Input.is_physical_key_pressed(KEY_W) and not _line_edit.has_focus()
	if not holding_w or player.radius < FEED_MIN_RADIUS:
		_feed_timer = 0.0 # so the next press throws straight away
		return
	_feed_timer -= delta
	if _feed_timer > 0.0:
		return
	_feed_timer = FEED_REPEAT
	var packet := packets.Packet.new()
	var feed_msg := packet.new_feed()
	feed_msg.set_direction((_world.get_global_mouse_position() - player.position).angle())
	WS.send(packet)

# Escape closes the chat box without sending.
func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_line_edit.clear()
		_line_edit.release_focus()
		_line_edit.accept_event()

func _handle_chat_msg(sender_id: int, chat_msg: packets.ChatMessage) -> void:
	if sender_id in _players:
		var actor := _players[sender_id]
		_log.chat(actor.actor_name, chat_msg.get_msg())
	
func _handle_player_msg(sender_id: int, player_msg: packets.PlayerMessage) -> void:
	var actor_id := player_msg.get_id()
	var actor_name := player_msg.get_name()
	var x := player_msg.get_x()
	var y := player_msg.get_y()
	var radius := player_msg.get_radius()
	var speed := player_msg.get_speed()
	var color := Color.hex(player_msg.get_color())
	
	var is_player := actor_id == GameManager.client_id
	
	#if id is not in player dictionary
	if actor_id not in _players:
		_add_actor(actor_id, actor_name, x, y, radius, speed, color, is_player)

	else:
		var direction := player_msg.get_direction()
		_update_actor(actor_id, x, y, direction, speed, radius, color, is_player)


func _add_actor(actor_id: int, actor_name: String, x: float, y: float, radius: float, speed: float, color: Color, is_player: bool) -> void:
	var actor := Actor.instantiate(actor_id, actor_name, x, y, radius, speed, color,  is_player)
	_world.add_child(actor)
	actor.z_index = 1
	_set_actor_mass(actor, _rad_to_mass(radius))
	_players[actor_id] = actor
	
	if is_player:
		actor.area_entered.connect(_on_player_area_entered)

func _update_actor(actor_id: int, x: float, y: float, direction: float, speed: float, radius: float, color: Color, is_player: bool) -> void:
	var actor := _players[actor_id]

	# Pick up colour changes too (e.g. a blob that arrived before its colour was set).
	if actor.color != color:
		actor.color = color
		actor.queue_redraw()
	_set_actor_mass(actor, _rad_to_mass(radius))
	#Updating the player coords only if server and client coords 
	#are more than 100px apart
	if actor.position.distance_squared_to(Vector2(x, y)) > 100:
		actor.server_position.x = x
		actor.server_position.y = y
	
	if not is_player:
		actor.velocity = Vector2.from_angle(direction) * speed

func _on_logout_button_pressed() -> void:
	var packet := packets.Packet.new()
	var disconnect_msg := packet.new_disconnect()
	disconnect_msg.set_reason("they logged out")
	WS.send(packet)
	GameManager.set_state(GameManager.State.CONNECTED)

func _on_line_edit_text_submitted(new_text) -> void:
	# Enter sends and closes the chat box, so the keyboard goes back to the game.
	_line_edit.release_focus()
	if new_text.strip_edges().is_empty():
		_line_edit.clear()
		return
	var packet := packets.Packet.new()
	var chat_msg := packet.new_chat()
	chat_msg.set_msg(new_text)
	
	var err := WS.send(packet)
	if err:
		_log.error("Error sending chat message")
	else:
		_log.chat("You", new_text)
	_line_edit.clear()

func _on_ws_connection_closed() -> void:
	_log.warning("Connection closed")

func _on_ws_packet_received(packet: packets.Packet) -> void:
	var sender_id := packet.get_sender_id()
	if packet.has_chat():
		_handle_chat_msg(sender_id, packet.get_chat())
	elif packet.has_player():
		_handle_player_msg(sender_id, packet.get_player())
	elif packet.has_spore():
		_handle_spore_msg(sender_id, packet.get_spore())
	elif packet.has_spores_batch():
		_handle_spores_batch_msg(sender_id, packet.get_spores_batch())
	elif packet.has_spore_consumed():
		_handle_spore_consumed_msg(sender_id, packet.get_spore_consumed())
	elif packet.has_virus():
		_handle_virus_msg(packet.get_virus())
	elif packet.has_viruses_batch():
		for virus_msg in packet.get_viruses_batch().get_viruses():
			_handle_virus_msg(virus_msg)
	elif packet.has_virus_consumed():
		_handle_virus_consumed_msg(packet.get_virus_consumed())
	elif packet.has_disconnect():
		_handle_disconnect_msg(sender_id, packet.get_disconnect())

func _handle_spore_msg(sender_id: int, spore_msg: packets.SporeMessage) -> void:
	var spore_id := spore_msg.get_id()
	var x := spore_msg.get_x()
	var y := spore_msg.get_y()
	var radius := spore_msg.get_radius()
	
	# Only a spore our own blob just dropped under itself waits until we move off it
	# (the server would reject eating it straight back). Spores thrown or burst by
	# anyone are edible as soon as they land, even if they land under us.
	var underneath_player := false
	if sender_id == GameManager.client_id and not spore_msg.get_ejected() and GameManager.client_id in _players:
		var player := _players[GameManager.client_id]
		var player_pos := Vector2(player.position.x, player.position.y)
		var spore_pos := Vector2(x, y)
		underneath_player = player_pos.distance_squared_to(spore_pos) < player.radius * player.radius
	
	if spore_id not in _spores:
		var spore := Spore.instantiate(spore_id, x, y, radius, underneath_player)
		if spore_msg.get_ejected():
			spore.ejected = true
			spore.from_position = Vector2(spore_msg.get_from_x(), spore_msg.get_from_y())
		var owner_id := spore_msg.get_owner_id()
		if owner_id != 0:
			spore.owner_id = owner_id
			spore.lock_until_msec = Time.get_ticks_msec() + int(spore_msg.get_lock_seconds() * 1000.0)
			# Thrown and burst mass keeps the colour of the blob it came from.
			if owner_id in _players:
				spore.color = _players[owner_id].color
		_world.add_child(spore)
		_spores[spore_id] =  spore

func _handle_spores_batch_msg(sender_id: int, spores_batch_msg: packets.SporesBatchMessage) -> void:
	for spore_msg in spores_batch_msg.get_spores():
		_handle_spore_msg(sender_id, spore_msg)

func _handle_spore_consumed_msg(sender_id: int, spore_consumed_msg: packets.SporeConsumedMessage) -> void:
	#everything has already been verified on the server side so we'll simply update
	if sender_id in _players:
		var actor := _players[sender_id]
		var actor_mass := _rad_to_mass(actor.radius)
		
		var spore_id := spore_consumed_msg.get_spore_id()
		if spore_id in _spores:
			var spore := _spores[spore_id]
			var spore_mass := _rad_to_mass(spore.radius)
			
			_set_actor_mass(actor, actor_mass + spore_mass)
			_remove_spore(spore)

func _handle_virus_msg(virus_msg: packets.VirusMessage) -> void:
	var virus_id := virus_msg.get_id()
	if virus_id in _viruses:
		_viruses[virus_id].update_from_server(virus_msg.get_x(), virus_msg.get_y(), virus_msg.get_radius())
	else:
		var virus := Virus.instantiate(virus_id, virus_msg.get_x(), virus_msg.get_y(), virus_msg.get_radius())
		_world.add_child(virus)
		_viruses[virus_id] = virus

# A virus burst a blob. The blob's new size and its spores arrive separately.
func _handle_virus_consumed_msg(virus_consumed_msg: packets.VirusConsumedMessage) -> void:
	var virus_id := virus_consumed_msg.get_virus_id()
	if virus_id in _viruses:
		_viruses[virus_id].queue_free()
		_viruses.erase(virus_id)

func _handle_disconnect_msg(sender_id: int, disconnect_msg: packets.DisconnectMessage) -> void:
	if sender_id in _players:
		var actor := _players[sender_id]
		var reason := disconnect_msg.get_reason()
		_log.info("%s disconnected because %s" % [actor.actor_name, reason])
		_remove_actor(actor)

func _rad_to_mass(radius: float) -> float:
	return radius * radius * PI

func _on_player_area_entered(area: Area2D) -> void:
	if area is Spore:
		_consume_spore(area as Spore)
	elif area is Actor:
		_collide_actor(area as Actor)

func _set_actor_mass(actor: Actor, new_mass: float) -> void:
	actor.radius = sqrt(new_mass / PI)
	# Like Agar.io: blobs small enough to hide under a virus are drawn below it,
	# blobs big enough to burst on one are drawn above it.
	actor.z_index = 3 if actor.radius > Virus.RADIUS * Virus.POP_RATIO else 1
	_hiscores.set_hiscore(actor.actor_name, roundi(new_mass))

func _consume_spore(spore: Spore) -> void:
	if spore.spore_id not in _spores or not spore.can_be_eaten_by(GameManager.client_id):
		return
	
	var packet := packets.Packet.new()
	var spore_consumed_msg := packet.new_spore_consumed()
	spore_consumed_msg.set_spore_id(spore.spore_id)
	WS.send(packet)
	_remove_spore(spore)

func _collide_actor(actor: Actor) -> void:
	var player := _players[GameManager.client_id]
	var player_mass := _rad_to_mass(player.radius)
	var actor_mass := _rad_to_mass(actor.radius)
	
	#If our mass is 150% more than the other player's mass, we consume on collision
	if player_mass > actor_mass * 1.5:
		_consume_actor(actor)

func _consume_actor(actor: Actor) -> void:
	var player := _players[GameManager.client_id]
	var player_mass := _rad_to_mass(player.radius)
	var actor_mass := _rad_to_mass(actor.radius)
	_set_actor_mass(player, player_mass + actor_mass)
	
	var packet := packets.Packet.new()
	var player_consumed_msg := packet.new_player_consumed()
	player_consumed_msg.set_player_id(actor.actor_id)
	WS.send(packet)
	
	_remove_actor(actor)

func _remove_spore(spore: Spore) -> void:
	_spores.erase(spore.spore_id)
	spore.queue_free()

func _remove_actor(actor: Actor) -> void:
	_players.erase(actor.actor_id)
	actor.queue_free()
	_hiscores.remove_hiscore(actor.actor_name)
