extends SceneTree
## Saves screenshots of the race flow screens (car select for 1 and 2 players,
## track select, race settings) to user://screenshots, with no user input.
## Run windowed with an override.cfg containing window/size/no_focus=true:
##   Godot.exe --path . -s res://tests/screenshot_menus.gd
## The saved settings file is put back afterwards.

const OUT := "user://screenshots"

var _backup: PackedByteArray
var _had_settings := false


func _init() -> void:
	_had_settings = FileAccess.file_exists(GameSettings.PATH)
	if _had_settings:
		_backup = FileAccess.get_file_as_bytes(GameSettings.PATH)
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _frames(20)
	var menu := current_scene
	GameSettings.p1_car = "braxton"
	GameSettings.p2_car = "atmaca"
	GameSettings.track = "spa"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			GameSettings.track = arg.get_slice("=", 1)
	menu._start_flow(1)
	await _frames(90)
	await _save("select_1p")
	var cs := menu.find_children("*", "CarSelect", true, false)[0] as CarSelect
	for i in 3:
		cs._cursor[0] = CarRoster.index_of(["bastion", "piccolo", "mammoth"][i])
		cs._refresh()
		await _frames(30)
		await _save("select_1p_%d" % i)
	menu._start_flow(2)
	await _frames(60)
	cs.choose(0, CarRoster.index_of("braxton"))
	await _frames(40)
	await _save("select_2p")
	cs.choose(1, CarRoster.index_of("atmaca"))
	await _frames(80)
	await _save("track_select")
	var ts := menu.find_children("*", "TrackSelect", true, false)[0] as TrackSelect
	ts._pick()
	await _frames(20)
	await _save("race_settings")

	if _had_settings:
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	print("screenshots saved to ", ProjectSettings.globalize_path(OUT))
	quit()


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
