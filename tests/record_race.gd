extends SceneTree
## Films a whole AI race like a TV broadcast, for watching (or cutting a
## trailer from): a grid fly-by in the countdown, then chase, trackside,
## blimp, close and battle cameras, with a timing tower and lap counter,
## and the results at the end. Use with Godot's movie maker, windowed
## (override.cfg with window/size/no_focus=true):
##   Godot.exe --path . --write-movie race.avi --fixed-fps 30 -s res://tests/record_race.gd -- --track=daytona --laps=5
## Options: --track, --laps, --ai=9 (at most 9 names), --tiers=8 (car classes), --car=cup_camaro
## (the featured car, driven by the AI), --seconds=N (stop early), --no-overlay,
## --shot=chase|trackside|blimp|close|battle (one camera only), --time=1.

const SHOT_LEN := 5.5

var _cam: Camera3D
var _race: RaceDirector
var _circuit: Circuit
var _featured: Vehicle
var _shot := ""
var _shot_start := -99.0
var _shot_focus: Vehicle
var _fixed_pos := Vector3.ZERO
var _tower: Label
var _lap: Label
var _caption: Label
var _results: Label


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var track := "daytona"
	var laps := 5
	var ai_count := 9
	var tiers := 8
	var car := "cup_camaro"
	var seconds := 9999.0
	var overlay := true
	var only := ""
	var time_of_day := 1
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--track="): track = v
		elif arg.begins_with("--laps="): laps = int(v)
		elif arg.begins_with("--ai="): ai_count = int(v)
		elif arg.begins_with("--tiers="): tiers = int(v)
		elif arg.begins_with("--car="): car = v
		elif arg.begins_with("--seconds="): seconds = float(v)
		elif arg.begins_with("--shot="): only = v
		elif arg.begins_with("--time="): time_of_day = int(v)
		elif arg == "--no-overlay": overlay = false
	GameSettings.track = track
	GameSettings.laps = laps
	GameSettings.ai_count = ai_count
	GameSettings.ai_tiers = tiers
	GameSettings.ai_difficulty = 2
	GameSettings.p1_car = car
	GameSettings.time_of_day = time_of_day
	GameSettings.weather = 0
	var scene := (load("res://scenes/modes/circuit_race.tscn") as PackedScene).instantiate()
	for node in scene.get_children():
		if node is Vehicle and node.get_node_or_null("PlayerInput"):
			var player := node.get_node("PlayerInput")
			node.remove_child(player)
			player.free()
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.skill = 0.95
			DriverStyle.apply(ai, "KATO")
			node.add_child(ai)
			_featured = node
	root.add_child(scene)
	current_scene = scene
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		if not (layer is RetroLook):
			(layer as CanvasLayer).visible = false
	_race = scene.find_children("*", "RaceDirector", true, false)[0] as RaceDirector
	_circuit = scene.find_children("*", "Circuit", true, false)[0] as Circuit
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 3000.0
	scene.add_child(_cam)
	_cam.make_current()
	if overlay:
		_build_overlay(scene)
	var frames := 0
	var finished_at := -1.0
	while frames < int(seconds * 30.0):
		await process_frame
		frames += 1
		if _race.car_count() == 0:
			continue
		# Keep our camera current (the race's chase cameras may grab it).
		if not _cam.current:
			_cam.make_current()
		_direct(only)
		if overlay:
			_update_overlay(track)
		if _race.finish_order.size() > 0 and finished_at < 0.0:
			finished_at = _race.race_time
		# A few seconds after the winner, while the rest come home, then stop.
		if finished_at > 0.0 and _race.race_time > finished_at + 9.0:
			break
	quit()


# --- camera director -----------------------------------------------------------

