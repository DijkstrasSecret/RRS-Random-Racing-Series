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
var _summary: Label
var _title: VBoxContainer
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
	_main.add_child(MenuStyle.button("RACE", func() -> void: _go(GameSettings.RACE)))
	_main.add_child(MenuStyle.button("SPLIT SCREEN", func() -> void: _go(GameSettings.VERSUS)))
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

	var hint := MenuStyle.label("Arrows / D-pad: choose      Enter / A: select      Esc / B: back", 18, MenuStyle.DIM)
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
	_settings.visible = false
	_controls.visible = false
	_main.visible = true
	_title.visible = true
	_summary.visible = true
	_summary.text = "%d laps  ·  %d AI opponents (%s)  ·  %s handling" % [
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


func _show_controls() -> void:
	_main.visible = false
	_title.visible = false
	_summary.visible = false
	_controls.visible = true
	_controls.focus_first()


func _go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
