extends Control
## Driving HUD (design concept §12) and telemetry overlay (§6.5).
## Everything is drawn in _draw(), so there is no scene layout to maintain.

## The car this HUD shows.
@export var vehicle_path: NodePath
## Leave empty to use the first LapTimer in the scene.
@export var lap_timer_path: NodePath
## Name tag shown instead of the lap number, e.g. "PLAYER 1" in split screen. Empty = no tag.
@export var player_name: String = ""
## Colour of the player's name tag and position marker (used when player_name is set).
@export var player_color: Color = Color(1.0, 0.78, 0.2)
## Split screen: smaller layout, no telemetry.
@export var split_screen: bool = false

var show_telemetry: bool = false
var _vehicle: Vehicle
var _font: Font
var _bold: FontVariation
var _lap_timer: LapTimer
var _circuit: Circuit
var _map_points := PackedVector2Array()
var _map_rect := Rect2()
var _map_centre := Vector2.ZERO
var _map_scale := 1.0
var _best_flash_until := 0.0
var _race: RaceDirector
var _camera: ChaseCamera

const PANEL := Color(0.0, 0.0, 0.0, 0.5)
const TEXT := Color(1.0, 1.0, 1.0)
const DIM := Color(0.7, 0.72, 0.75)
const ACCENT := Color(1.0, 0.78, 0.2)
const GOOD := Color(0.35, 0.85, 0.45)
const WARN := Color(1.0, 0.8, 0.2)
const HOT := Color(1.0, 0.3, 0.25)

func _ready() -> void:
	_vehicle = get_node_or_null(vehicle_path) as Vehicle
	_font = ThemeDB.fallback_font
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.7
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if split_screen:
		return
	if event.is_action_pressed("toggle_telemetry"):
		show_telemetry = not show_telemetry


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _vehicle == null:
		return
	var s := size
	# Split screen halves get a smaller copy of the same layout.
	var k := clampf(s.y / 1080.0, 0.5, 1.0)
	_find_race_nodes()
	var r := 150.0 * k
	_draw_dial(Vector2(s.x - r - 36.0 * k, s.y - r - 30.0 * k), r, k)
	if _vehicle.damage:
		_draw_damage(Vector2(s.x - r * 2.0 - 96.0 * k, s.y - 150.0 * k), k)
	if _vehicle.wheels.size() == 4 and _vehicle.wheels[0].wear_rate > 0.0:
		_draw_tyres(Vector2(s.x - r * 2.0 - 176.0 * k, s.y - 150.0 * k), k)
	_draw_top(k)
	if _circuit:
		var m := 200.0 * k
		_draw_minimap(Rect2(28.0 * k, s.y - m - 28.0 * k, m, m))
	if show_telemetry:
		_draw_telemetry(Vector2(s.x - 500.0, 150.0))
	_draw_view_name(k)
	_draw_nitro(Vector2(s.x - r * 2.0 - 36.0 * k, s.y - r * 2.0 - 84.0 * k), k)
	if _vehicle.draft > 0.15:
		var dx := s.x - r * 2.0 - 36.0 * k
		_label(Vector2(dx + 200.0 * k, s.y - r * 2.0 - 92.0 * k), "SLIPSTREAM", int(16 * k), Color(0.5, 0.9, 1.0, 0.5 + 0.5 * _vehicle.draft))
	if Tournament.active:
		_draw_tournament(k)
	if _vehicle.pit_service_left > 0.0:
		_label(Vector2(s.x * 0.5, s.y * 0.2), "PIT STOP  %.1f" % _vehicle.pit_service_left, int(34 * k), GOOD, true)
	elif _vehicle.in_pit_lane:
		_label(Vector2(s.x * 0.5, s.y * 0.2), "PIT LIMITER 60", int(28 * k), Color(1.0, 0.8, 0.2), true)
	if _vehicle.off_track and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.4:
		_label(Vector2(s.x * 0.5, s.y * 0.2), "OFF TRACK", int(34 * k), HOT, true)


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


