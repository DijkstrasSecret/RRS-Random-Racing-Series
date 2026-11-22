extends Node3D
## Two-player split-screen race on the circuit: player 1 on top (WASD /
## first gamepad), player 2 below (arrow keys / second gamepad).
## F3 or F2 goes back to single player, Esc quits.

@export var circuit_path: NodePath
@export var car_paths: Array[NodePath] = []
@export_file("*.tscn") var single_player_scene: String = "res://scenes/modes/circuit_race.tscn"


func _enter_tree() -> void:
	InputActions.ensure()


func _ready() -> void:
	print("RRS %s | Godot %s | %d players" % [name, Engine.get_version_info().string, car_paths.size()])
	var circuit := get_node(circuit_path) as Circuit
	for i in car_paths.size():
		var car := get_node(car_paths[i]) as Vehicle
		var xf := circuit.get_grid_transform(i)
		car.spawn_transform = xf
		car.teleport(xf)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("versus_mode") or event.is_action_pressed("switch_track"):
		get_tree().change_scene_to_file(single_player_scene)
