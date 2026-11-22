class_name CarPreview
extends SubViewportContainer
## A slowly turning car on its own little stage (own 3D world, transparent
## background), used by the garage. show_car(id) swaps the model.

var _viewport: SubViewport
var _pivot: Node3D
var _current: String = ""


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.3
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -150, 0)
	rim.light_energy = 0.6
	_viewport.add_child(rim)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.8, 7.6)
	cam.fov = 38.0
	_viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
	cam.current = true

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


func show_car(id: String) -> void:
	if id == _current:
		return
	_current = id
	for child in _pivot.get_children():
		child.queue_free()
	var model := (load(CarRoster.model_path(id)) as PackedScene).instantiate()
	_pivot.add_child(model)
	# Long cars are scaled down a little so every car fits the frame.
	var length := CarRoster.config(id).inertia_box_size.z
	var fit := clampf(4.6 / length, 0.8, 1.15)
	_pivot.scale = Vector3.ONE * fit


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotate_y(delta * 0.45)
