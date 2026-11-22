extends SceneTree
## Records a short race clip for the track select screen: an AI race on the
## chosen track, filmed with a few TV-style cuts (chase cam, low trackside
## shot, high side shot), no HUD, PS1 look. Use with Godot's movie maker:
##   Godot.exe --path . --write-movie clip.avi --fixed-fps 30 -s res://tests/record_clip.gd -- --track=spa
## (windowed, override.cfg with window/size/no_focus=true). The first ~4 s is
## the countdown; the clip ends ~20 s into the race.

const SHOT_LEN := 4.0


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var track := "monza"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.get_slice("=", 1)
	GameSettings.track = track
	GameSettings.ai_tiers = 15
	GameSettings.ai_count = 7
	GameSettings.laps = 3
	GameSettings.time_of_day = 1
	GameSettings.weather = 0
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = 0.8
			node.add_child(ai)
	root.add_child(scene)
	current_scene = scene
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		if not (layer is RetroLook):
			(layer as CanvasLayer).visible = false
	var race := scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	var cam := Camera3D.new()
	cam.fov = 55.0
	scene.add_child(cam)
	cam.make_current()
	var frames := 0
	var shot_pos := Vector3.ZERO
	var last_shot := -1
	while race.race_time < 20.5 and frames < 30 * 40:
		await process_frame
		frames += 1
		if race.car_count() == 0:
			continue
		var order := race.standings()
		var t := race.race_time
		var shot := int(t / SHOT_LEN) % 4 if race.state != RaceDirector.State.COUNTDOWN else 0
		var leader := race.vehicle_at(order[0])
		var pack := race.vehicle_at(order[mini(2, order.size() - 1)])
		var focus := pack if shot == 2 else leader
		var xf := focus.global_transform
		var fwd := -xf.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		match shot:
			0, 2:
				# Chase camera behind the car.
				var want := xf.origin - fwd * 9.0 + Vector3.UP * 3.2
				cam.global_position = cam.global_position.lerp(want, 0.25) if last_shot == shot else want
				cam.look_at(xf.origin + fwd * 6.0 + Vector3.UP * 0.8, Vector3.UP)
			1:
				# Low trackside camera ahead of the leader, panning as the pack passes.
				if last_shot != shot:
					var off := circuit.progress_at(xf.origin) + 40.0
					var side := 1.0 if circuit.curvature_at(off) < 0.0 else -1.0  # outside of the bend
					shot_pos = circuit.point_at(off) + circuit.right_at(off) * side * 9.0
					shot_pos.y = circuit.surface_height(shot_pos.x, shot_pos.z) + 1.6
				cam.global_position = shot_pos
				cam.look_at(xf.origin + Vector3.UP * 0.8, Vector3.UP)
			3:
				# High side view gliding along with the leader.
				var want := xf.origin + right * 26.0 + Vector3.UP * 16.0 - fwd * 6.0
				cam.global_position = cam.global_position.lerp(want, 0.2) if last_shot == shot else want
				cam.look_at(xf.origin + fwd * 8.0, Vector3.UP)
		last_shot = shot
	quit()
