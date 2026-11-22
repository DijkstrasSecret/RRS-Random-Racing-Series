extends Node3D
## Greybox test track (design concept §6.5): braking zone, skidpad, slalom
## and a table-top jump on a big open grid. Built from code so it is quick to
## tweak; it will be replaced by a Blender track kit in M2.
##
## Collision layers: 1 = world, 2 = vehicles, 3 (value 4) = loose props.

const GROUND_SIZE := 1200.0
const LAYER_WORLD := 1
const LAYER_PROPS := 4

const ASPHALT := Color(0.17, 0.17, 0.18)
const PAINT_WHITE := Color(0.92, 0.92, 0.9)
const PAINT_RED := Color(0.85, 0.15, 0.12)
const CONE_ORANGE := Color(1.0, 0.45, 0.05)
const CONCRETE := Color(0.62, 0.6, 0.57)

var _materials: Dictionary = {}


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_braking_zone()
	_build_skidpad(Vector3(130.0, 0.0, -140.0), 30.0)
	_build_slalom(Vector3(-45.0, 0.0, -30.0), 12, 16.0)
	_build_jump(Vector3(70.0, 0.0, -250.0))
	_build_boundary()
	_build_scenery()


# --- Environment -------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.48, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.85)
	sky_mat.ground_horizon_color = Color(0.68, 0.76, 0.85)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.85)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


# --- Ground ------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)

	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.material = _grid_material()
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	body.add_child(mesh)
	add_child(body)


## Grey grid, one tile = 10 m, so speed is easy to read.
func _grid_material() -> StandardMaterial3D:
	var px := 256
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.36, 0.37, 0.38))
	var line := Color(0.52, 0.53, 0.54)
	var faint := Color(0.41, 0.42, 0.43)
	img.fill_rect(Rect2i(0, 128, px, 1), faint)
	img.fill_rect(Rect2i(128, 0, 1, px), faint)
	img.fill_rect(Rect2i(0, 0, px, 3), line)
	img.fill_rect(Rect2i(0, 0, 3, px), line)
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	return mat


# --- Test areas --------------------------------------------------------------

## Long straight from the start (heading -Z) with 150/100/50 m boards
## and a red stop line.
func _build_braking_zone() -> void:
	var stop_z := -420.0
	_paint(Vector3(16.0, 0.02, 460.0), Vector3(0.0, 0.01, -210.0), ASPHALT)
	_paint(Vector3(16.0, 0.03, 0.6), Vector3(0.0, 0.015, -6.0), PAINT_WHITE)
	_paint(Vector3(16.0, 0.03, 1.2), Vector3(0.0, 0.015, stop_z), PAINT_RED)
	for dist: int in [150, 100, 50]:
		var z := stop_z + dist
		_paint(Vector3(16.0, 0.03, 0.3), Vector3(0.0, 0.015, z), PAINT_WHITE)
		_sign(Vector3(10.0, 0.0, z), str(dist))
		_sign(Vector3(-10.0, 0.0, z), str(dist))
	_label(Vector3(0.0, 5.0, stop_z - 8.0), "BRAKING ZONE\nstop on the red line")
	_label(Vector3(0.0, 4.0, -12.0), "START", 120)


func _build_skidpad(center: Vector3, radius: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = radius + 8.0
	disc.bottom_radius = radius + 8.0
	disc.height = 0.02
	disc.radial_segments = 64
	disc.material = _color_mat(ASPHALT)
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = disc
	disc_mi.position = center + Vector3(0.0, 0.01, 0.0)
	disc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc_mi)

	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.15
	ring.outer_radius = radius + 0.15
	ring.rings = 96
	ring.material = _color_mat(PAINT_WHITE)
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.position = center + Vector3(0.0, 0.02, 0.0)
	ring_mi.scale = Vector3(1.0, 0.1, 1.0)
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mi)

	var cones := 16
	for i in cones:
		var a := TAU * i / cones
		_spawn_cone(center + Vector3(cos(a), 0.0, sin(a)) * (radius - 5.0))
	_label(center + Vector3(0.0, 5.0, 0.0), "SKIDPAD\nR %d m" % roundi(radius))


