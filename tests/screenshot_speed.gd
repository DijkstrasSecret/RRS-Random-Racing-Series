extends SceneTree
## Speed effects and fisheye compared: the player's car (AI driving) is put
## on Monza's main straight at 230 km/h for each setting and shot 1.5 s later.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_speed.gd

const OUT := "user://screenshots"
const SETS := [[0.0, 0.0, "fov_static"], [100.0, 0.0, "speed_fov_100"], [100.0, 35.0, "fisheye_35"], [100.0, 100.0, "fisheye_100"]]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.track = "monza"
	GameSettings.time_of_day = 1
	GameSettings.p1_car = "ashford"
	GameSettings.damage = 0
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	var ai := AIDriver.new()
	ai.skill = 0.9
	car.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	await _wait(2.0)
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	for s: Array in SETS:
		GameSettings.speed_fov = s[0]
		GameSettings.speed_fx = s[0] > 0.0
		GameSettings.fisheye = s[1]
		var off := 40.0
		var dir := circuit.direction_at(off)
		car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), circuit.point_at(off) + Vector3.UP * 0.4))
		car.linear_velocity = dir * 64.0
		_force_player_fx(scene, car)
		await _wait(1.5)
		await _save("speedfx_" + s[2])
	quit()


## The retro screen reads the player's car from its input type; in this test
## the AI drives, so point the effect at the car directly.
func _force_player_fx(scene: Node, car: Vehicle) -> void:
	var look := scene.find_children("*", "RetroLook", true, false)
	if look.is_empty():
		return
	(look[0] as RetroLook).forced_car = car


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
