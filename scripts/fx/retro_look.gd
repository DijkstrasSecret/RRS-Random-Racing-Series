class_name RetroLook
extends CanvasLayer
## Switchable retro visual style (look test). V cycles Modern -> PS2-ish -> PS1.
## The screen effect lives here; nodes in the "retro_aware" group get
## set_retro_level(level) so they can swap their own materials.

enum Level { MODERN, PS2, PS1 }
const LEVEL_NAMES: PackedStringArray = ["Modern", "PS2-ish", "PS1"]

## Current look, readable from anywhere (HUD).
static var level: int = Level.PS1

@export var start_level: Level = Level.PS1

var _rect: ColorRect
var _material: ShaderMaterial


static func level_name() -> String:
	return LEVEL_NAMES[level]


## Internal resolution for a look (matches the screen's 16:9 shape).
static func resolution_for(look: int) -> Vector2:
	return Vector2(854.0, 480.0) if look == Level.PS2 else Vector2(426.0, 240.0)


func _ready() -> void:
	layer = 1
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/vfx/shaders/psx_post.gdshader")
	_rect = ColorRect.new()
	_rect.name = "RetroScreen"
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	level = start_level
	# Wait one frame so every vehicle has finished setting up its model.
	_apply.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_look"):
		level = (level + 1) % LEVEL_NAMES.size()
		_apply()


func _apply() -> void:
	_rect.visible = level != Level.MODERN
	_material.set_shader_parameter("virtual_resolution", resolution_for(level))
	if level == Level.PS1:
		_material.set_shader_parameter("color_levels", 32.0)
		_material.set_shader_parameter("dither_strength", 1.0)
	else:
		_material.set_shader_parameter("color_levels", 64.0)
		_material.set_shader_parameter("dither_strength", 0.5)
	get_tree().call_group("retro_aware", "set_retro_level", level)