func _build_slalom(start: Vector3, count: int, spacing: float) -> void:
	var length := (count - 1) * spacing
	_paint(Vector3(12.0, 0.02, length + 40.0), start + Vector3(0.0, 0.01, -length * 0.5), ASPHALT)
	for i in count:
		_spawn_cone(start + Vector3(0.0, 0.0, -i * spacing))
	_label(start + Vector3(0.0, 4.0, 12.0), "SLALOM")


## Table-top jump heading -Z: kicker, flat table, landing ramp. Slow cars
## just roll over the table; fast cars fly and land on the down ramp.
func _build_jump(start: Vector3) -> void:
	var h := 2.2
	var width := 9.0
	_paint(Vector3(10.0, 0.02, 130.0), start + Vector3(0.0, 0.01, 55.0), ASPHALT)
	_wedge(start + Vector3(0.0, 0.0, -7.0), Vector3(width, h, 14.0), true)
	_static_box(Vector3(width, h, 16.0), start + Vector3(0.0, h * 0.5, -22.0), CONCRETE)
	_wedge(start + Vector3(0.0, 0.0, -40.0), Vector3(width, h, 20.0), false)
	_label(start + Vector3(0.0, 5.0, 8.0), "JUMP")


func _build_boundary() -> void:
	var half := GROUND_SIZE * 0.5 - 20.0
	var length := half * 2.0
	_static_box(Vector3(length, 1.5, 1.0), Vector3(0.0, 0.75, -half), CONCRETE)
	_static_box(Vector3(length, 1.5, 1.0), Vector3(0.0, 0.75, half), CONCRETE)
	_static_box(Vector3(1.0, 1.5, length), Vector3(-half, 0.75, 0.0), CONCRETE)
	_static_box(Vector3(1.0, 1.5, length), Vector3(half, 0.75, 0.0), CONCRETE)


## Scattered blocks outside the test areas, as reference points for speed.
## They stay beyond 470 m and out of the run-off past the braking zone.
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := 0
	while placed < 40:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(470.0, 550.0)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if absf(pos.x) < 60.0 and pos.z < 0.0:
			continue
		placed += 1
		var size := Vector3(rng.randf_range(4.0, 14.0), rng.randf_range(3.0, 22.0), rng.randf_range(4.0, 14.0))
		var tint := Color.from_hsv(rng.randf_range(0.0, 1.0), 0.25, rng.randf_range(0.5, 0.8))
		_static_box(size, pos + Vector3(0.0, size.y * 0.5, 0.0), tint)


# --- Builders ----------------------------------------------------------------

func _color_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	_materials[key] = mat
	return mat


## Flat painted shape on the ground (no collision).
func _paint(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = _color_mat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _static_box(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var box := BoxMesh.new()
	box.size = size
	box.material = _color_mat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	body.add_child(mi)
	add_child(body)
	return body


## Ramp with its high end toward -Z (`rising`) or toward +Z.
func _wedge(center: Vector3, size: Vector3, rising: bool) -> void:
	var prism := PrismMesh.new()
	prism.left_to_right = 0.0
	prism.size = Vector3(size.z, size.y, size.x)
	prism.material = _color_mat(CONCRETE)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = prism.create_convex_shape()
	body.add_child(cs)
	body.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	body.rotation.y = -PI * 0.5 if rising else PI * 0.5
	add_child(body)


func _spawn_cone(pos: Vector3) -> void:
	var cone := RigidBody3D.new()
	cone.mass = 4.0
	cone.collision_layer = LAYER_PROPS
	cone.collision_mask = 1 | 2 | 4
	var shape := CylinderShape3D.new()
	shape.radius = 0.2
	shape.height = 0.7
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.35
	cone.add_child(cs)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.22
	mesh.height = 0.7
	mesh.material = _color_mat(CONE_ORANGE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.35
	cone.add_child(mi)
	cone.position = pos
	add_child(cone)


## Distance board on a post, readable from the start side (+Z).
func _sign(pos: Vector3, text: String) -> void:
	_paint(Vector3(0.12, 2.0, 0.12), pos + Vector3(0.0, 1.0, 0.0), PAINT_WHITE)
	_paint(Vector3(1.8, 1.1, 0.08), pos + Vector3(0.0, 2.3, 0.0), PAINT_WHITE)
	var l := _label(pos + Vector3(0.0, 2.3, 0.06), text, 80, false)
	l.modulate = Color.BLACK
	l.outline_size = 0


func _label(pos: Vector3, text: String, font_size: int = 160, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	l.outline_size = 24
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	return l
