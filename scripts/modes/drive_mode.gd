extends Node3D
## A drivable scene: free roam on the test track, or laps on a circuit.
## If the track can give a spawn point (Circuit), the car starts there.
## F2 switches to `other_scene`, Esc quits.

@export_file("*.tscn") var other_scene: String
@export var track_path: NodePath
@export var vehicle_path: NodePath


func _enter_tree() -> void:
	InputActions.ensure()


func _ready() -> void:
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	print("RRS %s | Godot %s | physics: %s @ %d Hz" % [
		name, Engine.get_version_info().string, engine_name, Engine.physics_ticks_per_second])
	var track := get_node_or_null(track_path)
	var car := get_node_or_null(vehicle_path) as Vehicle
	if track and car and track.has_method("get_spawn_transform"):
		var xf: Transform3D = track.get_spawn_transform()
		car.spawn_transform = xf
		car.teleport(xf)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("switch_track") and not other_scene.is_empty():
		get_tree().change_scene_to_file(other_scene)
