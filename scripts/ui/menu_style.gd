class_name MenuStyle
extends RefCounted
## Shared look for the menus: bold, high-contrast motorsport style
## (design concept §12) with a yellow highlight on the selected item.
## Works with mouse, keyboard and gamepad (Godot's ui_* actions).

const ACCENT := Color(1.0, 0.78, 0.2)
const DARK := Color(0.05, 0.06, 0.08)
const TEXT := Color(1, 1, 1)
const DIM := Color(0.72, 0.74, 0.78)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24

	var normal := _box(Color(0.0, 0.0, 0.0, 0.55))
	var hover := _box(Color(1.0, 0.78, 0.2, 0.25))
	var focus := _box(Color(1.0, 0.78, 0.2, 0.3))
	focus.border_color = ACCENT
	focus.border_width_left = 6
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2
	var pressed := _box(ACCENT)
	for state: String in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", DARK)
	t.set_color("font_pressed_color", "Button", DARK)
	t.set_font_size("font_size", "Button", 26)
	t.set_constant("outline_size", "Button", 4)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 22)
	t.set_constant("outline_size", "Label", 6)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))

	var panel := _box(Color(0.03, 0.04, 0.06, 0.82))
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_constant("separation", "VBoxContainer", 8)
	return t


static func _box(color: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.content_margin_left = 22
	b.content_margin_right = 22
	b.content_margin_top = 7
	b.content_margin_bottom = 7
	b.corner_radius_top_left = 3
	b.corner_radius_top_right = 3
	b.corner_radius_bottom_left = 3
	b.corner_radius_bottom_right = 3
	return b


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 0)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	# Mouse hover and keyboard/gamepad selection look the same.
	b.mouse_entered.connect(b.grab_focus)
	return b


static func label(text: String, font_size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Focus the first button in `container` (needed for keyboard / gamepad).
## Deferred, so it also works while the menu is still being built.
static func focus_first(container: Node) -> void:
	_focus_first_now.call_deferred(container)


static func _focus_first_now(container: Node) -> void:
	if not is_instance_valid(container):
		return
	for child in container.get_children():
		if child is Button and child.visible:
			child.grab_focus()
			return
