class_name RetroLook
extends CanvasLayer
## Switchable retro visual style. V switches PS2 <-> PS1 (PS1 default).
## (The old Modern level still exists in the code but is no longer offered.)
## The screen effect lives here; it also tweaks the scene's environment
## (glow, colour) and tells nodes in the "retro_aware" group to swap their
## materials via set_retro_level(level).

enum Level { MODERN, PS2, PS1 }
const LEVEL_NAMES: PackedStringArray = ["Modern", "PS2", "PS1"]

## Current look, readable from anywhere (HUD). Kept when switching tracks.
static var level: int = Level.PS1
static var _initialised := false

@export var start_level: Level = Level.PS1

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
	add_to_group("retro_look")
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/vfx/shaders/psx_post.gdshader")
	_rect = ColorRect.new()
	_rect.name = "RetroScreen"
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	if not _initialised:
		GameSettings.ensure_loaded()
		level = GameSettings.look if GameSettings.look != Level.MODERN else Level.PS1
		_initialised = true
	# Wait one frame so the track and vehicles have finished setting up.
	_apply.call_deferred()


## Fisheye and the speed blur follow the settings and the player's speed.
## (Split screen: off, the lens would bend across both halves.)
var forced_car: Vehicle  ## (screenshots: use this car as the player's)
var _blur := 0.0

func _process(delta: float) -> void:
	var players := 0
	var car: Vehicle = null
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v and v.input is PlayerInput:
			players += 1
			car = v
	if is_instance_valid(forced_car):
		players = 1
		car = forced_car
	var solo := players == 1
	_material.set_shader_parameter("fisheye", GameSettings.FISHEYE_AMOUNTS[clampi(GameSettings.fisheye, 0, 2)] if solo else 0.0)
	var target := 0.0
	if solo and GameSettings.speed_fx and car:
		target = smoothstep(28.0, 70.0, car.linear_velocity.length())
		var perks := car.get_node_or_null("Perks") as CarPerks
		if perks and perks.boosting:
			target = minf(target + 0.35, 1.0)
	_blur = lerpf(_blur, target, 1.0 - exp(-3.0 * delta))
	_material.set_shader_parameter("speed_blur", _blur)
	var s := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("aspect", s.x / maxf(s.y, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_look"):
		set_level(Level.PS1 if level == Level.PS2 else Level.PS2)
		GameSettings.look = level
		GameSettings.save()


func set_level(new_level: int) -> void:
	level = new_level
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
