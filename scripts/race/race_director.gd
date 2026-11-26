class_name RaceDirector
extends Control
## Runs a race (design concept §14.2): countdown with the cars held still,
## live positions, lap count, finish order and the results screen.
## Racers are added with add_racer() (RaceSetup does this) or listed in
## vehicle_paths / lap_timer_paths. Backspace restarts the race.
## Draws its own overlay, so put it full-screen in a CanvasLayer above the HUDs.

enum State { WAITING, COUNTDOWN, RACING, FINISHED }

## Race length in laps. Replaced by the player's setting when use_game_settings is on.
@export var laps: int = 3
## Length of the start countdown, in seconds.
@export var countdown_time: float = 3.0
## The Circuit the race runs on.
@export var circuit_path: NodePath
## Start the countdown by itself (off when a RaceSetup adds the racers).
@export var auto_start: bool = true
## Take the number of laps from the player's settings.
@export var use_game_settings: bool = true
## Human cars placed in the scene, added as racers in _ready. Pairs with lap_timer_paths by index.
@export var vehicle_paths: Array[NodePath] = []
## The LapTimer of each car in vehicle_paths, same order.
@export var lap_timer_paths: Array[NodePath] = []
## Names for the cars in vehicle_paths; missing entries become "PLAYER n".
@export var player_names: PackedStringArray = ["PLAYER 1", "PLAYER 2"]
## Colours for the cars in vehicle_paths; missing entries are white.
@export var player_colors: PackedColorArray = [Color(0.35, 0.8, 1.0), Color(1.0, 0.4, 0.35)]

var state: int = State.WAITING
var race_time: float = 0.0
## Indices of the racers in the order they crossed the finish line.
var finish_order: Array[int] = []
var finish_times: Dictionary = {}
## Tournament: cars out of the race (stuck / upside down / a wheel off, no
## recovery), in the order they dropped out.
var retired: Array[int] = []
const DNF_UPSIDE_DOWN := 5.0
const DNF_STUCK := 8.0
var _wreck_time: Dictionary = {}  ## racer -> [upside down s, stuck s, wheel off s]

## One entry per racer: {vehicle, timer, name, color, human}.
var _racers: Array[Dictionary] = []
var _circuit: Circuit
var _countdown: float = 0.0
var _go_flash: float = 0.0
var _font: Font
var _tournament_wait := 0.0
var _tournament_done := false


func _ready() -> void:
	add_to_group("race_director")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_circuit = get_node_or_null(circuit_path) as Circuit
	if use_game_settings:
		GameSettings.ensure_loaded()
		laps = GameSettings.laps
	if Tournament.active:
		laps = Tournament.current_laps()
	for i in vehicle_paths.size():
		add_racer(get_node(vehicle_paths[i]) as Vehicle, get_node(lap_timer_paths[i]) as LapTimer,
				player_names[i] if i < player_names.size() else "PLAYER %d" % (i + 1),
				player_colors[i] if i < player_colors.size() else Color.WHITE, true)
	if auto_start:
		begin.call_deferred()


## Adds a racer and locks its controls until the countdown ends. The racer's index (0, 1, …) is its order of adding.
func add_racer(vehicle: Vehicle, timer: LapTimer, racer_name: String, color: Color, human: bool) -> void:
	_racers.append({"vehicle": vehicle, "timer": timer, "name": racer_name, "color": color, "human": human})
	vehicle.controls_locked = true


## Start the countdown.
func begin() -> void:
	state = State.COUNTDOWN
	_countdown = countdown_time + 0.5
	for r in _racers:
		r.vehicle.controls_locked = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not Tournament.active:
		get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				state = State.RACING
				_go_flash = 1.2
				for r in _racers:
					r.vehicle.controls_locked = false
		State.RACING:
			race_time += delta
			if Tournament.active:
				_watch_wrecks(delta)
			for i in _racers.size():
				if i in finish_order or i in retired:
					continue
				if completed_laps(i) >= laps:
					finish_order.append(i)
					finish_times[i] = race_time
			# The race is over once every human has finished.
			var humans_left := false
			for i in _racers.size():
				if _racers[i].human and not (i in finish_order) and not (i in retired):
					humans_left = true
			if not humans_left:
				state = State.FINISHED
		State.FINISHED:
			race_time += delta
			if Tournament.active:
				_watch_wrecks(delta)
			for i in _racers.size():
				if not (i in finish_order) and not (i in retired) and completed_laps(i) >= laps:
					finish_order.append(i)
					finish_times[i] = race_time
	_go_flash = maxf(_go_flash - delta, 0.0)
	# Tournament: a few seconds on the results, then the shop / podium.
	if Tournament.active and state == State.FINISHED:
		_tournament_wait += delta
		if _tournament_wait > 5.0 and not _tournament_done:
			_tournament_done = true
			Tournament.record(self)
			get_tree().change_scene_to_file.call_deferred(Tournament.SHOP_SCENE)


