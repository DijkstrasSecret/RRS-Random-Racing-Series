class_name CarPortraits
extends Node
## Renders a small picture of every roster car once (front three-quarter view,
## each on its own little lit stage) for the car select grid.
## `textures[id]` is ready to draw straight away and fills in on the next frame.

const SIZE := Vector2i(320, 192)
## PS1 look: rendered small (and drawn with blocky pixels) with the
## wobbly PS1 car materials.
const SIZE_PS1 := Vector2i(100, 60)

var textures: Dictionary = {}


var _ps1 := true


func _ready() -> void:
	GameSettings.ensure_loaded()
	_ps1 = GameSettings.look != RetroLook.Level.PS2
	for id in CarRoster.ids():
		textures[id] = _render(id)


func _render(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = SIZE_PS1 if _ps1 else SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED if _ps1 else Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 30, 0)
	key.light_energy = 1.35
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, -150, 0)
	rim.light_energy = 0.7
	vp.add_child(rim)

	var model := (load(CarRoster.model_path(id)) as PackedScene).instantiate() as Node3D
	if _ps1:
		CarLook.apply_retro(model, Vector2(SIZE_PS1))
	# Every car is drawn about the same length so the grid looks even.
	var length := CarRoster.config(id).inertia_box_size.z
	model.scale = Vector3.ONE * clampf(4.5 / length, 0.78, 1.25)
	vp.add_child(model)

	var cam := Camera3D.new()
	cam.fov = 30.0
	var dir := Vector3(0.95, 0.42, -1.0).normalized()  # cars face -Z
	cam.position = Vector3(0, 0.62, 0) + dir * 8.6
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.62, 0), Vector3.UP)
	cam.current = true
	return vp.get_texture()
