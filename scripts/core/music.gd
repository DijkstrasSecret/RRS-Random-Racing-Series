class_name MusicPlayer
extends Node
## Background music (autoload "Music"), kept playing across scene changes.
## - Opening menu: res://soundtrack/starting_menu_soundtrack.mp3 on a loop.
## - Races: every other track in res://soundtrack/, shuffled, one after another.
## Fades between tracks and turns down while the game is paused.
## Plays on the "Music" audio bus (volume from GameSettings.music_volume).

const FOLDER := "res://soundtrack/"
const MENU_TRACK := "starting_menu_soundtrack"
const FADE_TIME := 0.8

var _player: AudioStreamPlayer
var _race_tracks: PackedStringArray = []
var _queue: Array[String] = []
var _mode: String = ""
var _last_track: String = ""
var _tween: Tween
var _switching: bool = false

## The running music player (the autoload), for the static helpers below.
static var instance: MusicPlayer


## Plays the menu music, if the Music autoload exists.
static func start_menu() -> void:
	if instance:
		instance.play_menu()


## Plays the next race track, if the Music autoload exists.
static func start_race() -> void:
	if instance:
		instance.play_race()


## Lowers the music (true), e.g. while paused, or brings it back (false).
static func duck(ducked: bool) -> void:
	if instance:
		instance.set_ducked(ducked)


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.finished.connect(_on_finished)
	add_child(_player)
	for file in ResourceLoader.list_directory(FOLDER):
		var ext := file.get_extension().to_lower()
		if ext in ["mp3", "ogg", "wav"] and not file.get_basename().begins_with(MENU_TRACK):
			_race_tracks.append(FOLDER + file)


## Loop the menu theme (does nothing if it is already playing).
func play_menu() -> void:
	if _mode == "menu":
		return
	_mode = "menu"
	for file in ResourceLoader.list_directory(FOLDER):
		if file.get_basename() == MENU_TRACK:
			_switch_to(FOLDER + file, true)
			return


## Shuffled race tracks (keeps the current one if race music is already on).
func play_race() -> void:
	if _mode == "race":
		return
	_mode = "race"
	_next_race_track()


## Quieter while the pause menu is open.
func set_ducked(ducked: bool) -> void:
	if _switching:
		return
	_fade_to(-12.0 if ducked else 0.0, 0.3)


func _next_race_track() -> void:
	if _race_tracks.is_empty():
		return
	if _queue.is_empty():
		for t in _race_tracks:
			_queue.append(t)
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _last_track:
			_queue.append(_queue.pop_front())  # never the same track twice in a row
	_switch_to(_queue.pop_front(), false)


func _switch_to(path: String, loop: bool) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_last_track = path
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_switching = true
	if _player.playing:
		_tween.tween_property(_player, "volume_db", -40.0, FADE_TIME * 0.5)
	_tween.tween_callback(func() -> void:
		_player.stream = stream
		_player.volume_db = -40.0
		_player.play())
	_tween.tween_property(_player, "volume_db", 0.0, FADE_TIME)
	_tween.tween_callback(func() -> void: _switching = false)


func _fade_to(db: float, time: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, time)


func _on_finished() -> void:
	if _mode == "race":
		_next_race_track()
	elif _mode == "menu":
		_player.play()
