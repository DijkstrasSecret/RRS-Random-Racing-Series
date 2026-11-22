extends Node3D
## Free Roam on the test track: the first playable demo (milestone M1).


func _enter_tree() -> void:
	InputActions.ensure()


func _ready() -> void:
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	print("RRS free roam | Godot %s | physics: %s @ %d Hz" % [
		Engine.get_version_info().string,
		engine_name,
		Engine.physics_ticks_per_second,
	])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
