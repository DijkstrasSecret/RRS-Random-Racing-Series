class_name MenuStyle
extends RefCounted
## Shared look for the menus: clean text over the scene, no boxes. The
## selected item turns yellow with a slim accent line on its left.
## Works with mouse, keyboard and gamepad (Godot's ui_* actions).

const ACCENT := Color(1.0, 0.78, 0.2)
const DARK := Color(0.05, 0.06, 0.08)
const TEXT := Color(1, 1, 1)
const SOFT := Color(1, 1, 1, 0.78)
const DIM := Color(0.8, 0.82, 0.86, 0.85)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 20
	empty.content_margin_right = 20
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.border_width_left = 4
	focus.content_margin_left = 20
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "Button", empty)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", SOFT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_font_size("font_size", "Button", 30)
	t.set_constant("outline_size", "Button", 8)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.7))

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 22)
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))

	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 4)
	return t


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


## Wide letter spacing for titles ("R A C E").
static func spaced(text: String) -> String:
	return " ".join(text.split(""))


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
