class_name GaragePanel
extends VBoxContainer
## Garage: each player picks a car (left/right). Shows the car's name, a
## short description, its specs and 0-10 bars for the main stats.
## `car_shown(id)` tells the menu which car to display in the 3D preview.

signal closed
signal car_shown(id: String, livery: bool)

var _p1: OptionRow
var _p2: OptionRow
var _p1_livery: OptionRow
var _p2_livery: OptionRow
var _name: Label
var _tagline: Label
var _specs: Label
var _bars: StatBars


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_child(MenuStyle.label("GARAGE", 40, MenuStyle.ACCENT))
	_p1 = OptionRow.create("PLAYER 1", CarRoster.names(), CarRoster.index_of(GameSettings.p1_car))
	_p2 = OptionRow.create("PLAYER 2", CarRoster.names(), CarRoster.index_of(GameSettings.p2_car))
	_p1_livery = OptionRow.create("P1 LIVERY", PackedStringArray(["OFF", "ON"]), int(GameSettings.p1_livery))
	_p2_livery = OptionRow.create("P2 LIVERY", PackedStringArray(["OFF", "ON"]), int(GameSettings.p2_livery))
	for row: OptionRow in [_p1, _p1_livery, _p2, _p2_livery]:
		row.custom_minimum_size = Vector2(640, 0)
		add_child(row)
		row.focus_entered.connect(_refresh)
	_p1_livery.value_changed.connect(func(i: int) -> void:
		GameSettings.p1_livery = i == 1
		GameSettings.save()
		_refresh())
	_p2_livery.value_changed.connect(func(i: int) -> void:
		GameSettings.p2_livery = i == 1
		GameSettings.save()
		_refresh())
	_p1.value_changed.connect(func(i: int) -> void:
		GameSettings.p1_car = CarRoster.CARS[i].id
		GameSettings.save()
		_refresh())
	_p2.value_changed.connect(func(i: int) -> void:
		GameSettings.p2_car = CarRoster.CARS[i].id
		GameSettings.save()
		_refresh())

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	add_child(gap)
	_name = MenuStyle.label("", 34, MenuStyle.TEXT)
	_tagline = MenuStyle.label("", 19, MenuStyle.DIM)
	_specs = MenuStyle.label("", 20, MenuStyle.ACCENT)
	# Fixed width: switching cars must not resize the panel.
	for l: Label in [_name, _tagline, _specs]:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(640, 0)
		add_child(l)
	_bars = StatBars.new()
	_bars.custom_minimum_size = Vector2(560, 6 * 30)
	add_child(_bars)
	add_child(MenuStyle.label("Left / right to change car. Player 2 is for split screen.", 17, MenuStyle.DIM))
	var back := MenuStyle.button("BACK", func() -> void: closed.emit())
	add_child(back)


func focus_first() -> void:
	_p1.grab_focus.call_deferred()
	_refresh.call_deferred()


func _refresh() -> void:
	var second := _p2.has_focus() or _p2_livery.has_focus()
	var row := _p2 if second else _p1
	var e: Dictionary = CarRoster.CARS[row.index]
	var s := CarRoster.stats(e.id)
	_name.text = e.name
	_tagline.text = e.tagline
	_specs.text = "CLASS %s   ·   %d HP   ·   %d KG   ·   %d KM/H   ·   %s%s" % [
		CarRoster.TIER_NAMES[int(e.tier)], s.hp, s.kg, s.top_kmh, s.drive, "   ·   ELECTRIC" if s.electric else ""]
	_bars.stats = s
	_bars.queue_redraw()
	car_shown.emit(e.id, GameSettings.p2_livery if second else GameSettings.p1_livery)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Six labelled 10-segment bars that slide to the new values when the car
## changes. Segments fill partly, so small differences still show.
class StatBars extends Control:
	const ROWS := [["ACCELERATION", "acceleration"], ["TOP SPEED", "top_speed"], ["HANDLING", "handling"],
		["BRAKING", "braking"], ["GRIP", "grip"], ["WEIGHT", "weight"]]
	var stats: Dictionary = {}
	var _shown: Dictionary = {}

	func _process(delta: float) -> void:
		var moving := false
		for row: Array in ROWS:
			var key: String = row[1]
			var target: float = stats.get(key, 0.0)
			var now: float = _shown.get(key, 0.0)
			if absf(target - now) > 0.01:
				now = lerpf(now, target, 1.0 - exp(-10.0 * delta))
				moving = true
			else:
				now = target
			_shown[key] = now
		if moving or _shown.size() != ROWS.size():
			queue_redraw()

	func _draw() -> void:
		if stats.is_empty():
			return
		var font := ThemeDB.fallback_font
		var row_h := 30.0 if custom_minimum_size.y >= 6 * 30 else 26.0
		for i in ROWS.size():
			var y := i * row_h
			var label: String = ROWS[i][0]
			var value: float = _shown.get(ROWS[i][1], 0.0)
			draw_string_outline(font, Vector2(0, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(0, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.TEXT)
			for seg in 10:
				var r := Rect2(Vector2(190 + seg * 34, y + 6), Vector2(30, 14))
				draw_rect(r.grow(1.5), Color(0, 0, 0, 0.55))
				draw_rect(r, Color(1, 1, 1, 0.12))
				var fill := clampf(value - seg, 0.0, 1.0)
				if fill > 0.0:
					var col := MenuStyle.ACCENT.darkened(0.25).lerp(MenuStyle.ACCENT.lightened(0.2), seg / 9.0)
					draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)
			var num := "%.1f" % value
			draw_string_outline(font, Vector2(536, y + 20), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(536, y + 20), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MenuStyle.DIM)