func _process(_delta: float) -> void:
	queue_redraw()


## True if racer i is out of the race (tournament wreck rule).
func is_retired(i: int) -> bool:
	return i in retired


## No recovery in a tournament: 5 s upside down, or 8 s stuck or with a
## wheel off, and the car is out of the race.
func _watch_wrecks(delta: float) -> void:
	if race_time < 3.0:
		return
	for i in _racers.size():
		if i in finish_order or i in retired:
			continue
		var car: Vehicle = _racers[i].vehicle
		var t: Array = _wreck_time.get(i, [0.0, 0.0, 0.0])
		t[0] = t[0] + delta if car.global_basis.y.y < 0.3 else 0.0
		t[1] = t[1] + delta if absf(car.forward_speed) < 1.0 else 0.0
		var wheel_off := false
		for w in car.wheels:
			wheel_off = wheel_off or w.detached
		t[2] = t[2] + delta if wheel_off else 0.0
		_wreck_time[i] = t
		if t[0] > DNF_UPSIDE_DOWN or t[1] > DNF_STUCK or t[2] > DNF_STUCK:
			retire(i)


## Takes racer i out of the race and locks its controls. Does nothing if it already finished or retired.
func retire(i: int) -> void:
	if i in retired or i in finish_order:
		return
	retired.append(i)
	_racers[i].vehicle.controls_locked = true


## What is stopping a car right now (for the HUD's countdown), or "".
func wreck_warning(i: int) -> String:
	var t: Array = _wreck_time.get(i, [0.0, 0.0, 0.0])
	if t[0] > 1.0:
		return "UPSIDE DOWN  ·  OUT IN %d" % ceili(DNF_UPSIDE_DOWN - t[0])
	if t[2] > 1.0:
		return "WHEEL OFF  ·  OUT IN %d" % ceili(DNF_STUCK - t[2])
	if t[1] > 3.0:
		return "STUCK  ·  OUT IN %d" % ceili(DNF_STUCK - t[1])
	return ""


## Number of racers.
func car_count() -> int:
	return _racers.size()


## The car of racer i.
func vehicle_at(i: int) -> Vehicle:
	return _racers[i].vehicle


## The HUD colour of racer i.
func color_at(i: int) -> Color:
	return _racers[i].color


## The display name of racer i.
func name_at(i: int) -> String:
	return _racers[i].name


## The LapTimer of racer i.
func timer_at(i: int) -> LapTimer:
	return _racers[i].timer


## True if racer i is driven by a player, not the AI.
func is_human(i: int) -> bool:
	return bool(_racers[i].human)


## Gap to the car one place ahead, F1 interval style: "+0.842", "+1 LAP",
## "" for the leader (and before the start).
func interval(i: int) -> String:
	var order := standings()
	var at := order.find(i)
	if at <= 0:
		return ""
	if i in finish_order and order[at - 1] in finish_order:
		return "+%.3f" % (float(finish_times[i]) - float(finish_times[order[at - 1]]))
	var mine: LapTimer = _racers[i].timer
	var theirs: LapTimer = _racers[order[at - 1]].timer
	if not mine.running or mine.last_point < 0:
		return ""
	if theirs.last_point - mine.last_point >= LapTimer.TIMING_POINTS:
		return "+%d LAP" % int((theirs.last_point - mine.last_point) / LapTimer.TIMING_POINTS)
	var p := mine.last_point
	if not theirs.points.has(p):
		return ""
	return "+%.3f" % maxf(float(mine.points[p]) - float(theirs.points[p]), 0.0)


## Laps racer i has finished; 0 before it first crosses the line.
func completed_laps(i: int) -> int:
	var t: LapTimer = _racers[i].timer
	return maxi(t.lap - 1, 0) if t.running else 0


## Current lap being driven (1-based, capped at the race length).
func current_lap(i: int) -> int:
	return clampi(completed_laps(i) + 1, 1, laps)


