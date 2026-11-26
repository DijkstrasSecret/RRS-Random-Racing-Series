class_name GameSettings
extends RefCounted
## Player settings, shared by every scene and saved to user://settings.cfg.
## Menus change them; races, cars and the visual style read them.

const PATH := "user://settings.cfg"

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const RACE := "res://scenes/modes/circuit_race.tscn"
const VERSUS := "res://scenes/modes/versus_race.tscn"
const PRACTICE := "res://scenes/modes/circuit_practice.tscn"
const TEST_TRACK := "res://scenes/modes/free_roam.tscn"
const OBSTACLE_COURSE := "res://scenes/modes/obstacle_course.tscn"

const LAP_CHOICES: PackedInt32Array = [1, 2, 3, 5, 10]
const TIME_NAMES: PackedStringArray = ["MORNING", "NOON", "SUNSET", "NIGHT"]
const WEATHER_NAMES: PackedStringArray = ["CLEAR", "HAZY", "FOG"]
const DIFFICULTY_NAMES: PackedStringArray = ["EASY", "NORMAL", "HARD"]
## AI skill range (min, max) for each difficulty.
const DIFFICULTY_SKILLS: Array[Vector2] = [Vector2(0.3, 0.6), Vector2(0.5, 0.82), Vector2(0.75, 1.0)]

static var laps: int = 3
static var ai_count: int = 5
static var ai_difficulty: int = 1
static var handling_profile: int = 1  ## 0 Arcade, 1 Sport, 2 Sim
static var look: int = 2  ## 1 PS2, 2 PS1 (0 = old Modern look, no longer offered)
static var fullscreen: bool = false
static var vibration: bool = true
## Camera field of view (degrees) when standing still.
static var fov: float = 64.0
## How much the view widens at speed: 0 = not at all, 100 = +28 degrees.
static var speed_fov: float = 100.0
## Strength of the PS1 / PS2 screen effect (low resolution, few colours,
## dithering): 0 = sharp full-resolution picture, 100 = the full retro look.
static var retro_strength: float = 100.0
## Camera rumble and edge blur at speed.
static var speed_fx: bool = true
## Lens bend, 0..100 (single player only); 100 = a strong barrel.
static var fisheye: float = 35.0
const FISHEYE_MAX := 0.2
static var sound_volume: int = 8  ## 0..10, engines and effects
static var music_volume: int = 6  ## 0..10
static var p1_car: String = "bavaro"
static var p2_car: String = "quadra"
## Racing livery on the players' cars (cars that have one).
static var p1_livery: bool = true
static var p2_livery: bool = true
static var track: String = "monza"
## Car classes the AI may drive: bit 0 = D ... bit 3 = A.
static var ai_tiers: int = 15
## 0 morning, 1 noon, 2 sunset, 3 night.
static var time_of_day: int = 2
## 0 clear, 1 hazy, 2 fog.
static var weather: int = 0
## Crash damage: 0 off, 1 visual only, 2 visual + handling.
static var damage: int = 2
## Tyre heat and wear: 0 off, 1 normal, 2 fast.
## Tyre wear speed in percent of normal (0 = off).
static var tyre_wear: float = 100.0
## Car toughness in percent: 200 = takes half the crash damage.
static var durability: float = 100.0
const DAMAGE_NAMES: PackedStringArray = ["OFF", "VISUAL", "FULL"]

static var _loaded: bool = false


