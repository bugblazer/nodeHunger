extends Node

#A list of states:
enum State {
	ENTERED, #Connecting to the server etc
	CONNECTED, #Login/register state
	INGAME, #In-game logic, chat etc
	BROWSING_HISCORES, #for the all-time leaderboard browsing
}

#Creating a dictionary that will hold scenes related to different states
var _states_scenes: Dictionary[State, String] = {
	State.ENTERED: "res://states/entered/entered.tscn",
	State.CONNECTED: "res://states/connected/connected.tscn",
	State.INGAME: "res://states/ingame/ingame.tscn",
	State.BROWSING_HISCORES: "res://states/browsing_hiscores/browsing_hiscores.tscn",
}

var client_id: int
var _current_scene_root: Node

#Sets the scene according to the state and deletes the previous one from queue
func set_state(state: State) -> void:
	if _current_scene_root != null:
		_current_scene_root.queue_free()
		
	#Grabs the path from the enum and loads it
	var scene: PackedScene = load(_states_scenes[state])
	_current_scene_root = scene.instantiate()
	add_child(_current_scene_root)
	