## F1-style timing: the position tower on the left (race) and the lap timer
## with sector times on the right.
func _draw_top(k: float) -> void:
	if _lap_timer == null:
		return
	var lt := _lap_timer
	var s := size
	var me := _race.index_of(_vehicle) if _race else -1
	if me >= 0:
		_draw_tower(Vector2(24.0 * k, 24.0 * k), k, me)
	else:
		var box := Rect2(24.0 * k, 24.0 * k, 150.0 * k, 40.0 * k)
		draw_rect(box, F1_DARK)
		draw_rect(Rect2(box.position, Vector2(box.size.x, 3.0 * k)), F1_RED)
		_bold_text(box.position + Vector2(12.0 * k, 28.0 * k), ("LAP %d" % lt.lap) if lt.running else "LAP -", int(21 * k), TEXT)
	_draw_timer(Vector2(s.x - 24.0 * k - 340.0 * k, 24.0 * k), k, lt)
	if Time.get_ticks_msec() / 1000.0 < _best_flash_until:
		_label(Vector2(s.x * 0.5, 120.0 * k), "NEW BEST LAP!", int(34 * k), F1_PURPLE if _is_session_best(lt) else F1_GREEN, true)
	elif not lt.running and _race == null:
		_label(Vector2(s.x * 0.5, 120.0 * k), "Cross the line to start the clock", int(22 * k), DIM, true)


const F1_DARK := Color(0.05, 0.05, 0.07, 0.88)
const F1_ROW := Color(0.09, 0.09, 0.11, 0.84)
const F1_ROW_ALT := Color(0.12, 0.12, 0.14, 0.84)
const F1_RED := Color(0.9, 0.08, 0.08)
const F1_PURPLE := Color(0.66, 0.24, 0.95)
const F1_GREEN := Color(0.1, 0.84, 0.32)
const F1_YELLOW := Color(1.0, 0.82, 0.1)
const F1_GREY := Color(0.35, 0.35, 0.4)


## Position tower: lap counter, then every car in order with its colour,
## three-letter code and gap to the car ahead. Your row is highlighted.
func _draw_tower(o: Vector2, k: float, me: int) -> void:
	var w := 262.0 * k
	var row := 31.0 * k
	var head := Rect2(o, Vector2(w, 42.0 * k))
	draw_rect(head, F1_DARK)
	draw_rect(Rect2(o, Vector2(w, 3.0 * k)), F1_RED)
	_bold_text(o + Vector2(12.0 * k, 29.0 * k), "LAP", int(19 * k), DIM)
	_bold_text(o + Vector2(58.0 * k, 29.0 * k), "%d/%d" % [_race.current_lap(me), _race.laps], int(22 * k), TEXT)
	var y := o.y + head.size.y
	var order := _race.standings()
	for n in order.size():
		var i: int = order[n]
		var mine := i == me
		var r := Rect2(o.x, y, w, row)
		draw_rect(r, Color(0.95, 0.95, 0.96, 0.95) if mine else (F1_ROW if n % 2 == 0 else F1_ROW_ALT))
		var ink := Color(0.05, 0.05, 0.07) if mine else TEXT
		_bold_text_centered(Vector2(o.x + 18.0 * k, y + row * 0.72), str(n + 1), int(18 * k), ink)
		draw_rect(Rect2(o.x + 38.0 * k, y + 6.0 * k, 4.0 * k, row - 12.0 * k), _race.color_at(i))
		_bold_text(Vector2(o.x + 52.0 * k, y + row * 0.72), _code(_race.name_at(i)), int(19 * k), ink)
		var gap := _race.interval(i)
		if i in _race.finish_order and n == 0:
			gap = "FINISH"
		draw_string(_font, Vector2(o.x + w - 10.0 * k - 110.0 * k, y + row * 0.72), gap, HORIZONTAL_ALIGNMENT_RIGHT,
				110.0 * k, int(16 * k), Color(0.2, 0.2, 0.25) if mine else Color(0.82, 0.83, 0.86))
		y += row


