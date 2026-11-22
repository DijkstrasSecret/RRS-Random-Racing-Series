extends Control
## Driving HUD (design concept §12) and telemetry overlay (§6.5).
## Everything is drawn in _draw(), so there is no scene layout to maintain.

@export var vehicle_path: NodePath
## Leave empty to use the first LapTimer in the scene.
@export var lap_timer_path: NodePath
## Split screen: shows the player name instead of the car, hides help/telemetry.
@export var player_name: String = ""
@export var player_color: Color = Color(1.0, 0.78, 0.2)
@export var split_screen: bool = false

var show_telemetry: bool = false
var show_help: bool = true
var _vehicle: Vehicle
var _font: Font
var _lap_timer: LapTimer
var _circuit: Circuit
var _map_points := PackedVector2Array()
var _map_rect := Rect2()
var _map_centre := Vector2.ZERO
var _map_scale := 1.0
var _best_flash_until := 0.0
var _race: RaceDirector

const PANEL := Color(0.0, 0.0, 0.0, 0.5)
const TEXT := Color(1.0, 1.0, 1.0)
const DIM := Color(0.7, 0.72, 0.75)
const ACCENT := Color(1.0, 0.78, 0.2)
const GOOD := Color(0.35, 0.85, 0.45)
const WARN := Color(1.0, 0.8, 0.2)
const HOT := Color(1.0, 0.3, 0.25)

## Help panel: keys and what they do. The first five rows are driving.
const HELP_KEYS: PackedStringArray = [
	"W / Up", "S / Down", "A D / Arrows", "Space", "Q / E", "Gamepad", "P", "V", "C", "F1", "F2", "F3", "R", "H",
]
const HELP_ACTIONS: PackedStringArray = [
	"Throttle",
	"Brake  (hold when stopped = reverse)",
	"Steer",
	"Handbrake",
	"Shift down / up  (M = back to auto)",
	"Stick steer · RT / LT pedals · A handbrake · LB / RB shift",
	"Handling profile  (Arcade / Sport / Sim)",
	"Visual style  (Modern / PS2 / PS1)",
	"Camera view",
	"Telemetry",
	"Switch mode  (race / practice / test track)",
	"Two-player split screen race",
	"Recover car     Backspace  Back to start",
	"Hide help     Esc  Quit",
]


func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as Vehicle
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if split_screen:
		show_help = false


func _unhandled_input(event: InputEvent) -> void:
	if split_screen:
		return
	if event.is_action_pressed("toggle_telemetry"):
		show_telemetry = not show_telemetry
	elif event.is_action_pressed("toggle_help"):
		show_help = not show_help


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _vehicle == null:
		return
	var s := size
	_draw_speedo(Vector2(s.x - 330.0, s.y - 170.0))
	_draw_status(Vector2(24.0, s.y - 96.0))
	if show_help:
		_draw_help(Vector2(24.0, 24.0))
	if show_telemetry:
		_draw_telemetry(Vector2(s.x - 500.0, 24.0))
	_find_race_nodes()
	if _lap_timer:
		_draw_laps(Vector2(s.x * 0.5 - 270.0, 18.0))
	if _vehicle.off_track and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.4:
		_text(Vector2(s.x * 0.5 - 80.0, 160.0), "OFF TRACK", 32, HOT)
	if _circuit:
		_draw_minimap(Rect2(s.x - 254.0, s.y - 420.0, 230.0, 230.0))


func _find_race_nodes() -> void:
	if _race == null:
		_race = get_tree().get_first_node_in_group("race_director") as RaceDirector
	if _lap_timer == null:
		if not lap_timer_path.is_empty():
			_lap_timer = get_node_or_null(lap_timer_path) as LapTimer
		else:
			_lap_timer = get_tree().get_first_node_in_group("lap_timer") as LapTimer
		if _lap_timer:
			_lap_timer.lap_completed.connect(_on_lap_completed)
	if _circuit == null:
		_circuit = get_tree().get_first_node_in_group("circuit") as Circuit


