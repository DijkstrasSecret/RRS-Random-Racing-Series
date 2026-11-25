extends SceneTree
## Walks through the menus like a player would (keyboard / gamepad actions):
## opening menu -> settings -> change laps -> back -> race (car select, track
## select, race settings) -> pause -> resume -> pause -> main menu -> split
## screen (both players choose at once). Restores the saved settings afterwards.
## Run: Godot_console.exe --headless --path . -s res://tests/menu_test.gd

var _ok := true
var _backup: PackedByteArray
var _had_settings := false


func _init() -> void:
	_had_settings = FileAccess.file_exists(GameSettings.PATH)
	if _had_settings:
		_backup = FileAccess.get_file_as_bytes(GameSettings.PATH)
	_run.call_deferred()


func _run() -> void:
	GameSettings.ensure_loaded()
	GameSettings.ai_tiers = 15  # known start; the saved file is put back at the end
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _frames(30)
	var menu := current_scene
	_check("opening menu loaded", menu != null and menu.name == "MainMenu")
	var setup: RaceSetup = menu.get_node("RaceSetup")
	_check("AI cars race behind the menu (%d)" % setup.ai_vehicles.size(), setup.ai_vehicles.size() == 5)
	var focused := root.gui_get_focus_owner() as Button
	_check("RACE is selected first", focused != null and focused.text == "RACE")

	# Down 7 times to SETTINGS (past TOURNAMENT and OBSTACLE COURSE), then select it.
	for i in 7:
		await _action("ui_down")
	focused = root.gui_get_focus_owner() as Button
	_check("arrow keys move the selection (now %s)" % (focused.text if focused else "nothing"),
			focused != null and focused.text == "SETTINGS")
	await _action("ui_accept")
	var row := root.gui_get_focus_owner() as OptionRow
	_check("settings open with LAPS selected", row != null and row.text == "LAPS")
	var laps_before := GameSettings.laps
	await _action("ui_right")
	_check("right arrow changes laps (%d -> %d)" % [laps_before, GameSettings.laps], GameSettings.laps != laps_before)
	await _action("ui_left")
	_check("left arrow changes it back", GameSettings.laps == laps_before)
	await _action("ui_cancel")
	focused = root.gui_get_focus_owner() as Button
	_check("Esc / B goes back to the main list", focused != null and focused.text == "RACE")

	# The same with a gamepad (second pad): D-pad moves, A selects, B goes back.
	for i in 7:
		await _pad(JOY_BUTTON_DPAD_DOWN, 1)
	await _pad(JOY_BUTTON_A, 1)
	row = root.gui_get_focus_owner() as OptionRow
	_check("gamepad: D-pad + A opens settings", row != null and row.text == "LAPS")
	await _pad(JOY_BUTTON_B, 1)
	focused = root.gui_get_focus_owner() as Button
	_check("gamepad: B goes back to the main list", focused != null and focused.text == "RACE")

	# RACE -> car select -> track select -> race settings -> race.
	await _pad(JOY_BUTTON_A, 0)
	await _frames(5)
	var cs := _find(menu, "CarSelect") as CarSelect
	_check("RACE opens the car select", cs != null and cs.is_visible_in_tree() and cs.players == 1)
	# Livery on / off (Y / R) for a car that has one.
	cs._cursor[0] = CarRoster.index_of("braxton")
	cs._refresh()
	var livery_before := GameSettings.p1_livery
	await _action("menu_alt")
	_check("Y / R switches the livery (%s -> %s)" % [livery_before, GameSettings.p1_livery], GameSettings.p1_livery != livery_before)
	await _pad(JOY_BUTTON_Y, 1)
	_check("gamepad Y switches it back", GameSettings.p1_livery == livery_before)
	var start_car := cs.cursor_of(0)
	await _action("ui_right")
	_check("right arrow moves to the next car", cs.cursor_of(0) == wrapi(start_car + 1, 0, CarRoster.CARS.size()))
	await _action("ui_down")
	await _action("ui_up")
	_check("down then up comes back", cs.cursor_of(0) == wrapi(start_car + 1, 0, CarRoster.CARS.size()))
	var picked: String = CarRoster.CARS[cs.cursor_of(0)].id
	await _pad(JOY_BUTTON_A, 1)
	await _frames(20)
	var ts := _find(menu, "TrackSelect") as TrackSelect
	_check("gamepad A picks the car, track select opens (%s saved)" % picked, ts != null and ts.is_visible_in_tree() and GameSettings.p1_car == picked)
	await _action("ui_cancel")
	_check("back goes to the car select", cs.is_visible_in_tree() and not ts.is_visible_in_tree())
	await _action("ui_accept")
	await _frames(20)
	await _action("ui_right")
	var track := ts.selected_id()
	await _action("ui_accept")
	var rs := _find(menu, "RaceSettingsPanel") as RaceSettingsPanel
	_check("track %s picked, race settings open" % track, rs != null and rs.is_visible_in_tree() and GameSettings.track == track)
	focused = root.gui_get_focus_owner() as Button
	_check("START RACE is selected", focused != null and focused.text == "START RACE")
	var tiers := _find(rs, "TierToggleRow") as TierToggleRow
	for i in [1, 2, 3]:
		tiers.toggle(i)
	tiers.toggle(0)  # last class can't be switched off
	_check("AI classes: only D left on (mask %d)" % GameSettings.ai_tiers, GameSettings.ai_tiers == 1)
	GameSettings.ai_count = 5  # (the player's own settings may have no AI)
	await _action("ui_accept")
	await _frames(40)
	_check("race scene loaded", current_scene != null and current_scene.name == "CircuitRace")
	_check("race is on %s" % track, (current_scene.get_node("Circuit") as Circuit).track_name.to_upper() == TrackList.get_track(track).name)
	var player_car := current_scene.get_node("Vehicle") as Vehicle
	_check("player drives the chosen car", player_car.get_meta(&"car_id", "") == picked)
	var race_setup := current_scene.get_node("RaceSetup") as RaceSetup
	var all_d := race_setup.ai_vehicles.size() > 0
	for v in race_setup.ai_vehicles:
		if CarRoster.tier(v.get_meta(&"car_id")) != 0:
			all_d = false
	_check("AI cars are all class D (%d cars, ai_count %d, tiers %d)" % [race_setup.ai_vehicles.size(), GameSettings.ai_count, GameSettings.ai_tiers], all_d)
	var pause := current_scene.get_tree().get_first_node_in_group("pause_menu") as PauseMenu
	_check("race has a pause menu", pause != null)
	await _action("pause")
	_check("Esc / Start pauses the game", paused and pause.visible)
	focused = root.gui_get_focus_owner() as Button
	_check("RESUME is selected", focused != null and focused.text == "RESUME")
	await _action("pause")
	_check("pressing it again resumes", not paused and not pause.visible)
	await _action("pause")
	for i in 4:
		await _action("ui_down")
	focused = root.gui_get_focus_owner() as Button
	_check("can reach MAIN MENU (%s)" % (focused.text if focused else "nothing"),
			focused != null and focused.text == "MAIN MENU")
	await _action("ui_accept")
	await _frames(30)
	_check("back at the opening menu, unpaused", current_scene != null and current_scene.name == "MainMenu" and not paused)

	# Split screen: both players choose at the same time.
	menu = current_scene
	await _action("ui_down")
	focused = root.gui_get_focus_owner() as Button
	_check("SPLIT SCREEN selected", focused != null and focused.text == "SPLIT SCREEN")
	await _action("ui_accept")
	await _frames(5)
	cs = _find(menu, "CarSelect") as CarSelect
	_check("two-player car select", cs.is_visible_in_tree() and cs.players == 2)
	var p2_start := cs.cursor_of(1)
	await _action("p1_menu_right")
	_check("player 1's keys move only player 1", cs.cursor_of(1) == p2_start)
	await _action("p2_menu_down")
	var p2_pick: String = CarRoster.CARS[cs.cursor_of(1)].id
	await _action("p1_menu_accept")
	_check("player 1 ready, waiting for player 2", cs.is_locked(0) and cs.is_visible_in_tree())
	await _action("p2_menu_accept")
	await _frames(120)
	ts = _find(menu, "TrackSelect") as TrackSelect
	_check("both ready -> track select (P2 car %s)" % p2_pick, ts.is_visible_in_tree() and GameSettings.p2_car == p2_pick)
	await _action("ui_accept")
	await _action("ui_accept")
	await _frames(40)
	_check("split-screen race loaded", current_scene != null and current_scene.name == "VersusRace")
	var car2 := current_scene.get_node("Car2") as Vehicle
	_check("player 2 drives their car", car2.get_meta(&"car_id", "") == p2_pick)

	# Put the player's saved settings back.
	if _had_settings:
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	elif FileAccess.file_exists(GameSettings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	print("menu_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _find(from: Node, cls: String) -> Node:
	for n in from.find_children("*", cls, true, false):
		return n
	return null


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _action(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


func _pad(button: JoyButton, device: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var up := InputEventJoypadButton.new()
	up.device = device
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
