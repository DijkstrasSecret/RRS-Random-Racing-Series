class_name PauseMenu
extends CanvasLayer
## Pause menu for every driving mode. Esc (keyboard) or Start (any gamepad)
## freezes the game and opens it; the same key, Esc / B or RESUME closes it.

var _dim: ColorRect
var _panel: PanelContainer
var _main: VBoxContainer
var _settings: SettingsPanel
var _controls: ControlsPanel


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.theme = MenuStyle.make_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var stack := VBoxContainer.new()
	_panel.add_child(stack)

	_main = VBoxContainer.new()
	_main.add_child(MenuStyle.label("PAUSED", 48, MenuStyle.ACCENT))
	_main.add_child(MenuStyle.button("RESUME", resume))
	_main.add_child(MenuStyle.button("RESTART", _restart))
	_main.add_child(MenuStyle.button("SETTINGS", _show_settings))
	_main.add_child(MenuStyle.button("CONTROLS", _show_controls))
	_main.add_child(MenuStyle.button("MAIN MENU", _main_menu))
	_main.add_child(MenuStyle.button("QUIT GAME", func() -> void: get_tree().quit()))
	stack.add_child(_main)

	_settings = SettingsPanel.new()
	_settings.closed.connect(_show_main)
	stack.add_child(_settings)
	_controls = ControlsPanel.new()
	_controls.closed.connect(_show_main)
	stack.add_child(_controls)
	_show_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not visible:
			open()
		elif _main.visible:
			resume()
		else:
			_show_main()
	elif visible and _main.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()


func open() -> void:
	get_tree().paused = true
	visible = true
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)
	_show_main()


func resume() -> void:
	visible = false
	get_tree().paused = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameSettings.MAIN_MENU)


func _show_main() -> void:
	_settings.visible = false
	_controls.visible = false
	_main.visible = true
	if visible:
		MenuStyle.focus_first(_main)


func _show_settings() -> void:
	_main.visible = false
	_settings.visible = true
	_settings.focus_first()


func _show_controls() -> void:
	_main.visible = false
	_controls.visible = true
	_controls.focus_first()
