class_name RaceDirector
extends Control
## Runs a race between several cars (design concept §14.2): countdown with
## the cars held still, live positions, lap count, finish order and the
## results screen. Backspace restarts the race. Draws its own overlay, so put
## it full-screen in a CanvasLayer above the HUDs.

enum State { COUNTDOWN, RACING, FINISHED }

@export var laps: int = 3
@export var countdown_time: float = 3.0
@export var vehicle_paths: Array[NodePath] = []
@export var lap_timer_paths: Array[NodePath] = []
@export var player_names: PackedStringArray = ["PLAYER 1", "PLAYER 2"]
@export var player_colors: PackedColorArray = [Color(0.35, 0.8, 1.0), Color(1.0, 0.4, 0.35)]
@export var circuit_path: NodePath

var state: int = State.COUNTDOWN
var race_time: float = 0.0
## Indices of the cars in the order they crossed the finish line.
var finish_order: Array[int] = []
var finish_times: Dictionary = {}

var _vehicles: Array[Vehicle] = []
var _timers: Array[LapTimer] = []
var _circuit: Circuit
var _countdown: float = 0.0
var _go_flash: float = 0.0
var _font: Font


func _ready() -> void:
	add_to_group("race_director")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_circuit = get_node_or_null(circuit_path) as Circuit
	for p in vehicle_paths:
		_vehicles.append(get_node(p) as Vehicle)
	for p in lap_timer_paths:
		_timers.append(get_node(p) as LapTimer)
	_countdown = countdown_time + 0.5
	for v in _vehicles:
		v.controls_locked = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				state = State.RACING
				_go_flash = 1.2
				for v in _vehicles:
					v.controls_locked = false
		State.RACING:
			race_time += delta
			for i in _vehicles.size():
				if i in finish_order:
					continue
				if completed_laps(i) >= laps:
					finish_order.append(i)
					finish_times[i] = race_time
			if finish_order.size() == _vehicles.size():
				state = State.FINISHED
	_go_flash = maxf(_go_flash - delta, 0.0)


func _process(_delta: float) -> void:
	queue_redraw()


func car_count() -> int:
	return _vehicles.size()


func vehicle_at(i: int) -> Vehicle:
	return _vehicles[i]


func completed_laps(i: int) -> int:
	var t := _timers[i]
	return maxi(t.lap - 1, 0) if t.running else 0


## Current lap being driven (1-based, capped at the race length).
func current_lap(i: int) -> int:
	return clampi(completed_laps(i) + 1, 1, laps)


func index_of(vehicle: Vehicle) -> int:
	return _vehicles.find(vehicle)


## 1 = leading. Finished cars keep their finishing position.
func position_of(i: int) -> int:
	var order := _vehicles.size()
	if i in finish_order:
		return finish_order.find(i) + 1
	var mine := _race_distance(i)
	var pos := finish_order.size() + 1
	for j in _vehicles.size():
		if j != i and not (j in finish_order) and _race_distance(j) > mine:
			pos += 1
	return mini(pos, order)


func _race_distance(i: int) -> float:
	if _circuit == null:
		return 0.0
	var offset := _circuit.progress_at(_vehicles[i].global_position)
	if not _timers[i].running:
		# Still on the grid behind the line.
		return offset - _circuit.length
	return completed_laps(i) * _circuit.length + offset


static func ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
	return "%dTH" % n


func _draw() -> void:
	var s := size
	var centre := s * 0.5
	if state == State.COUNTDOWN:
		var n := ceili(_countdown - 0.5)
		if n >= 1 and n <= int(countdown_time):
			_big(centre, str(n), 180, Color(1.0, 0.85, 0.25))
		_big(centre + Vector2(0, 130), "GET READY", 36, Color(1, 1, 1, 0.9))
	elif _go_flash > 0.0:
		_big(centre, "GO!", 180, Color(0.4, 1.0, 0.45, clampf(_go_flash, 0.0, 1.0)))

	if finish_order.size() > 0:
		_draw_results(centre)


func _draw_results(centre: Vector2) -> void:
	var winner := finish_order[0]
	var panel := Rect2(centre - Vector2(330, 150), Vector2(660, 300))
	draw_rect(panel, Color(0, 0, 0, 0.72))
	_big(centre + Vector2(0, -95), "%s WINS!" % player_names[winner], 52, player_colors[winner])
	var y := -30.0
	for place in finish_order.size():
		var i: int = finish_order[place]
		var gap := ""
		if place > 0:
			gap = "  (+%.3f s)" % (finish_times[i] - finish_times[finish_order[0]])
		_big(centre + Vector2(0, y), "%s  %s   %s%s" % [ordinal(place + 1), player_names[i],
				LapTimer.format_time(finish_times[i]), gap], 26, player_colors[i])
		y += 40.0
	for i in _vehicles.size():
		if not (i in finish_order):
			_big(centre + Vector2(0, y), "%s still racing..." % player_names[i], 22, Color(1, 1, 1, 0.7))
			y += 36.0
	_big(centre + Vector2(0, 120), "Backspace = race again    F3 = back to single player", 20, Color(1, 1, 1, 0.8))


func _big(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := pos + Vector2(-w * 0.5, font_size * 0.35)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(0, 0, 0, color.a * 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
