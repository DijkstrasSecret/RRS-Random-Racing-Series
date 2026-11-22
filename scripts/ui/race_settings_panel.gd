class_name RaceSettingsPanel
extends VBoxContainer
## Last step before a race: laps, how many AI opponents, how good they are
## and which car classes they may drive. START RACE is selected first, so
## Enter / A straight away races with the saved settings.

signal start
signal back

var _summary: Label
var _start_button: Button
var _rows: Array[Control] = []


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_theme_constant_override("separation", 6)
	add_child(MenuStyle.label("RACE SETTINGS", 46, MenuStyle.ACCENT))
	_summary = MenuStyle.label("", 20, MenuStyle.DIM)
	add_child(_summary)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	add_child(gap)

	var laps := PackedStringArray()
	for n in GameSettings.LAP_CHOICES:
		laps.append(str(n))
	_add_row("LAP COUNT", laps, maxi(GameSettings.LAP_CHOICES.find(GameSettings.laps), 0),
			func(i: int) -> void: GameSettings.laps = GameSettings.LAP_CHOICES[i])
	_add_row("TIME OF DAY", GameSettings.TIME_NAMES, GameSettings.time_of_day,
			func(i: int) -> void: GameSettings.time_of_day = i)
	_add_row("WEATHER", GameSettings.WEATHER_NAMES, GameSettings.weather,
			func(i: int) -> void: GameSettings.weather = i)
	_add_row("AI DIFFICULTY", GameSettings.DIFFICULTY_NAMES, GameSettings.ai_difficulty,
			func(i: int) -> void: GameSettings.ai_difficulty = i)
	var tiers := TierToggleRow.create("AI CAR CLASSES", GameSettings.ai_tiers)
	tiers.mask_changed.connect(func(m: int) -> void:
		GameSettings.ai_tiers = m
		GameSettings.save()
		_update_summary())
	add_child(tiers)
	_rows.append(tiers)
	var counts := PackedStringArray()
	for n in 8:
		counts.append(str(n))
	_add_row("AI COUNT", counts, GameSettings.ai_count, func(i: int) -> void: GameSettings.ai_count = i)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 22)
	for i in 4:
		legend.add_child(MenuStyle.label("%s  %s" % [CarRoster.TIER_NAMES[i], CarRoster.TIER_TITLES[i]], 17,
				CarRoster.TIER_COLORS[i]))
	add_child(legend)
	add_child(MenuStyle.label("AI cars come from the lit classes. Enter / A switches a class on or off.", 17, MenuStyle.DIM))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	add_child(gap2)
	_start_button = MenuStyle.button("START RACE", func() -> void: start.emit())
	_start_button.custom_minimum_size = Vector2(760, 0)
	add_child(_start_button)
	var back_button := MenuStyle.button("BACK", func() -> void: back.emit())
	back_button.custom_minimum_size = Vector2(760, 0)
	add_child(back_button)


func _add_row(row_title: String, choices: PackedStringArray, start_index: int, apply: Callable) -> void:
	var row := OptionRow.create(row_title, choices, start_index)
	row.custom_minimum_size = Vector2(760, 0)
	row.value_changed.connect(func(i: int) -> void:
		apply.call(i)
		GameSettings.save()
		_update_summary())
	add_child(row)
	_rows.append(row)


func open(players: int) -> void:
	_players = players
	_update_summary()
	_start_button.grab_focus.call_deferred()


var _players := 1


func _update_summary() -> void:
	var cars: String = CarRoster.entry(GameSettings.p1_car).name
	if _players == 2:
		cars = "P1 %s   vs   P2 %s" % [cars, CarRoster.entry(GameSettings.p2_car).name]
	var allowed := PackedStringArray()
	for i in 4:
		if GameSettings.ai_tiers & (1 << i):
			allowed.append(CarRoster.TIER_NAMES[i])
	_summary.text = "%s   ·   %s, %s, %s   ·   AI classes %s (%d cars)" % [
		cars, TrackList.get_track(GameSettings.track).name, GameSettings.TIME_NAMES[GameSettings.time_of_day],
		GameSettings.WEATHER_NAMES[GameSettings.weather], " ".join(allowed),
		CarRoster.ids_in_tiers(GameSettings.ai_tiers).size()]


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()
