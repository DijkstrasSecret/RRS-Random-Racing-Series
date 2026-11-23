extends SceneTree
## Every menu screen in turn (main, game settings, garage, tournament choice,
## car select, track select, race settings, tournament settings, pause) to
## user://screenshots/<prefix>_<screen>.png. Also checks that changing a
## setting doesn't move the race settings rows sideways.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_menu_tour.gd -- --prefix=after

const OUT := "user://screenshots"
var _prefix := "menu"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prefix="):
			_prefix = arg.get_slice("=", 1)
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _frames(120)
	var m := current_scene
	await _shot("main")
	m._show_settings()
	await _frames(20)
	await _shot("settings")
	await _measure(m.find_children("*", "SettingsPanel", true, false)[0] as Control, "game settings")
	m._show_main()
	m._show_garage()
	await _frames(40)
	await _shot("garage")
	await _measure(m.find_children("*", "GaragePanel", true, false)[0] as Control, "garage")
	m._show_main()
	m._show_tournament_choice()
	await _frames(20)
	await _shot("tournament_choice")
	m._show_main()
	m._start_flow(1)
	await _frames(60)
	await _shot("car_select")
	m._show_track_select()
	await _frames(60)
	await _shot("track_select")
	m._show_race_settings()
	await _frames(30)
	await _shot("race_settings")
	# Changing settings must not move the rows.
	var panel := m.find_children("*", "RaceSettingsPanel", true, false)[0] as Control
	var rows := panel.find_children("*", "OptionRow", true, false)
	var x0 := (rows[0] as Control).global_position.x
	var moved := 0.0
	for r: OptionRow in rows:
		for k in r.choices.size():
			r.step(1)
			await _frames(2)
			moved = maxf(moved, absf((rows[0] as Control).global_position.x - x0))
	print("race settings rows moved by up to %.1f px while changing settings" % moved)
	m._show_main()
	m._start_flow(1, true)
	await _frames(30)
	m._show_tournament_settings()
	await _frames(30)
	await _shot("tournament_settings")
	quit()


## Steps every option row through all its values (and back) and reports
## how far the panel's rows moved or the panel changed size.
func _measure(panel: Control, what: String) -> void:
	var rows := panel.find_children("*", "OptionRow", true, false)
	if rows.is_empty():
		print("%s: no option rows" % what)
		return
	var first := rows[0] as Control
	var x0 := first.global_position.x
	var w0 := panel.size.x
	var moved := 0.0
	var grew := 0.0
	for r: OptionRow in rows:
		if r.text.contains("FULLSCREEN") or r.text.contains("STYLE"):
			continue
		for k in r.choices.size():
			r.step(1)
			await _frames(2)
			moved = maxf(moved, absf(first.global_position.x - x0))
			grew = maxf(grew, absf(panel.size.x - w0))
	print("%s: rows moved up to %.1f px, panel width changed up to %.1f px" % [what, moved, grew])


func _shot(screen: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [OUT, _prefix, screen])
	print("saved ", screen)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
