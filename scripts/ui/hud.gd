extends Control
## Driving HUD (design concept §12) and telemetry overlay (§6.5).
## Everything is drawn in _draw(), so there is no scene layout to maintain.

@export var vehicle_path: NodePath

var show_telemetry: bool = false
var show_help: bool = true
var _vehicle: Vehicle
var _font: Font

const PANEL := Color(0.0, 0.0, 0.0, 0.5)
const TEXT := Color(1.0, 1.0, 1.0)
const DIM := Color(0.7, 0.72, 0.75)
const ACCENT := Color(1.0, 0.78, 0.2)
const GOOD := Color(0.35, 0.85, 0.45)
const WARN := Color(1.0, 0.8, 0.2)
const HOT := Color(1.0, 0.3, 0.25)

## Help panel: keys and what they do. The first five rows are driving.
const HELP_KEYS: PackedStringArray = [
	"W / Up", "S / Down", "A D / Arrows", "Space", "Q / E", "P", "V", "C", "F1", "R", "H",
]
const HELP_ACTIONS: PackedStringArray = [
	"Throttle",
	"Brake  (hold when stopped = reverse)",
	"Steer",
	"Handbrake",
	"Shift down / up  (M = back to auto)",
	"Handling profile  (Arcade / Sport / Sim)",
	"Visual style  (Modern / PS2-ish / PS1)",
	"Camera view",
	"Telemetry",
	"Recover car     Backspace  Back to start",
	"Hide help     Esc  Quit",
]


func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as Vehicle
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
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
	_text(o + Vector2(16.0, 28.0), _vehicle.config.display_name, 18)
	_text(o + Vector2(250.0, 28.0), "Look: %s" % RetroLook.level_name(), 18, ACCENT)
	_text(o + Vector2(16.0, 56.0), "Profile: %s" % _vehicle.assists.profile_name(), 18, ACCENT)
	var x := 200.0
	for flag: Array in [["TC", _vehicle.tc_active], ["ABS", _vehicle.abs_active],
			["ESC", _vehicle.stability_active], ["HB", _vehicle.input.handbrake > 0.5]]:
		_text(o + Vector2(x, 56.0), flag[0], 18, HOT if flag[1] else Color(1, 1, 1, 0.25))
		x += 54.0


func _draw_help(o: Vector2) -> void:
	var line_h := 22.0
	draw_rect(Rect2(o, Vector2(470.0, 20.0 + line_h * HELP_KEYS.size())), PANEL)
	for i in HELP_KEYS.size():
		var y := 26.0 + line_h * i
		var col := TEXT if i < 5 else DIM
		_text(o + Vector2(14.0, y), HELP_KEYS[i], 16, ACCENT if i < 5 else DIM)
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
