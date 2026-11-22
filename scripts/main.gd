extends Node3D
## Placeholder boot scene for milestone M0. Prints the physics setup so we can
## confirm the project is configured correctly. Replaced by the test track in M1.


func _ready() -> void:
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine")
	print("RRS boot OK | Godot %s | physics: %s @ %d Hz" % [
		Engine.get_version_info().string,
		engine_name,
		Engine.physics_ticks_per_second,
	])
