class_name TournamentSettingsPanel
extends VBoxContainer
## Tournament setup after the car select: which tracks it may use, AI
## difficulty and car classes, time of day, weather and damage.
## START TOURNAMENT is selected first.

signal start
signal back

const TRACK_SETS: PackedStringArray = ["ALL TRACKS", "F1 CIRCUITS", "RALLYCROSS + ISLAND"]

var track_set := 0
var _start_button: Button
var _players := 1


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_theme_constant_override("separation", 6)
	add_child(MenuStyle.label("TOURNAMENT", 46, MenuStyle.ACCENT))
	add_child(MenuStyle.label("6 one-lap races with an upgrade shop between them. The last 3 races decide the champion.", 20, MenuStyle.DIM))
	add_child(MenuStyle.label("No recovery: stuck or upside down = out of that race. Tyres and damage carry over.", 18, MenuStyle.DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	add_child(gap)
	_row("TRACKS", TRACK_SETS, 0, func(i: int) -> void: track_set = i)
	_row("AI DIFFICULTY", GameSettings.DIFFICULTY_NAMES, GameSettings.ai_difficulty, func(i: int) -> void: GameSettings.ai_difficulty = i)
	var tiers := TierToggleRow.create("AI CAR CLASSES", GameSettings.ai_tiers)
	tiers.mask_changed.connect(func(m: int) -> void: GameSettings.ai_tiers = m)
	add_child(tiers)
	_row("TIME OF DAY", GameSettings.TIME_NAMES, GameSettings.time_of_day, func(i: int) -> void: GameSettings.time_of_day = i)
	_row("WEATHER", GameSettings.WEATHER_NAMES, GameSettings.weather, func(i: int) -> void: GameSettings.weather = i)
	_row("DAMAGE", GameSettings.DAMAGE_NAMES, GameSettings.damage, func(i: int) -> void: GameSettings.damage = i)
	_row("TYRE WEAR", GameSettings.TYRE_WEAR_NAMES, GameSettings.tyre_wear, func(i: int) -> void: GameSettings.tyre_wear = i)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	add_child(gap2)
	_start_button = MenuStyle.button("START TOURNAMENT", func() -> void: start.emit())
	_start_button.custom_minimum_size = Vector2(760, 0)
	add_child(_start_button)
	var back_button := MenuStyle.button("BACK", func() -> void: back.emit())
	back_button.custom_minimum_size = Vector2(760, 0)
	add_child(back_button)


func _row(row_title: String, choices: PackedStringArray, start_index: int, apply: Callable) -> void:
	var row := OptionRow.create(row_title, choices, start_index)
	row.custom_minimum_size = Vector2(760, 0)
	row.value_changed.connect(func(i: int) -> void: apply.call(i))
	add_child(row)


func open(players: int) -> void:
	_players = players
	_start_button.grab_focus.call_deferred()


## Track ids for the chosen set.
func track_pool() -> PackedStringArray:
	var out := PackedStringArray()
	for t in TrackList.TRACKS:
		var series := String(t.get("series", ""))
		if track_set == 0 or (track_set == 1 and series == "F1") or (track_set == 2 and series != "F1"):
			out.append(t.id)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()
