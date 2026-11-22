class_name SettingsPanel
extends VBoxContainer
## Settings page used by the opening menu and the pause menu.
## Every change is applied straight away (where possible) and saved.

signal closed

var _rows: Array[Control] = []


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_child(MenuStyle.label("SETTINGS", 40, MenuStyle.ACCENT))

	var laps := PackedStringArray()
	for n in GameSettings.LAP_CHOICES:
		laps.append(str(n))
	_add_row("LAPS", laps, maxi(GameSettings.LAP_CHOICES.find(GameSettings.laps), 0),
			func(i: int) -> void: GameSettings.laps = GameSettings.LAP_CHOICES[i])
	var counts := PackedStringArray()
	for n in 8:
		counts.append(str(n))
	_add_row("AI OPPONENTS", counts, GameSettings.ai_count,
			func(i: int) -> void: GameSettings.ai_count = i)
	_add_row("AI DIFFICULTY", GameSettings.DIFFICULTY_NAMES, GameSettings.ai_difficulty,
			func(i: int) -> void: GameSettings.ai_difficulty = i)
	_add_row("HANDLING", PackedStringArray(["ARCADE", "SPORT", "SIM"]), GameSettings.handling_profile,
			func(i: int) -> void: GameSettings.handling_profile = i)
	_add_row("VISUAL STYLE", PackedStringArray(["PS2", "PS1"]), clampi(GameSettings.look - 1, 0, 1),
			func(i: int) -> void: GameSettings.look = i + 1)
	_add_row("FULLSCREEN", PackedStringArray(["OFF", "ON"]), int(GameSettings.fullscreen),
			func(i: int) -> void: GameSettings.fullscreen = i == 1)
	var volumes := PackedStringArray()
	for n in 11:
		volumes.append(str(n))
	_add_row("MUSIC VOLUME", volumes, GameSettings.music_volume,
			func(i: int) -> void: GameSettings.music_volume = i)
	_add_row("SOUND VOLUME", volumes, GameSettings.sound_volume,
			func(i: int) -> void: GameSettings.sound_volume = i)
	_add_row("VIBRATION", PackedStringArray(["OFF", "ON"]), int(GameSettings.vibration),
			func(i: int) -> void: GameSettings.vibration = i == 1)

	add_child(MenuStyle.label("Laps, AI opponents and difficulty apply to the next race.", 18, MenuStyle.DIM))
	var back := MenuStyle.button("BACK", func() -> void: closed.emit())
	back.custom_minimum_size = Vector2(560, 0)
	add_child(back)
	_rows.append(back)


func _add_row(row_title: String, choices: PackedStringArray, start: int, apply: Callable) -> void:
	var row := OptionRow.create(row_title, choices, start)
	row.value_changed.connect(func(i: int) -> void:
		apply.call(i)
		GameSettings.save()
		GameSettings.apply_live(get_tree()))
	add_child(row)
	_rows.append(row)


func focus_first() -> void:
	if _rows.size() > 0:
		_rows[0].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