## Lap timer: current lap time, three sector boxes coloured F1 style, last and best lap.
func _draw_timer(o: Vector2, k: float, lt: LapTimer) -> void:
	var w := 340.0 * k
	var top := Rect2(o, Vector2(w, 54.0 * k))
	draw_rect(top, F1_DARK)
	draw_rect(Rect2(o, Vector2(w, 3.0 * k)), F1_RED)
	var tag := player_name if not player_name.is_empty() else ("LAP %d" % lt.lap if lt.running else "LAP -")
	_bold_text(o + Vector2(12.0 * k, 35.0 * k), tag, int(17 * k), player_color if not player_name.is_empty() else DIM)
	draw_string(_bold, o + Vector2(0, 40.0 * k), LapTimer.format_time(lt.lap_time if lt.running else -1.0),
			HORIZONTAL_ALIGNMENT_RIGHT, w - 12.0 * k, int(32 * k), TEXT)
	# Sectors: this lap's as they come in; until then last lap's, faded (as on F1 TV).
	var cell := w / 3.0
	var sy := o.y + top.size.y
	for n in 3:
		var t := lt.sectors[n]
		var c := _sector_color(lt.sector_colors[n])
		var fade := 1.0
		if t < 0.0 and lt.last_sectors[n] >= 0.0:
			t = lt.last_sectors[n]
			c = _sector_color(lt.last_sector_colors[n])
			fade = 0.4
		var r := Rect2(o.x + n * cell, sy, cell - (2.0 * k if n < 2 else 0.0), 42.0 * k)
		draw_rect(r, F1_ROW)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0 * k)), Color(c, c.a * fade))
		_bold_text(r.position + Vector2(8.0 * k, 31.0 * k), "S%d" % (n + 1), int(14 * k), DIM)
		draw_string(_bold, r.position + Vector2(0, 31.0 * k), LapTimer.format_sector(t), HORIZONTAL_ALIGNMENT_RIGHT,
				r.size.x - 8.0 * k, int(18 * k), Color(TEXT, fade) if t >= 0.0 else F1_GREY)
	var by := sy + 42.0 * k
	var bottom := Rect2(o.x, by, w, 30.0 * k)
	draw_rect(bottom, F1_DARK)
	_text(Vector2(o.x + 10.0 * k, by + 21.0 * k), "LAST", int(14 * k), DIM)
	_bold_text(Vector2(o.x + 50.0 * k, by + 21.0 * k), LapTimer.format_time(lt.last_lap), int(16 * k), TEXT)
	_text(Vector2(o.x + w * 0.5 + 6.0 * k, by + 21.0 * k), "BEST", int(14 * k), DIM)
	var best_col := F1_PURPLE if _is_session_best(lt) else (F1_GREEN if lt.best_lap > 0.0 else TEXT)
	_bold_text(Vector2(o.x + w * 0.5 + 48.0 * k, by + 21.0 * k), LapTimer.format_time(lt.best_lap), int(16 * k), best_col)


func _is_session_best(lt: LapTimer) -> bool:
	return lt.best_lap > 0.0 and _circuit != null and absf(lt.best_lap - _circuit.best_lap) < 0.0005


func _sector_color(c: int) -> Color:
	match c:
		LapTimer.SectorColor.PURPLE:
			return F1_PURPLE
		LapTimer.SectorColor.GREEN:
			return F1_GREEN
		LapTimer.SectorColor.YELLOW:
			return F1_YELLOW
	return F1_GREY


## Three-letter timing code: "VEGA" -> "VEG", "PLAYER 2" -> "P2".
static func _code(racer_name: String) -> String:
	if racer_name.begins_with("PLAYER "):
		return "P" + racer_name.trim_prefix("PLAYER ")
	return racer_name.substr(0, 3).to_upper()