func _on_lap_completed(_time: float, is_best: bool) -> void:
	if is_best:
		_best_flash_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _draw_laps(o: Vector2) -> void:
	var lt := _lap_timer
	draw_rect(Rect2(o, Vector2(540.0, 66.0)), PANEL)
	var me := _race.index_of(_vehicle) if _race else -1
	if me >= 0:
		# Race: lap x of N, and a big position badge on the left.
		_text(o + Vector2(18.0, 44.0), "LAP %d/%d" % [_race.current_lap(me), _race.laps], 22, ACCENT)
		draw_rect(Rect2(o - Vector2(110.0, 0.0), Vector2(100.0, 66.0)), PANEL)
		_text(o + Vector2(-100.0, 44.0), RaceDirector.ordinal(_race.position_of(me)), 36, player_color)
		_text(o + Vector2(-100.0, 62.0), "of %d" % _race.car_count(), 14, DIM)
	else:
		_text(o + Vector2(18.0, 44.0), ("LAP %d" % lt.lap) if lt.running else "LAP -", 26, ACCENT)
	_text(o + Vector2(130.0, 46.0), LapTimer.format_time(lt.lap_time if lt.running else -1.0), 34)
	_text(o + Vector2(330.0, 28.0), "LAST   " + LapTimer.format_time(lt.last_lap), 17, DIM)
	_text(o + Vector2(330.0, 54.0), "BEST   " + LapTimer.format_time(lt.best_lap), 17, GOOD)
	if Time.get_ticks_msec() / 1000.0 < _best_flash_until:
		_text(o + Vector2(190.0, 100.0), "NEW BEST LAP!", 28, GOOD)
	elif not lt.running and _race == null:
		_text(o + Vector2(120.0, 96.0), "Cross the line to start the clock", 18, DIM)


func _draw_minimap(rect: Rect2) -> void:
	if _map_points.is_empty() or _map_rect != rect:
		_build_map(rect)
	draw_rect(rect, PANEL)
	draw_polyline(_map_points, Color(0.1, 0.1, 0.12, 0.9), 7.0, true)
	draw_polyline(_map_points, Color(0.85, 0.86, 0.9), 3.0, true)
	draw_circle(_map_points[0], 4.0, ACCENT)
	if _race:
		for i in _race.car_count():
			var other := _race.vehicle_at(i)
			if other != _vehicle:
				var op := other.global_position
				draw_circle(_to_map(Vector2(op.x, op.z)), 4.5, _race.color_at(i))
	var p := _vehicle.global_position
	var dot := _to_map(Vector2(p.x, p.z))
	var fwd := -_vehicle.global_basis.z
	var me_color := player_color if not player_name.is_empty() else HOT
	draw_line(dot, dot + Vector2(fwd.x, fwd.z).normalized() * 10.0, me_color, 2.0)
	draw_circle(dot, 5.5, me_color)


func _build_map(rect: Rect2) -> void:
	_map_rect = rect
	var outline := _circuit.outline
	var lo := outline[0]
	var hi := outline[0]
	for q in outline:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	_map_centre = (lo + hi) * 0.5
	var span := hi - lo
	_map_scale = minf((rect.size.x - 24.0) / maxf(span.x, 1.0), (rect.size.y - 24.0) / maxf(span.y, 1.0))
	_map_points = PackedVector2Array()
	for i in range(0, outline.size(), 3):
		_map_points.append(_to_map(outline[i]))
	_map_points.append(_map_points[0])


func _to_map(world_xz: Vector2) -> Vector2:
	return _map_rect.get_center() + (world_xz - _map_centre) * _map_scale


func _text(pos: Vector2, text: String, font_size: int, color: Color = TEXT) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_speedo(o: Vector2) -> void:
	var dt := _vehicle.drivetrain
	var cfg := _vehicle.config
	draw_rect(Rect2(o, Vector2(306.0, 146.0)), PANEL)
	_text(o + Vector2(20.0, 76.0), "%d" % roundi(absf(_vehicle.forward_speed) * 3.6), 64)
	_text(o + Vector2(150.0, 76.0), "km/h", 20, DIM)
	_text(o + Vector2(240.0, 76.0), dt.gear_label(), 64, ACCENT)

	var bar := Rect2(o + Vector2(20.0, 98.0), Vector2(266.0, 18.0))
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.12))
	var frac := clampf(dt.rpm / cfg.redline_rpm, 0.0, 1.0)
	var col := GOOD
	if dt.rpm > cfg.auto_upshift_rpm:
		col = HOT
	elif frac > 0.75:
		col = WARN
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	if dt.rpm > cfg.auto_upshift_rpm:
		draw_circle(o + Vector2(286.0, 20.0), 9.0, HOT)
	_text(o + Vector2(20.0, 136.0), "%d rpm" % roundi(dt.rpm), 16, DIM)
	_text(o + Vector2(200.0, 136.0), "AUTO" if dt.automatic else "MANUAL", 16, DIM)


