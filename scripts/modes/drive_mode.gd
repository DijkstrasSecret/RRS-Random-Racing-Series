extends Node3D
## A drivable scene: free roam on the test track, or laps on a circuit.
## If the track can give a spawn point (Circuit), the car starts there.
## F2 switches to `other_scene`, F3 starts two-player split screen,
## Esc / Start opens the pause menu.

@export_file("*.tscn") var other_scene: String
@export var track_path: NodePath
@export var vehicle_path: NodePath
@export_file("*.tscn") var versus_scene: String = "res://scenes/modes/versus_race.tscn"


func _enter_tree() -> void:
	InputActions.ensure()
	GameSettings.ensure_loaded()
	# Before the car is ready: make it the car chosen in the garage.
	var car := get_node_or_null(vehicle_path) as Vehicle
	if car:
		CarRoster.apply(car, GameSettings.p1_car)


func _ready() -> void:
	add_child(PauseMenu.new())
	MusicPlayer.start_race()
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	print("RRS %s | Godot %s | physics: %s @ %d Hz" % [
		name, Engine.get_version_info().string, engine_name, Engine.physics_ticks_per_second])
	var track := get_node_or_null(track_path)
	var car := get_node_or_null(vehicle_path) as Vehicle
	var has_race := get_tree().get_first_node_in_group("race_setup") != null
	if track and car and track.has_method("get_spawn_transform") and not has_race:
		var xf: Transform3D = track.get_spawn_transform()
		car.spawn_transform = xf
		car.teleport(xf)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_track") and not other_scene.is_empty():
		get_tree().change_scene_to_file(other_scene)
	elif event.is_action_pressed("versus_mode") and not versus_scene.is_empty():
		get_tree().change_scene_to_file(versus_scene)
