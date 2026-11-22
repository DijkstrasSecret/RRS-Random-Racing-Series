class_name GaragePanel
extends VBoxContainer
## Garage: each player picks a car (left/right). Shows the car's name, a
## short description, its specs and 0-10 bars for the main stats.
## `car_shown(id)` tells the menu which car to display in the 3D preview.

signal closed
signal car_shown(id: String)

var _p1: OptionRow
var _p2: OptionRow
var _name: Label
var _tagline: Label
var _specs: Label
var _bars: StatBars


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_child(MenuStyle.label("GARAGE", 40, MenuStyle.ACCENT))
	_p1 = OptionRow.create("PLAYER 1", CarRoster.names(), CarRoster.index_of(GameSettings.p1_car))
	_p2 = OptionRow.create("PLAYER 2", CarRoster.names(), CarRoster.index_of(GameSettings.p2_car))
	for row: OptionRow in [_p1, _p2]:
		row.custom_minimum_size = Vector2(760, 0)
		add_child(row)
		row.focus_entered.connect(_refresh)
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
	add_child(_name)
	_tagline = MenuStyle.label("", 19, MenuStyle.DIM)
	add_child(_tagline)
	_specs = MenuStyle.label("", 20, MenuStyle.ACCENT)
	add_child(_specs)
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
	var row := _p2 if _p2.has_focus() else _p1
	var e: Dictionary = CarRoster.CARS[row.index]
	var s := CarRoster.stats(e.id)
	_name.text = e.name
	_tagline.text = e.tagline
	_specs.text = "%d HP   ·   %d KG   ·   %d KM/H   ·   %s%s" % [
		s.hp, s.kg, s.top_kmh, s.drive, "   ·   ELECTRIC" if s.electric else ""]
	_bars.stats = s
	_bars.queue_redraw()
	car_shown.emit(e.id)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## Six labelled 10-segment bars.
class StatBars extends Control:
	const ROWS := [["ACCELERATION", "acceleration"], ["TOP SPEED", "top_speed"], ["HANDLING", "handling"],
		["BRAKING", "braking"], ["GRIP", "grip"], ["WEIGHT", "weight"]]
	var stats: Dictionary = {}

	func _draw() -> void:
		if stats.is_empty():
			return
		var font := ThemeDB.fallback_font
		for i in ROWS.size():
			var y := i * 30.0
			var label: String = ROWS[i][0]
			var value: float = stats[ROWS[i][1]]
			draw_string_outline(font, Vector2(0, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(0, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.TEXT)
			for seg in 10:
				var r := Rect2(Vector2(190 + seg * 34, y + 6), Vector2(30, 14))
				var filled := value >= seg + 0.5
				draw_rect(r.grow(1.5), Color(0, 0, 0, 0.55))
				draw_rect(r, MenuStyle.ACCENT if filled else Color(1, 1, 1, 0.14))