func _draw_status(o: Vector2) -> void:
	draw_rect(Rect2(o, Vector2(470.0, 72.0)), PANEL)
	if player_name.is_empty():
		_text(o + Vector2(16.0, 28.0), _vehicle.config.display_name, 18)
	else:
		_text(o + Vector2(16.0, 28.0), player_name, 20, player_color)
	_text(o + Vector2(250.0, 28.0), "Look: %s" % RetroLook.level_name(), 18, ACCENT)
	_text(o + Vector2(16.0, 56.0), "Profile: %s" % _vehicle.assists.profile_name(), 18, ACCENT)
	var x := 200.0
	for flag: Array in [["TC", _vehicle.tc_active], ["ABS", _vehicle.abs_active],
			["ESC", _vehicle.stability_active], ["HB", _vehicle.input.handbrake > 0.5]]:
		_text(o + Vector2(x, 56.0), flag[0], 18, HOT if flag[1] else Color(1, 1, 1, 0.25))
		x += 54.0


func _draw_help(o: Vector2) -> void:
	var line_h := 22.0
	draw_rect(Rect2(o, Vector2(560.0, 20.0 + line_h * HELP_KEYS.size())), PANEL)
	for i in HELP_KEYS.size():
		var y := 26.0 + line_h * i
		var col := TEXT if i < 6 else DIM
		_text(o + Vector2(14.0, y), HELP_KEYS[i], 16, ACCENT if i < 6 else DIM)
		_text(o + Vector2(140.0, y), HELP_ACTIONS[i], 16, col)


func _draw_telemetry(o: Vector2) -> void:
	var v := _vehicle
	draw_rect(Rect2(o, Vector2(476.0, 400.0)), PANEL)
	_text(o + Vector2(14.0, 26.0), "TELEMETRY", 18, ACCENT)
	_text(o + Vector2(140.0, 26.0), "lat %+.2f g   long %+.2f g   steer %+.1f°" % [
		v.g_lat, v.g_long, rad_to_deg(v.steer_angle)], 15, DIM)
	var order: Array[Wheel] = []
	order.append_array(v.front_wheels)
	order.append_array(v.rear_wheels)
	for i in order.size():
		var cell := o + Vector2(14.0 + (i % 2) * 232.0, 44.0 + floorf(i / 2.0) * 176.0)
		_draw_wheel(cell, order[i])


func _draw_wheel(o: Vector2, w: Wheel) -> void:
	draw_rect(Rect2(o, Vector2(220.0, 166.0)), Color(1.0, 1.0, 1.0, 0.06))
	var label := String(w.name).trim_prefix("Wheel")
	_text(o + Vector2(10.0, 22.0), label, 18, ACCENT)
	var lines := [
		"load   %.2f kN" % (w.tire_load / 1000.0),
		"slip   %+.3f" % w.slip_ratio,
		"angle  %+.1f°" % rad_to_deg(w.slip_angle),
		"susp   %d %%" % roundi(w.compression_ratio() * 100.0),
		"spin   %.0f rad/s" % w.omega,
		"grip   %d %%" % roundi(w.grip_usage * 100.0),
	]
	for i in lines.size():
		_text(o + Vector2(10.0, 46.0 + i * 19.0), lines[i], 14, TEXT if w.grounded else DIM)

	# Friction circle: dot = tyre force relative to the grip limit.
	var c := o + Vector2(170.0, 96.0)
	var r := 38.0
	draw_arc(c, r, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.5), 1.5)
	draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), Color(1.0, 1.0, 1.0, 0.15))
	draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), Color(1.0, 1.0, 1.0, 0.15))
	if w.mu_load > 1.0:
		var p := Vector2(w.force_lat, -w.force_long) / w.mu_load
		var col := GOOD if w.grip_usage < 0.85 else (WARN if w.grip_usage < 0.98 else HOT)
		draw_circle(c + p * r, 5.0, col)