func _direct(only: String) -> void:
	var t := _race.race_time
	var order := _race.standings()
	var leader := _race.vehicle_at(order[0])
	if _race.state == RaceDirector.State.COUNTDOWN or t < 0.5:
		_grid_flyby()
		return
	var last_lap := _race.completed_laps(order[0]) >= _race.laps - 1
	var to_line := fposmod(_circuit.length - _circuit.progress_at(leader.global_position), _circuit.length)
	if (last_lap and to_line < 260.0) or not _race.finish_order.is_empty():
		_finish_line(leader)
		return
	if t - _shot_start > SHOT_LEN or _shot == "" or _shot == "grid" or _shot == "finish":
		_next_shot(order, only)
	var focus := _shot_focus if is_instance_valid(_shot_focus) else leader
	var xf := focus.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var fresh := t - _shot_start < 0.05
	match _shot:
		"chase":
			var want := xf.origin - fwd * 8.5 + Vector3.UP * 2.9
			_cam.global_position = want if fresh else _cam.global_position.lerp(want, 0.3)
			_cam.look_at(xf.origin + fwd * 7.0 + Vector3.UP * 0.8, Vector3.UP)
			_cam.fov = 62.0
		"battle":
			var want := xf.origin - fwd * 13.0 + right * 2.5 + Vector3.UP * 3.6
			_cam.global_position = want if fresh else _cam.global_position.lerp(want, 0.25)
			_cam.look_at(xf.origin + fwd * 14.0 + Vector3.UP * 0.5, Vector3.UP)
			_cam.fov = 55.0
		"close":
			# Close behind the car, low: the game's CLOSE view.
			var want := xf.origin - fwd * 5.2 + Vector3.UP * 2.0
			_cam.global_position = want if fresh else _cam.global_position.lerp(want, 0.35)
			_cam.look_at(xf.origin + fwd * 8.0 + Vector3.UP * 0.8, Vector3.UP)
			_cam.fov = 66.0
		"blimp":
			var want := xf.origin + right * -60.0 + Vector3.UP * 55.0 - fwd * 20.0
			_cam.global_position = want if fresh else _cam.global_position.lerp(want, 0.08)
			_cam.look_at(xf.origin + fwd * 25.0, Vector3.UP)
			_cam.fov = 45.0
		"trackside":
			if fresh:
				var off := _circuit.progress_at(xf.origin) + maxf(focus.forward_speed, 20.0) * 2.6
				var side := 1.0 if _circuit.curvature_at(off) <= 0.0 else -1.0  # outside of the bend
				if _circuit.oval:
					side = -1.0 if _circuit.infield_side() == 0 else 1.0  # in the infield, looking up the banking
				_fixed_pos = _circuit.point_at(off) + _circuit.right_at(off) * side * (16.0 if _circuit.oval else 13.0)
				_fixed_pos.y = _circuit.surface_height(_fixed_pos.x, _fixed_pos.z) + (3.0 if _circuit.oval else 2.2)
			_cam.global_position = _fixed_pos
			_cam.look_at(xf.origin + Vector3.UP * 0.8, Vector3.UP)
			_cam.fov = clampf(30.0 + _fixed_pos.distance_to(xf.origin) * 0.25, 30.0, 60.0)


func _next_shot(order: Array[int], only: String) -> void:
	var cycle := ["chase", "trackside", "battle", "blimp", "trackside", "close", "chase", "battle"]
	var k := int(_race.race_time / SHOT_LEN) % cycle.size()
	_shot = only if only != "" else String(cycle[k])
	_shot_start = _race.race_time
	match _shot:
		"chase", "close":
			# Mostly the featured car, sometimes the leader.
			_shot_focus = _featured if k % 2 == 0 else _race.vehicle_at(order[0])
		"battle":
			# The closest fight in the top half of the field.
			var best := 1
			var gap := 1e9
			for i in range(1, maxi(order.size() / 2, 2)):
				var g := _race._race_distance(order[i - 1]) - _race._race_distance(order[i])
				if g < gap:
					gap = g
					best = i
			_shot_focus = _race.vehicle_at(order[best])
		_:
			_shot_focus = _race.vehicle_at(order[0])


func _grid_flyby() -> void:
	_shot = "grid"
	_shot_start = _race.race_time
	var u := clampf((3.5 - _countdown_left()) / 3.5, 0.0, 1.0)
	var line := _circuit.point_at(0.0)
	var back := _circuit.point_at(_circuit.length - 110.0)
	var side := _circuit.right_at(_circuit.length - 50.0) * (-1.0 if _circuit.infield_side() == 0 else 1.0)
	var from := line + side * 16.0 + Vector3.UP * 14.0
	var to := back + side * 9.0 + Vector3.UP * 4.0
	_cam.global_position = from.lerp(to, u * u * (3.0 - 2.0 * u))
	_cam.look_at(_circuit.point_at(_circuit.length - 40.0) + Vector3.UP, Vector3.UP)
	_cam.fov = 55.0


