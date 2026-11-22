class_name RetroLook
extends CanvasLayer
## Switchable retro visual style. V cycles Modern -> PS2 -> PS1 (PS2 default).
## The screen effect lives here; it also tweaks the scene's environment
## (glow, colour) and tells nodes in the "retro_aware" group to swap their
## materials via set_retro_level(level).

enum Level { MODERN, PS2, PS1 }
const LEVEL_NAMES: PackedStringArray = ["Modern", "PS2", "PS1"]

## Current look, readable from anywhere (HUD). Kept when switching tracks.
static var level: int = Level.PS2
static var _initialised := false

@export var start_level: Level = Level.PS2

var _rect: ColorRect
var _material: ShaderMaterial
var _env: Environment
var _env_defaults: Dictionary = {}


static func level_name() -> String:
	return LEVEL_NAMES[level]


## Internal resolution for a look (matches the screen's 16:9 shape).
static func resolution_for(look: int) -> Vector2:
	return Vector2(640.0, 360.0) if look == Level.PS2 else Vector2(426.0, 240.0)


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
	if not _initialised:
		level = start_level
		_initialised = true
	# Wait one frame so the track and vehicles have finished setting up.
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
		_material.set_shader_parameter("smooth_upscale", 0.0)
	else:
		_material.set_shader_parameter("color_levels", 48.0)
		_material.set_shader_parameter("dither_strength", 0.45)
		_material.set_shader_parameter("smooth_upscale", 1.0)
	_apply_environment()
	get_tree().call_group("retro_aware", "set_retro_level", level)


## PS2-era games loved a soft glow and punchy colour.
func _apply_environment() -> void:
	if _env == null:
		var world_env := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
		if world_env == null or world_env.environment == null:
			return
		_env = world_env.environment
		for key: String in ["glow_enabled", "adjustment_enabled", "adjustment_saturation",
				"adjustment_contrast", "fog_density"]:
			_env_defaults[key] = _env.get(key)
	for key: String in _env_defaults:
		_env.set(key, _env_defaults[key])
	if level == Level.PS2:
		_env.glow_enabled = true
		_env.glow_intensity = 0.7
		_env.glow_bloom = 0.06
		_env.glow_hdr_threshold = 0.9
		_env.adjustment_enabled = true
		_env.adjustment_saturation = 1.15
		_env.adjustment_contrast = 1.06
		_env.fog_density = _env_defaults["fog_density"] * 1.4
	elif level == Level.PS1:
		_env.fog_density = _env_defaults["fog_density"] * 2.0
