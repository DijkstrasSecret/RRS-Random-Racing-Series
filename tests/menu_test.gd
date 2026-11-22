extends SceneTree
## Walks through the menus like a player would (keyboard / gamepad actions):
## opening menu -> settings -> change laps -> back -> race -> pause ->
## resume -> pause -> main menu. Restores the saved settings afterwards.
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
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _frames(30)
	var menu := current_scene
	_check("opening menu loaded", menu != null and menu.name == "MainMenu")
	var setup: RaceSetup = menu.get_node("RaceSetup")
	_check("AI cars race behind the menu (%d)" % setup.ai_vehicles.size(), setup.ai_vehicles.size() == 5)
	var focused := root.gui_get_focus_owner() as Button
	_check("RACE is selected first", focused != null and focused.text == "RACE")

	# Down 4 times to SETTINGS, then select it.
	for i in 4:
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

	# Start a race.
	await _action("ui_accept")
	await _frames(40)
	_check("race scene loaded", current_scene != null and current_scene.name == "CircuitRace")
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

	# Put the player's saved settings back.
	if _had_settings:
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	elif FileAccess.file_exists(GameSettings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	print("menu_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame
