extends Node3D
## Two-player split-screen race on the circuit: player 1 on top (WASD /
## first gamepad), player 2 below (arrow keys / second gamepad).
## F3 or F2 goes back to single player, Esc / Start opens the pause menu.

@export var circuit_path: NodePath
@export var car_paths: Array[NodePath] = []
@export_file("*.tscn") var single_player_scene: String = "res://scenes/modes/circuit_race.tscn"


func _enter_tree() -> void:
	InputActions.ensure()
	GameSettings.ensure_loaded()
	# Before the cars are ready: each player's garage choice.
	var picks := [GameSettings.p1_car, GameSettings.p2_car]
	for i in mini(car_paths.size(), 2):
		var car := get_node_or_null(car_paths[i]) as Vehicle
		if car:
			# Same car for both players: player 2 gets red paint.
			var paint := Color(0.85, 0.12, 0.1) if i == 1 and picks[0] == picks[1] else Color(0, 0, 0, 0)
			CarRoster.apply(car, picks[i], paint)


func _ready() -> void:
	add_child(PauseMenu.new())
	MusicPlayer.start_race()
	print("RRS %s | Godot %s | %d players" % [name, Engine.get_version_info().string, car_paths.size()])
	var circuit := get_node(circuit_path) as Circuit
	if get_tree().get_first_node_in_group("race_setup"):
		return  # RaceSetup puts everyone on the grid.
	for i in car_paths.size():
		var car := get_node(car_paths[i]) as Vehicle
		var xf := circuit.get_grid_transform(i)
		car.spawn_transform = xf
		car.teleport(xf)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("versus_mode") or event.is_action_pressed("switch_track"):
		get_tree().change_scene_to_file(single_player_scene)