## The racer index of a car, or -1 if it isn't in the race.
func index_of(vehicle: Vehicle) -> int:
	for i in _racers.size():
		if _racers[i].vehicle == vehicle:
			return i
	return -1


## 1 = leading. Finished cars keep their finishing position.
func position_of(i: int) -> int:
	if i in finish_order:
		return finish_order.find(i) + 1
	if i in retired:
		return _racers.size() - retired.find(i)  # first out = last place
	var mine := _race_distance(i)
	var pos := finish_order.size() + 1
	for j in _racers.size():
		if j != i and not (j in finish_order) and not (j in retired) and _race_distance(j) > mine:
			pos += 1
	return pos


## Racer indices sorted by current position.
func standings() -> Array[int]:
	var frame := Engine.get_physics_frames()
	if frame == _order_frame and _order_cache.size() == _racers.size():
		return _order_cache
	_order_frame = frame
	var order: Array[int] = []
	for i in _racers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return position_of(a) < position_of(b))
	_order_cache = order
	return order


## Race distance of every car, measured once per frame (the HUD position
## tower asks for positions and gaps many times a frame).
var _dist_cache := PackedFloat32Array()
var _dist_frame := -1
var _order_cache: Array[int] = []
var _order_frame := -1


func _race_distance(i: int) -> float:
	var frame := Engine.get_physics_frames()
	if frame != _dist_frame or _dist_cache.size() != _racers.size():
		_dist_frame = frame
		_dist_cache.resize(_racers.size())
		for k in _racers.size():
			_dist_cache[k] = _measure_distance(k)
	return _dist_cache[i]


func _measure_distance(i: int) -> float:
	if _circuit == null:
		return 0.0
	var t: LapTimer = _racers[i].timer
	var offset := _circuit.progress_at(_racers[i].vehicle.global_position)
	if not t.running:
		# Still on the grid behind the line.
		return offset - _circuit.length
	return completed_laps(i) * _circuit.length + offset


## Position as shown on screen: 1 → "1ST", 2 → "2ND", 11 → "11TH".
static func ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
	return "%dTH" % n


func _draw() -> void:
	var centre := size * 0.5
	if state == State.COUNTDOWN:
		var n := ceili(_countdown - 0.5)
		if n >= 1 and n <= int(countdown_time):
			_big(centre, str(n), 180, Color(1.0, 0.85, 0.25))
		_big(centre + Vector2(0, 130), "GET READY", 36, Color(1, 1, 1, 0.9))
	elif _go_flash > 0.0:
		_big(centre, "GO!", 180, Color(0.4, 1.0, 0.45, clampf(_go_flash, 0.0, 1.0)))
	if state == State.FINISHED or _any_human_finished():
		_draw_results(centre)


func _any_human_finished() -> bool:
	for i in finish_order:
		if _racers[i].human:
			return true
	return false


func _draw_results(centre: Vector2) -> void:
	var rows := _racers.size()
	var row_h := 34.0
	var panel_h := 150.0 + rows * row_h
	var panel := Rect2(centre - Vector2(360, panel_h * 0.5), Vector2(720, panel_h))
	draw_rect(panel, Color(0, 0, 0, 0.75))
	var top := panel.position.y
	var winner: int = finish_order[0] if not finish_order.is_empty() else standings()[0]
	_big(Vector2(centre.x, top + 40.0), "%s WINS!" % _racers[winner].name, 46, _racers[winner].color)
	var y := top + 92.0
	for i in standings():
		var r := _racers[i]
		var place := position_of(i)
		var time_text := "racing..."
		if i in retired:
			time_text = "DNF"
		elif i in finish_order and finish_times.has(winner):
			time_text = LapTimer.format_time(finish_times[i])
			if place > 1:
				time_text += "  +%.3f" % (finish_times[i] - finish_times[winner])
		var label := "%s  %s" % [ordinal(place), r.name]
		_text_at(Vector2(panel.position.x + 60.0, y), label, 24, r.color)
		_text_at(Vector2(panel.position.x + 400.0, y), time_text, 22, Color(1, 1, 1, 0.9))
		y += row_h
	var footer := "Backspace = race again      Esc / Start = menu"
	if Tournament.active:
		footer = "Tournament podium coming up..." if Tournament.is_final() else "To the upgrade shop in a moment..."
	_big(Vector2(centre.x, panel.end.y - 26.0), footer, 20, Color(1, 1, 1, 0.8))


func _text_at(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _big(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := pos + Vector2(-w * 0.5, font_size * 0.35)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(0, 0, 0, color.a * 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