func _bold_text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_bold, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _bold_text_centered(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_bold, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


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


## Round arcade rev dial: needle over a 270 degree scale (red zone near
## the limiter), digital speed in the middle, gear in a box at the bottom.
func _draw_dial(c: Vector2, r: float, k: float) -> void:
	var dt := _vehicle.drivetrain
	var cfg := _vehicle.config
	var step := 1000.0 if cfg.redline_rpm <= 9500.0 else 2000.0
	var max_rpm := ceilf(cfg.redline_rpm / step) * step
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	draw_circle(c, r, Color(0.02, 0.025, 0.04, 0.62))
	draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.3), 3.0 * k, true)
	# Red zone from the shift point to the end of the scale.
	var red_from := clampf(minf(cfg.auto_upshift_rpm, cfg.redline_rpm * 0.92) / max_rpm, 0.0, 1.0)
	draw_arc(c, r * 0.9, a0 + sweep * red_from, a0 + sweep, 24, HOT, 9.0 * k, true)
	# Ticks and numbers (thousands of rpm).
	var n := int(max_rpm / step)
	for i in n * 2 + 1:
		var f := i / float(n * 2)
		var dir := Vector2.from_angle(a0 + sweep * f)
		var major := i % 2 == 0
		draw_line(c + dir * r * (0.8 if major else 0.86), c + dir * r * 0.95, TEXT if major else DIM, (3.0 if major else 1.5) * k)
		if major:
			var label := str(roundi(i * 0.5 * step / 1000.0))
			_label(c + dir * r * 0.66 + Vector2(0, 8.0 * k), label, int(22 * k), TEXT, true, 3)
	# Needle.
	var f_rpm := clampf(dt.rpm / max_rpm, 0.0, 1.02)
	var nd := Vector2.from_angle(a0 + sweep * f_rpm)
	draw_line(c - nd * r * 0.12, c + nd * r * 0.88, Color(0, 0, 0, 0.6), 7.0 * k)
	draw_line(c - nd * r * 0.12, c + nd * r * 0.88, HOT, 4.0 * k)
	draw_circle(c, 9.0 * k, Color(0.15, 0.15, 0.17))
	draw_circle(c, 5.0 * k, HOT)
	# Speed, units and gear.
	_label(c + Vector2(0, r * 0.42), "%d" % roundi(absf(_vehicle.forward_speed) * 3.6), int(54 * k), TEXT, true)
	_label(c + Vector2(0, r * 0.58), "KM/H", int(16 * k), DIM, true, 3)
	var box := Rect2(c + Vector2(-26.0 * k, r * 0.68), Vector2(52.0 * k, 46.0 * k))
	draw_rect(box, Color(0, 0, 0, 0.7))
	draw_rect(box, ACCENT, false, 2.0 * k)
	_label(box.get_center() + Vector2(0, 14.0 * k), dt.gear_label(), int(38 * k), ACCENT, true)
	if not dt.automatic:
		_label(box.position + Vector2(box.size.x + 8.0 * k, box.size.y * 0.7), "M", int(18 * k), DIM)
	# Shift light, and the driving aids lighting up when they step in.
	if dt.rpm > cfg.auto_upshift_rpm and fmod(Time.get_ticks_msec() / 1000.0, 0.2) < 0.12:
		draw_circle(c + Vector2(0, -r * 0.42), 8.0 * k, HOT)
	var x := c.x - r
	for flag: Array in [["TC", _vehicle.tc_active], ["ABS", _vehicle.abs_active], ["ESC", _vehicle.stability_active]]:
		_label(Vector2(x, c.y - r - 12.0 * k), flag[0], int(17 * k), HOT if flag[1] else Color(1, 1, 1, 0.22))
		x += 46.0 * k


## Four tyres (top = front): colour = temperature (blue cold, green ideal,
## orange / red hot), the dark part = worn away, % = tread left.
func _draw_tyres(o: Vector2, k: float) -> void:
	var tw := 22.0 * k
	var th := 38.0 * k
	draw_rect(Rect2(o - Vector2(6, 6) * k, Vector2(tw * 2.0 + 30.0 * k, th * 2.0 + 40.0 * k)), PANEL)
	var order := {"FL": Vector2(0, 0), "FR": Vector2(1, 0), "RL": Vector2(0, 1), "RR": Vector2(1, 1)}
	for w in _vehicle.wheels:
		var key := String(w.name).trim_prefix("Wheel")
		if not order.has(key):
			continue
		var cell: Vector2 = order[key]
		var p := o + Vector2(cell.x * (tw + 18.0 * k), cell.y * (th + 22.0 * k))
		var col := Color(0.35, 0.55, 1.0)
		if w.temp >= 105.0:
			col = Color(1.0, 0.55, 0.15).lerp(HOT, clampf((w.temp - 105.0) / 25.0, 0.0, 1.0))
		elif w.temp >= 75.0:
			col = GOOD
		elif w.temp >= 55.0:
			col = Color(0.35, 0.55, 1.0).lerp(GOOD, (w.temp - 55.0) / 20.0)
		draw_rect(Rect2(p, Vector2(tw, th)), col)
		draw_rect(Rect2(p, Vector2(tw, th * w.wear)), Color(0.05, 0.05, 0.07, 0.8))
		draw_rect(Rect2(p, Vector2(tw, th)), Color(1, 1, 1, 0.5), false, 1.5 * k)
		# Running gear: a lost wheel is an empty outline, a flat one red, a bent one yellow.
		var note := "%d" % roundi((1.0 - w.wear) * 100.0)
		var note_col := TEXT
		if w.detached:
			draw_rect(Rect2(p, Vector2(tw, th)), Color(0.05, 0.05, 0.07, 1.0))
			draw_rect(Rect2(p, Vector2(tw, th)), HOT, false, 2.0 * k)
			note = "OFF"
			note_col = HOT
		elif w.punctured:
			note = "FLAT"
			note_col = HOT
		elif absf(w.toe) > 0.02:
			note = "BENT"
			note_col = Color(1.0, 0.8, 0.2)
		_label(p + Vector2(tw * 0.5, th + 15.0 * k), note, int(13 * k), note_col, true, 3)