## Reads the saved settings once per run.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		apply_volume()
		return
	laps = cfg.get_value("race", "laps", laps)
	ai_count = cfg.get_value("race", "ai_count", ai_count)
	ai_difficulty = cfg.get_value("race", "ai_difficulty", ai_difficulty)
	handling_profile = cfg.get_value("car", "handling_profile", handling_profile)
	vibration = cfg.get_value("car", "vibration", vibration)
	sound_volume = cfg.get_value("audio", "sound", sound_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	p1_car = cfg.get_value("garage", "p1_car", p1_car)
	p2_car = cfg.get_value("garage", "p2_car", p2_car)
	p1_livery = cfg.get_value("garage", "p1_livery", p1_livery)
	p2_livery = cfg.get_value("garage", "p2_livery", p2_livery)
	track = cfg.get_value("race", "track", track)
	if TrackList.ids().find(track) == -1:
		track = "monza"  # an old track that no longer exists
	ai_tiers = cfg.get_value("race", "ai_tiers", ai_tiers)
	if CarRoster.ids().find(p1_car) == -1:
		p1_car = "bavaro"
	if CarRoster.ids().find(p2_car) == -1:
		p2_car = "quadra"
	look = cfg.get_value("video", "look", look)
	fov = clampf(float(cfg.get_value("video", "fov", fov)), 50.0, 85.0)
	speed_fov = clampf(float(cfg.get_value("video", "speed_fov", speed_fov)), 0.0, 100.0)
	speed_fx = cfg.get_value("video", "speed_fx", speed_fx)
	retro_strength = clampf(float(cfg.get_value("video", "retro_strength", retro_strength)), 0.0, 100.0)
	fisheye = clampf(float(cfg.get_value("video", "fisheye_amount", fisheye)), 0.0, 100.0)
	if look < 1 or look > 2:
		look = 2
	time_of_day = clampi(cfg.get_value("race", "time_of_day", time_of_day), 0, 3)
	weather = clampi(cfg.get_value("race", "weather", weather), 0, 2)
	damage = clampi(cfg.get_value("race", "damage", damage), 0, 2)
	# (tyre_wear used to be 0 / 1 / 2 = off / normal / fast)
	if cfg.has_section_key("race", "tyre_wear_pct"):
		tyre_wear = clampf(float(cfg.get_value("race", "tyre_wear_pct")), 0.0, 300.0)
	else:
		tyre_wear = [0.0, 100.0, 200.0][clampi(int(cfg.get_value("race", "tyre_wear", 1)), 0, 2)]
	durability = clampf(float(cfg.get_value("race", "durability", durability)), 25.0, 300.0)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	if fullscreen:
		apply_window()
	apply_volume()


## Tests call this so the saved file doesn't change their results.
static func use_defaults() -> void:
	_loaded = true


## Writes every setting to user://settings.cfg.
static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("race", "laps", laps)
	cfg.set_value("race", "ai_count", ai_count)
	cfg.set_value("race", "ai_difficulty", ai_difficulty)
	cfg.set_value("car", "handling_profile", handling_profile)
	cfg.set_value("car", "vibration", vibration)
	cfg.set_value("video", "look", look)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "speed_fov", speed_fov)
	cfg.set_value("video", "speed_fx", speed_fx)
	cfg.set_value("video", "retro_strength", retro_strength)
	cfg.set_value("video", "fisheye_amount", fisheye)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "sound", sound_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("garage", "p1_car", p1_car)
	cfg.set_value("garage", "p2_car", p2_car)
	cfg.set_value("garage", "p1_livery", p1_livery)
	cfg.set_value("garage", "p2_livery", p2_livery)
	cfg.set_value("race", "track", track)
	cfg.set_value("race", "ai_tiers", ai_tiers)
	cfg.set_value("race", "time_of_day", time_of_day)
	cfg.set_value("race", "weather", weather)
	cfg.set_value("race", "damage", damage)
	cfg.set_value("race", "tyre_wear_pct", tyre_wear)
	cfg.set_value("race", "durability", durability)
	cfg.save(PATH)


## AI skill range (min, max), 0–1, for the chosen AI difficulty.
static func ai_skill_range() -> Vector2:
	return DIFFICULTY_SKILLS[clampi(ai_difficulty, 0, DIFFICULTY_SKILLS.size() - 1)]


## Makes sure the "Music" and "SFX" buses exist (both feed Master).
static func ensure_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, &"Master")


## Sets the SFX and Music bus volumes from sound_volume and music_volume (0–10).
static func apply_volume() -> void:
	ensure_buses()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sound_volume / 10.0, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume / 10.0, 0.0001)))


## Applies the fullscreen setting (fullscreen or maximised window). Does nothing headless.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED)


## Applies the settings that can change mid-game (look, handling, window).
static func apply_live(tree: SceneTree) -> void:
	apply_window()
	apply_volume()
	for node in tree.get_nodes_in_group("retro_look"):
		node.set_level(look)
	for node in tree.get_nodes_in_group("vehicles"):
		var car := node as Vehicle
		if car and car.input is PlayerInput:
			car.set_handling_profile(handling_profile)
