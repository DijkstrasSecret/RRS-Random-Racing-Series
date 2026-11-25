extends SceneTree
## Obstacle course views: the start as the player sees it, then a camera
## over each section. Run windowed with an override.cfg containing
## window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_course.gd

const OUT := "user://screenshots"
const VIEWS := [
	["course_village", Vector3(-10, 8, -30), Vector3(0, 1, -95)],
	["course_chicane", Vector3(12, 11, -204), Vector3(0, 4, -240)],
	["course_jump", Vector3(18, 7, -398), Vector3(0, -1, -418)],
	["course_balls", Vector3(10, 5, -452), Vector3(0, 1, -500)],
	["course_bridges", Vector3(96, 9, -572), Vector3(105, -6, -595)],
	["course_hairpins", Vector3(188, 42, -585), Vector3(226, 10, -638)],
	["course_seesaw_lift", Vector3(264, 34, -578), Vector3(248, 20, -556)],
	["course_rollers_turntable", Vector3(263, 19, -505), Vector3(248, 10, -476)],
	["course_loop", Vector3(278, 16, -432), Vector3(253, 17, -404)],
	["course_home", Vector3(60, 12, 66), Vector3(18, 0, 28)],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	GameSettings.time_of_day = 1
	var scene := (load(GameSettings.OBSTACLE_COURSE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _wait(2.5)
	await _save("course_start")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 1500.0
	scene.add_child(cam)
	cam.make_current()
	for v: Array in VIEWS:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		await _wait(0.6)
		await _save(v[0])
	quit()


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < seconds:
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
