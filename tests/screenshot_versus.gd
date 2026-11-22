extends Node
## Saves screenshots of the versus race (AI drivers) without any user input.
## Used for visual checks. Run windowed with an override.cfg containing
## window/size/no_focus=true so the game window never takes the keyboard.

const OUT := "user://screenshots"  
var _scene: Node
var _race: RaceDirector
var _t := 0.0
var _shots := {1.6: "vs_countdown", 9.0: "vs_racing", 20.0: "vs_racing2"}
var _dirt_shot := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_scene = load("res://scenes/modes/versus_race.tscn").instantiate()
	_race = _scene.get_node("RaceLayer/RaceDirector")
	for car_name: String in ["Car1", "Car2"]:
		var car: Vehicle = _scene.get_node(car_name)
		var player := car.get_node("PlayerInput")
		car.remove_child(player)
		player.free()
		var ai := AIDriver.new()
		if car_name == "Car2":
			ai.cornering_g = 0.95  # too brave: will run onto the grass
		car.add_child(ai)
	add_child(_scene)


func _process(delta: float) -> void:
	_t += delta
	for at: float in _shots.keys():
		if _t >= at:
			_save(_shots[at])
			_shots.erase(at)
	if not _dirt_shot:
		for car_name: String in ["Car1", "Car2"]:
			var car: Vehicle = _scene.get_node(car_name)
			if car.off_track and absf(car.forward_speed) > 12.0:
				_dirt_shot = true
				_save_later("vs_dirt")
	if _t > 60.0 or (_shots.is_empty() and _dirt_shot and _t > 22.0):
		get_tree().quit()


func _save_later(file: String) -> void:
	await get_tree().create_timer(0.35).timeout
	_save(file)


func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, file])
	print("saved ", file, " at ", snappedf(_t, 0.1))