func _countdown_left() -> float:
	return float(_race.get("_countdown"))


func _finish_line(leader: Vehicle) -> void:
	if _shot != "finish":
		_shot = "finish"
		_shot_start = _race.race_time
		var side := -1.0 if _circuit.infield_side() == 0 else 1.0  # infield side, by the pit wall
		_fixed_pos = _circuit.point_at(8.0) + _circuit.right_at(8.0) * side * 10.0
		_fixed_pos.y = _circuit.surface_height(_fixed_pos.x, _fixed_pos.z) + 1.6
	_cam.global_position = _fixed_pos
	var watch := leader
	if not _race.finish_order.is_empty():
		# After the winner: the next car still to come home.
		for i in _race.standings():
			if not i in _race.finish_order:
				watch = _race.vehicle_at(i)
				break
	_cam.look_at(watch.global_position + Vector3.UP * 0.8, Vector3.UP)
	_cam.fov = clampf(20.0 + _fixed_pos.distance_to(watch.global_position) * 0.2, 20.0, 55.0)


# --- overlay -----------------------------------------------------------------------

func _build_overlay(scene: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120  # over the retro screen effect
	scene.add_child(layer)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_tower = _make_label(layer, Vector2(110, 70), 26, font)
	_lap = _make_label(layer, Vector2(0, 70), 40, null)
	_lap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lap.anchor_left = 1.0
	_lap.anchor_right = 1.0
	_lap.offset_left = -420
	_lap.offset_right = -110
	_caption = _make_label(layer, Vector2(110, 0), 30, null)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -130
	_results = _make_label(layer, Vector2(0, 0), 30, font)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_results.visible = false


func _make_label(layer: CanvasLayer, pos: Vector2, size: int, font: Font) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	if font:
		l.add_theme_font_override("font", font)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.04, 0.07, 0.62)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	l.add_theme_stylebox_override("normal", panel)
	layer.add_child(l)
	return l


func _update_overlay(track: String) -> void:
	var order := _race.standings()
	var lines: PackedStringArray = []
	for p in mini(order.size(), 10):
		var i: int = order[p]
		var car := _race.vehicle_at(i)
		var mark := ">" if car == _featured else " "
		lines.append("%s%2d %-7s %s" % [mark, p + 1, _race.name_at(i).trim_prefix("AI_"), CarRoster.short_name(String(car.get_meta(&"car_id", "?")))])
	_tower.text = "\n".join(lines)
	var lap := clampi(_race.current_lap(order[0]), 1, _race.laps)
	_lap.text = "LAP %d / %d" % [lap, _race.laps] if _race.state != RaceDirector.State.COUNTDOWN else "GET READY"
	if _race.completed_laps(order[0]) == _race.laps - 1 and _race.finish_order.is_empty():
		_lap.text = "FINAL LAP"
	_caption.text = "%s  ·  %s" % [TrackList.display_name(track).to_upper(), _shot_title()]
	if not _race.finish_order.is_empty() and _race.race_time > float(_race.finish_times[_race.finish_order[0]]) + 3.0:
		_tower.visible = false
		var res: PackedStringArray = ["  RESULT", ""]
		for p in mini(order.size(), 10):
			var i: int = order[p]
			var t := LapTimer.format_time(_race.finish_times[i]) if _race.finish_times.has(i) else "running"
			res.append("%2d  %-7s %-12s %s" % [p + 1, _race.name_at(i).trim_prefix("AI_"), CarRoster.short_name(String(_race.vehicle_at(i).get_meta(&"car_id", "?"))), t])
		_results.text = "\n".join(res)
		_results.visible = true
		_results.position = Vector2(-330, -200)


func _shot_title() -> String:
	match _shot:
		"blimp": return "BLIMP"
		"finish": return "FINISH LINE"
		"grid": return "THE GRID"
	if is_instance_valid(_shot_focus):
		var i := _race.index_of(_shot_focus)
		if i >= 0:
			return "%s  P%d" % [_race.name_at(i).trim_prefix("AI_"), _race.position_of(i)]
	return ""
