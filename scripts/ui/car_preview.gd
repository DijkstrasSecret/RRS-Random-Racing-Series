class_name CarPreview
extends SubViewportContainer
## A little showroom for the garage and car select: the car hovers and
## slowly turns over a glowing pad, on a grid floor in front of a dark
## backdrop, lit by a spotlight and a rim light in the `accent` colour.
## Rendered like the game: PS1 = low resolution, blocky pixels, wobbly
## vertices and dithered colours; PS2 = smoother. show_car(id) swaps the car.

## How far the camera sits from the car (smaller = car fills more of the frame).
var camera_distance: float = 7.6
## Rim light, pad ring and floor grid colour (e.g. the player's colour).
var accent: Color = Color(0.35, 0.6, 1.0)

var _viewport: SubViewport
var _pivot: Node3D
var _current: String = ""
var _model: Node3D
var _livery := true
var _ps1 := true
var _t := 0.0
var _appear := 1.0
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	GameSettings.ensure_loaded()
	_ps1 = GameSettings.look != RetroLook.Level.PS2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stretch_shrink = 3 if _ps1 else 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if _ps1 else CanvasItem.TEXTURE_FILTER_LINEAR
	var screen := ShaderMaterial.new()
	screen.shader = load("res://assets/vfx/shaders/preview_screen.gdshader")
	screen.set_shader_parameter("color_levels", 32.0 if _ps1 else 48.0)
	screen.set_shader_parameter("dither_strength", 1.0 if _ps1 else 0.45)
	material = screen

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if _ps1 else Viewport.MSAA_2X
	add_child(_viewport)
	_build_stage()


func _build_stage() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/vfx/shaders/studio_sky.gdshader")
	sky_mat.set_shader_parameter("glow_color", accent.darkened(0.78))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 32, 0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, -160, 0)
	rim.light_energy = 1.4
	rim.light_color = accent.lerp(Color.WHITE, 0.25)
	_viewport.add_child(rim)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 7.5, 0.5)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_range = 12.0
	spot.spot_angle = 30.0
	spot.light_energy = 3.0
	_viewport.add_child(spot)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://assets/vfx/shaders/studio_floor.gdshader")
	floor_mat.set_shader_parameter("line_color", accent * 0.45)
	floor_mesh.material = floor_mat
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	_viewport.add_child(floor_mi)

	# The hover pad: a dark disc with a glowing ring.
	var pad := CylinderMesh.new()
	pad.top_radius = 2.9
	pad.bottom_radius = 3.1
	pad.height = 0.16
	pad.radial_segments = 40
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.07, 0.075, 0.09)
	pad_mat.metallic = 0.6
	pad_mat.roughness = 0.35
	pad.material = pad_mat
	var pad_mi := MeshInstance3D.new()
	pad_mi.mesh = pad
	pad_mi.position.y = 0.08
	_viewport.add_child(pad_mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.82
	ring.outer_radius = 3.0
	ring.rings = 40
	ring.ring_segments = 6
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = accent
	_ring_mat.emission_enabled = true
	_ring_mat.emission = accent
	_ring_mat.emission_energy_multiplier = 1.1
	ring.material = _ring_mat
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position.y = 0.17
	_viewport.add_child(ring_mi)

	# Soft round shadow on the pad under the hovering car.
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.4
	disc.bottom_radius = 2.4
	disc.height = 0.01
	disc.radial_segments = 32
	shadow.mesh = disc
	var shade := StandardMaterial3D.new()
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade.albedo_color = Color(0, 0, 0, 0.5)
	shadow.material_override = shade
	shadow.scale = Vector3(1.0, 1.0, 0.7)
	shadow.position.y = 0.17
	_viewport.add_child(shadow)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.75, camera_distance)
	cam.fov = 36.0
	_viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.75, 0), Vector3.UP)
	cam.current = true

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


func show_car(id: String, livery: bool = true) -> void:
	if id == _current:
		if livery != _livery:
			_set_livery(livery)
		return
	_current = id
	_livery = livery
	for child in _pivot.get_children():
		child.queue_free()
	var model := (load(CarRoster.model_path(id)) as PackedScene).instantiate() as Node3D
	if _ps1:
		var res := Vector2(maxi(_viewport.size.x, 160), maxi(_viewport.size.y, 90))
		CarLook.apply_retro(model, res)
	_pivot.add_child(model)
	_model = model
	_set_livery(livery)
	# Long cars are scaled down a little so every car fits the frame.
	var length := CarRoster.config(id).inertia_box_size.z
	model.scale = Vector3.ONE * clampf(4.6 / length, 0.8, 1.15)
	_appear = 0.0


func _set_livery(on: bool) -> void:
	_livery = on
	if _model:
		var liv := _model.find_child("livery*", true, false) as Node3D
		if liv:
			liv.visible = on


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_t += delta
	_appear = minf(_appear + delta / 0.35, 1.0)
	var drop := 1.0 - pow(1.0 - _appear, 3.0)
	_pivot.rotation.y += delta * 0.45
	_pivot.position.y = 0.42 + sin(_t * 1.7) * 0.06 + (1.0 - drop) * 0.9
	_pivot.rotation.x = sin(_t * 1.1) * 0.025
	_pivot.rotation.z = sin(_t * 1.3 + 1.0) * 0.02
	_pivot.scale = Vector3.ONE * lerpf(0.9, 1.0, drop)
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 1.0 + sin(_t * 2.4) * 0.3
