extends Node3D
## Opening menu. AI cars race round the circuit behind it while the camera
## follows a different car every few seconds (attract mode).
## Mouse, keyboard (arrows / Enter / Esc) and gamepad (stick or D-pad / A / B).

@export var showcase_switch_time: float = 9.0

var _camera: ChaseCamera
var _setup: RaceSetup
var _main: VBoxContainer
var _settings: SettingsPanel
var _controls: ControlsPanel
var _garage: GaragePanel
var _preview: CarPreview
var _summary: Label
var _title: VBoxContainer
var _hint: Label
var _fade: TextureRect
## Race flow: car select -> track select -> race settings -> race.
var _flow: Control
var _car_select: CarSelect
var _track_select: TrackSelect
var _race_settings: RaceSettingsPanel
var _flow_players := 1
var _showcase_index: int = -1
var _showcase_timer: float = 0.0


func _enter_tree() -> void:
	InputActions.ensure()
	GameSettings.ensure_loaded()


func _ready() -> void:
	get_tree().paused = false
	MusicPlayer.start_menu()
	_camera = $ChaseCamera
	_camera.mode = ChaseCamera.Mode.FAR
	_setup = $RaceSetup
	_build_ui()


func _process(delta: float) -> void:
	if _setup.ai_vehicles.is_empty():
		return
	_showcase_timer -= delta
	if _showcase_timer <= 0.0:
		_showcase_timer = showcase_switch_time
		_showcase_index = (_showcase_index + 1) % _setup.ai_vehicles.size()
		_camera.set_target(_setup.ai_vehicles[_showcase_index])
		# Background cars a bit quieter than in a race.
		get_tree().call_group("car_audio", "set_gain", -9.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.theme = MenuStyle.make_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Dark fade on the left so the menu reads well over the 3D scene.
	var fade := TextureRect.new()
	_fade = fade
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = grad
	fade_tex.fill_to = Vector2(1, 0)
	fade.texture = fade_tex
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fade.custom_minimum_size = Vector2(1000, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_title = VBoxContainer.new()
	var big := MenuStyle.label("RRS", 150, MenuStyle.ACCENT)
	big.add_theme_constant_override("outline_size", 14)
	_title.add_child(big)
	_title.add_child(MenuStyle.label(MenuStyle.spaced("RANDOM RACING SERIES"), 22, MenuStyle.TEXT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 46)
	_title.add_child(gap)
	column.add_child(_title)

	_main = VBoxContainer.new()
	_main.add_child(MenuStyle.button("RACE", func() -> void: _start_flow(1)))
	_main.add_child(MenuStyle.button("SPLIT SCREEN", func() -> void: _start_flow(2)))
	_main.add_child(MenuStyle.button("GARAGE", _show_garage))
	_main.add_child(MenuStyle.button("PRACTICE", func() -> void: _go(GameSettings.PRACTICE)))
	_main.add_child(MenuStyle.button("TEST TRACK", func() -> void: _go(GameSettings.TEST_TRACK)))
	_main.add_child(MenuStyle.button("SETTINGS", _show_settings))
	_main.add_child(MenuStyle.button("CONTROLS", _show_controls))
	_main.add_child(MenuStyle.button("QUIT", func() -> void: get_tree().quit()))
	column.add_child(_main)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	column.add_child(gap2)
	_summary = MenuStyle.label("", 18, MenuStyle.DIM)
	column.add_child(_summary)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_show_main)
	column.add_child(_settings)
	_controls = ControlsPanel.new()
	_controls.visible = false
	_controls.closed.connect(_show_main)
	column.add_child(_controls)
	_garage = GaragePanel.new()
	_garage.visible = false
	_garage.closed.connect(_show_main)
	column.add_child(_garage)
	_preview = CarPreview.new()
	_preview.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_preview.anchor_left = 0.42
	_preview.offset_left = 0
	_preview.offset_top = 120
	_preview.offset_bottom = -120
	_preview.visible = false
	root.add_child(_preview)
	_garage.car_shown.connect(_preview.show_car)

	_build_flow(root)

	var hint := MenuStyle.label("Arrows / D-pad: choose      Enter / A: select      Esc / B: back", 18, MenuStyle.DIM)
	_hint = hint
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(110, -50)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)
	var version := MenuStyle.label("Prototype  ·  Godot %s" % Engine.get_version_info().string, 16, MenuStyle.DIM)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position += Vector2(-30, -40)
	root.add_child(version)

	_show_main()


func _show_main() -> void:
	_flow.visible = false
	_fade.visible = true
	_hint.visible = true
	_settings.visible = false
	_controls.visible = false
	_garage.visible = false
	_preview.visible = false
	_main.visible = true
	_title.visible = true
	_summary.visible = true
	_summary.text = "%s  ·  %s  ·  %d laps  ·  %d AI opponents (%s)  ·  %s handling" % [
		CarRoster.entry(GameSettings.p1_car).name.capitalize(), String(TrackList.get_track(GameSettings.track).name).capitalize(),
		GameSettings.laps, GameSettings.ai_count,
		GameSettings.DIFFICULTY_NAMES[GameSettings.ai_difficulty].to_lower(),
		HandlingAssists.PROFILE_NAMES[GameSettings.handling_profile]]
	MenuStyle.focus_first(_main)


func _show_settings() -> void:
	_main.visible = false
	_title.visible = false
	_summary.visible = false
	_settings.visible = true
	_settings.focus_first()


func _show_garage() -> void:
	_main.visible = false
	_title.visible = false
	_summary.visible = false
	_garage.visible = true
	_preview.visible = true
	_garage.focus_first()


func _show_controls() -> void:
	_main.visible = false
	_title.visible = false
	_summary.visible = false
	_controls.visible = true
	_controls.focus_first()


func _build_flow(root: Control) -> void:
	_flow = Control.new()
	_flow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flow.visible = false
	root.add_child(_flow)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.add_child(dim)
	_car_select = CarSelect.new()
	_car_select.done.connect(_show_track_select)
	_car_select.back.connect(_show_main)
	_flow.add_child(_car_select)
	_track_select = TrackSelect.new()
	_track_select.done.connect(_show_race_settings)
	_track_select.back.connect(func() -> void:
		_car_select.unlock_all()
		_show_car_select())
	_flow.add_child(_track_select)
	_race_settings = RaceSettingsPanel.new()
	_race_settings.position = Vector2(560, 150)
	_race_settings.start.connect(func() -> void:
		GameSettings.save()
		_go(GameSettings.VERSUS if _flow_players == 2 else GameSettings.RACE))
	_race_settings.back.connect(_show_track_select)
	_flow.add_child(_race_settings)


func _start_flow(players: int) -> void:
	_flow_players = players
	_car_select.open(players)
	_show_car_select()


func _hide_menu_column() -> void:
	_main.visible = false
	_title.visible = false
	_summary.visible = false
	_fade.visible = false
	_hint.visible = false
	_flow.visible = true


func _show_car_select() -> void:
	_hide_menu_column()
	_track_select.visible = false
	_race_settings.visible = false
	_car_select.visible = true
	# Leave the menu's selection so the arrow keys don't also move it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()


func _show_track_select() -> void:
	_hide_menu_column()
	_car_select.visible = false
	_race_settings.visible = false
	_track_select.visible = true
	_track_select.open()
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()


func _show_race_settings() -> void:
	_hide_menu_column()
	_car_select.visible = false
	_track_select.visible = false
	_race_settings.visible = true
	_race_settings.open(_flow_players)


func _go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