## Small top-down car (nose up): each area turns yellow, then red, as it
## takes damage.
func _draw_damage(o: Vector2, k: float) -> void:
	var z := _vehicle.damage.zones
	var w := 46.0 * k
	var h := 92.0 * k
	var e := 11.0 * k  # thickness of the front / rear / side strips
	var areas := [
		[Rect2(o.x + e, o.y, w - 2.0 * e, e * 1.6), CarDamage.Zone.FRONT],
		[Rect2(o.x + e, o.y + h - e * 1.6, w - 2.0 * e, e * 1.6), CarDamage.Zone.REAR],
		[Rect2(o.x, o.y + e, e, h - 2.0 * e), CarDamage.Zone.LEFT],
		[Rect2(o.x + w - e, o.y + e, e, h - 2.0 * e), CarDamage.Zone.RIGHT],
		[Rect2(o.x + e * 1.5, o.y + h * 0.3, w - 3.0 * e, h * 0.4), CarDamage.Zone.ROOF],
	]
	draw_rect(Rect2(o - Vector2(6, 6) * k, Vector2(w, h) + Vector2(12, 12) * k), PANEL)
	for a: Array in areas:
		var d: float = z[a[1]]
		var col := Color(1, 1, 1, 0.28)
		if d > 0.02:
			col = WARN.lerp(HOT, clampf((d - 0.3) / 0.4, 0.0, 1.0))
			col.a = 0.55 + 0.45 * clampf(d * 2.0, 0.0, 1.0)
		draw_rect(a[0], col)
	draw_rect(Rect2(o, Vector2(w, h)), Color(1, 1, 1, 0.55), false, 2.0 * k)


