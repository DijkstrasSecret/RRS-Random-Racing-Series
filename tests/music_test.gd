extends SceneTree
## Checks the music: menu theme on the opening menu, shuffled race tracks
## in a race, and the pause menu ducking the volume.
## Run: Godot_console.exe --headless --path . -s res://tests/music_test.gd

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var music := root.get_node("Music")
	print("  race tracks found: %d" % music._race_tracks.size())
	for t in music._race_tracks:
		print("    ", t.get_file())
	_check("4 race tracks, menu theme not among them", music._race_tracks.size() == 4
			and not music._race_tracks.has("res://soundtrack/starting_menu_soundtrack.mp3"))
	change_scene_to_file(GameSettings.MAIN_MENU)
	await _frames(60)
	_check("menu plays starting_menu_soundtrack (%s)" % music._last_track.get_file(),
			music._mode == "menu" and music._last_track.ends_with("starting_menu_soundtrack.mp3") and music._player.playing)
	change_scene_to_file(GameSettings.RACE)
	await _frames(90)
	_check("race plays a race track (%s)" % music._last_track.get_file(),
			music._mode == "race" and music._race_tracks.has(music._last_track) and music._player.playing)
	var first: String = music._last_track
	music._on_finished()
	await _frames(90)
	_check("next race track follows (%s)" % music._last_track.get_file(), music._last_track != first)
	print("music_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	_ok = _ok and ok


func _frames(n: int) -> void:
	for i in n:
		await process_frame