## Tournament X / Y item gauges above the dial, plus the passives' state.
func _draw_nitro(o: Vector2, k: float) -> void:
	var perks := _vehicle.get_node_or_null("Perks") as CarPerks
	if perks == null:
		return
	var w := 300.0 * k
	var h := 18.0 * k
	var y := o.y
	if perks.capacity > 0.0:
		var r := Rect2(Vector2(o.x, y), Vector2(w, h))
		draw_rect(r.grow(3.0 * k), Color(0.05, 0.05, 0.07, 0.85))
		var col := Color(1.0, 0.45, 0.9) if perks.boosting else Color(0.75, 0.3, 0.95)
		draw_rect(Rect2(r.position, Vector2(w * perks.energy / perks.capacity, h)), col)
		# Pulse items: one segment per use.
		var seg := perks.pulse_length()
		if seg > 0.0:
			var n := roundi(perks.capacity / seg)
			for k2 in range(1, n):
				var x := r.position.x + w * k2 / float(n)
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.05, 0.05, 0.07), 3.0 * k)
		_label(Vector2(o.x, y - 8.0 * k), "X  " + String(Upgrades.UNLOCKS[perks.power_id].name), int(16 * k), col)
		y -= 44.0 * k
	if perks.tactical_id != "":
		var txt := ""
		var col := Color(0.3, 0.9, 0.85)
		if perks.tactical_id == "engine_map":
			txt = "Y  MAP: " + ("STABILITY" if perks.map_stability else "POWER")
		else:
			txt = "Y  DRS " + ("OPEN" if perks.drs_open else ("READY" if perks.drs_available else "—"))
			col = Color(0.4, 1.0, 0.5) if perks.drs_open else (col if perks.drs_available else DIM)
		_label(Vector2(o.x, y + 10.0 * k), txt, int(18 * k), col)
		y -= 30.0 * k
	# Passives that are doing something right now.
	var tags := PackedStringArray()
	if perks.shift_bonus > 0.0:
		tags.append("PERFECT SHIFT")
	if perks.grip_bonus > 0.0:
		tags.append("GRIP+")
	if perks.heel_armed:
		tags.append("HEEL-TOE READY")
	if perks.late_armed:
		tags.append("LATE BRAKE")
	if perks.level("clean_sector") > 0 and perks.clean_time > CarPerks.CLEAN_TIME:
		tags.append("CLEAN")
	if perks.engine_heat > CarPerks.HEAT_LIMIT * 0.5:
		tags.append("ENGINE HOT!")
	if not tags.is_empty():
		_label(Vector2(o.x, y + 10.0 * k), "  ·  ".join(tags), int(16 * k), Color(1.0, 0.85, 0.3))
	if perks.level("heel_toe") > 0 and perks.heel_meter > 0.0:
		var m := Rect2(Vector2(o.x + w + 14.0 * k, o.y - 40.0 * k), Vector2(10.0 * k, 58.0 * k))
		draw_rect(m.grow(2.0 * k), Color(0.05, 0.05, 0.07, 0.85))
		draw_rect(Rect2(Vector2(m.position.x, m.end.y - m.size.y * perks.heel_meter), Vector2(m.size.x, m.size.y * perks.heel_meter)),
				Color(0.55, 0.9, 0.4))



## Tournament banner: which race, this player's points and score, and the
## DNF countdown when the car is wrecked.
func _draw_tournament(k: float) -> void:
	var me := Tournament.human(2 if player_name == "PLAYER 2" else 1)
	var text := Tournament.race_title()
	text += "   ·   %d PTS" % int(me.get("wallet", 0))
	if Tournament.is_scored():
		text += "   ·   SCORE %d" % int(me.get("score", 0))
	var font_size := int(22 * k)
	var tw := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var r := Rect2(size.x * 0.5 - tw * 0.5 - 20.0 * k, 24.0 * k, tw + 40.0 * k, 40.0 * k)
	draw_rect(r, F1_DARK)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0 * k)), Color(1.0, 0.45, 0.85) if Tournament.is_scored() else F1_RED)
	_bold_text(r.position + Vector2(20.0 * k, 28.0 * k), text, font_size, TEXT)
	if _race:
		var i := _race.index_of(_vehicle)
		if i >= 0 and _race.is_retired(i):
			_label(Vector2(size.x * 0.5, size.y * 0.32), "DNF  ·  OUT OF THIS RACE", int(40 * k), HOT, true)
		elif i >= 0:
			var warn := _race.wreck_warning(i)
			if warn != "":
				_label(Vector2(size.x * 0.5, size.y * 0.32), warn, int(32 * k), HOT, true)


## Shows the camera view name for a moment after it changes.
func _draw_view_name(k: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = null
		for node in get_tree().get_nodes_in_group("chase_cameras"):
			var cam := node as ChaseCamera
			if cam and cam.target() == _vehicle:
				_camera = cam
		if _camera == null:
			return
	if _camera.view_changed_ago < 1.6:
		var a := clampf((1.6 - _camera.view_changed_ago) / 0.4, 0.0, 1.0)
		_label(Vector2(size.x * 0.5, size.y - 60.0 * k), "VIEW:  " + _camera.view_name(), int(26 * k),
				Color(MenuStyle.ACCENT, a), true)


## Outlined text; `centre` centres it on `pos.x`.
func _label(pos: Vector2, text: String, font_size: int, color: Color = TEXT, centre: bool = false, outline: int = 6) -> void:
	if centre:
		pos.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _label_right(pos: Vector2, text: String, font_size: int, color: Color = TEXT) -> void:
	pos.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label(pos, text, font_size, color)


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
