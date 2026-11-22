class_name Circuit
extends Node3D
## Procedural race circuit (design concept §8): a closed spline through
## `points` is extruded into a road with curbs, grass run-off, a start/finish
## gantry, brake boards, trees and a grandstand. It also answers "how far
## round the lap is this position?" for lap timing, and gives an outline for
## the minimap.
##
## Surfaces: road grip 1.0, curbs 0.85, grass 0.55 with extra rolling drag
## (read by Wheel from each collider's "surface_grip" / "surface_drag" meta).

const LAYER_WORLD := 1
const ROAD_Y := 0.03

@export var track_name: String = "Greenhill Ring"
## Control points (x, z) in metres. The road runs through them in order and
## loops back to the first. The first point is the start/finish line.
@export var points: PackedVector2Array = PackedVector2Array([
	Vector2(0, 250), Vector2(0, -330), Vector2(20, -405), Vector2(75, -425),
	Vector2(112, -380), Vector2(108, -300), Vector2(115, -225), Vector2(170, -165),
	Vector2(240, -170), Vector2(295, -215), Vector2(360, -195), Vector2(405, -110),
	Vector2(400, 0), Vector2(345, 80), Vector2(305, 140), Vector2(330, 195),
	Vector2(300, 255), Vector2(225, 290), Vector2(150, 370), Vector2(65, 400),
	Vector2(10, 360), Vector2(0, 315),
])
@export var road_width: float = 12.0
@export var curb_width: float = 1.4
## Corners tighter than this radius (m) get curbs.
@export var curb_radius: float = 220.0
@export var sample_step: float = 2.0
@export var tree_count: int = 240
@export var tree_clearance: float = 32.0
@export var random_seed: int = 11
## Build the layout chosen in the menu (GameSettings.track) instead of `points`.
@export var use_selected_track: bool = false

var curve := Curve3D.new()
var length: float = 0.0
## Track centre line as (x, z) points, for the minimap.
var outline := PackedVector2Array()

var _samples: Array[Dictionary] = []
var _materials: Dictionary = {}
var _bounds := Rect2()


func _ready() -> void:
	add_to_group("circuit")
	if use_selected_track:
		GameSettings.ensure_loaded()
		var track := TrackList.get_track(GameSettings.track)
		points = PackedVector2Array(track.points)
		track_name = String(track.name).capitalize()
		random_seed = int(track.seed)
	_build_curve()
	_sample_curve()
	_build_environment()
	_build_ground()
	_build_road()
	_build_curbs()
	_build_start_line()
	_build_brake_boards()
	var dressing := TrackDressing.new()
	dressing.name = "Dressing"
	add_child(dressing)


## Starting position: on the grid just behind the start/finish line.
func get_spawn_transform() -> Transform3D:
	return get_grid_transform(-1)


## Grid slot 0, 1, 2... in a staggered two-wide grid behind the line.
## Slot -1 = alone in the middle of the road.
func get_grid_transform(slot: int) -> Transform3D:
	var row := maxi(slot, 0)
	var off := length - 16.0 - row * 7.0
	var pos := curve.sample_baked(off, true)
	var ahead := curve.sample_baked(fposmod(off + 2.0, length), true)
	var dir := (ahead - pos).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var lateral := 0.0 if slot < 0 else (-3.0 if slot % 2 == 0 else 3.0)
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), pos + right * lateral + Vector3(0.0, 0.1, 0.0))
	return global_transform * xf


## Distance (m) along the lap from the start line to the point nearest `world_pos`.
func progress_at(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))


## Signed curvature (1/radius, + = left turn) of the centre line at `off`.
## Looked up from the table built at start-up (fast enough for many AI cars).
func curvature_at(off: float) -> float:
	var n := _samples.size()
	var f := fposmod(off, length) / length * n
	var i := int(f)
	var a: float = _samples[i % n].curv
	var b: float = _samples[(i + 1) % n].curv
	return lerpf(a, b, f - i)


## Unit vector pointing to the right of the driving direction at `off`.
func right_at(off: float) -> Vector3:
	var tangent := (_at(off + 1.0) - _at(off - 1.0)).normalized()
	return global_transform.basis * tangent.cross(Vector3.UP).normalized()


## Unit vector along the driving direction at `off`.
func direction_at(off: float) -> Vector3:
	return global_transform.basis * (_at(off + 1.0) - _at(off - 1.0)).normalized()


## Fastest safe speed (m/s) at every `sample_step` round the lap for a car
## that can corner at `lateral_accel` and brake at `brake_accel` (m/s²).
## Corner limits first, then a backward pass so the car brakes in time.
func build_speed_profile(lateral_accel: float, brake_accel: float, top_speed: float) -> PackedFloat32Array:
	var n := _samples.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		# Use the tightest curvature nearby, so the car is slow through the whole corner.
		var k := 0.0
		for j in range(-3, 4):
			k = maxf(k, absf(_samples[(i + j + n) % n].curv))
		v[i] = minf(sqrt(lateral_accel / maxf(k, 0.0001)), top_speed)
	var step := length / n
	# Two laps backwards so braking zones wrap past the start line.
	for pass_i in 2:
		for idx in range(n - 1, -1, -1):
			var next := v[(idx + 1) % n]
			v[idx] = minf(v[idx], sqrt(next * next + 2.0 * brake_accel * step))
	return v


func profile_speed(profile: PackedFloat32Array, off: float) -> float:
	var n := profile.size()
	var f := fposmod(off, length) / length * n
	var i := int(f)
	return lerpf(profile[i % n], profile[(i + 1) % n], f - i)


## World position on the centre line at distance `off` along the lap.
func point_at(off: float) -> Vector3:
	return to_global(_at(off))


## Distance (m) from the track centre line.
func distance_from_centre(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	var p := curve.get_closest_point(local)
	return Vector2(local.x - p.x, local.z - p.z).length()


# --- Shape -------------------------------------------------------------------

func _build_curve() -> void:
	curve = TrackList.make_curve(points)
	length = curve.get_baked_length()


func _sample_curve() -> void:
	var count := int(ceil(length / sample_step))
	for k in count:
		var off := length * k / count
		var pos := _at(off)
		var tangent := (_at(off + 1.0) - _at(off - 1.0)).normalized()
		var t1 := (pos - _at(off - 8.0)).normalized()
		var t2 := (_at(off + 8.0) - pos).normalized()
		# + = turning left, in radians per metre.
		var curvature := t1.signed_angle_to(t2, Vector3.UP) / 16.0
		_samples.append({
			"pos": pos,
			"right": tangent.cross(Vector3.UP).normalized(),
			"tangent": tangent,
			"off": off,
			"curv": curvature,
		})
		outline.append(Vector2(pos.x, pos.z))
		_bounds = Rect2(pos.x, pos.z, 0, 0) if k == 0 else _bounds.expand(Vector2(pos.x, pos.z))


func _at(off: float) -> Vector3:
	return curve.sample_baked(fposmod(off, length), true)


# --- Environment & ground ----------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.8)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_horizon_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.88)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	world_env.add_to_group("world_environment")
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _build_ground() -> void:
	var margin := 260.0
	var rect := _bounds.grow(margin)
	var centre := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var size := rect.size

	var body := StaticBody3D.new()
	body.name = "Grass"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface_grip", 0.55)
	body.set_meta(&"surface_drag", 0.05)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 2.0, size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = centre + Vector3(0.0, -1.0, 0.0)
	body.add_child(cs)
	var plane := PlaneMesh.new()
	plane.size = size
	plane.material = _noise_material(Color(0.28, 0.48, 0.2), Color(0.22, 0.4, 0.16), 0.08)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = centre
	body.add_child(mi)
	add_child(body)

	# Low walls at the edge of the map.
	var wall_color := Color(0.6, 0.58, 0.55)
	var h := 1.5
	_static_box(Vector3(size.x, h, 1.0), centre + Vector3(0, h * 0.5, -size.y * 0.5), wall_color)
	_static_box(Vector3(size.x, h, 1.0), centre + Vector3(0, h * 0.5, size.y * 0.5), wall_color)
	_static_box(Vector3(1.0, h, size.y), centre + Vector3(-size.x * 0.5, h * 0.5, 0), wall_color)
	_static_box(Vector3(1.0, h, size.y), centre + Vector3(size.x * 0.5, h * 0.5, 0), wall_color)


# --- Road & curbs ------------------------------------------------------------

func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := road_width * 0.5
	var n := _samples.size()
	for k in n:
		var a: Dictionary = _samples[k]
		var b: Dictionary = _samples[(k + 1) % n]
		var a_off: float = a.off
		var b_off: float = a_off + sample_step if k == n - 1 else b.off
		var va := a_off / road_width
		var vb := b_off / road_width
		var al: Vector3 = a.pos - a.right * half + Vector3.UP * ROAD_Y
		var ar: Vector3 = a.pos + a.right * half + Vector3.UP * ROAD_Y
		var bl: Vector3 = b.pos - b.right * half + Vector3.UP * ROAD_Y
		var br: Vector3 = b.pos + b.right * half + Vector3.UP * ROAD_Y
		_quad(st, al, ar, br, bl, Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_texture()
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(0, mat)
	_add_static_mesh("Road", mesh, 1.0, 0.0)


func _build_curbs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := road_width * 0.5
	var n := _samples.size()
	var min_curv := 1.0 / curb_radius
	var red := Color(0.85, 0.12, 0.1)
	var white := Color(0.95, 0.95, 0.95)
	for k in n:
		var a: Dictionary = _samples[k]
		var b: Dictionary = _samples[(k + 1) % n]
		if absf(a.curv) < min_curv and absf(b.curv) < min_curv:
			continue
		var color := red if int(a.off / 4.0) % 2 == 0 else white
		st.set_color(color)
		for side: float in [-1.0, 1.0]:
			var a_in: Vector3 = a.pos + a.right * side * half + Vector3.UP * ROAD_Y
			var b_in: Vector3 = b.pos + b.right * side * half + Vector3.UP * ROAD_Y
			var a_out: Vector3 = a.pos + a.right * side * (half + curb_width) + Vector3.UP * (ROAD_Y + 0.04)
			var b_out: Vector3 = b.pos + b.right * side * (half + curb_width) + Vector3.UP * (ROAD_Y + 0.04)
			# Lift the inner edge a hair so the curb draws over the road edge.
			a_in.y += 0.005
			b_in.y += 0.005
			_quad(st, a_in, a_out, b_out, b_in, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_add_static_mesh("Curbs", mesh, 0.85, 0.01)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_normal(Vector3.UP)
	for pair: Array in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


func _add_static_mesh(node_name: String, mesh: ArrayMesh, grip: float, drag: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface_grip", grip)
	body.set_meta(&"surface_drag", drag)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# --- Trackside ---------------------------------------------------------------

func _build_start_line() -> void:
	var s: Dictionary = _samples[0]
	var rot := Basis.looking_at(s.tangent, Vector3.UP)
	var origin: Vector3 = s.pos
	# Chequered strip across the road.
	var cols := 12
	var cell := road_width / cols
	for row in 2:
		for col in cols:
			var black := (row + col) % 2 == 0
			var local := Vector3(-road_width * 0.5 + cell * (col + 0.5), ROAD_Y + 0.01, (row - 0.5) * 0.9)
			_paint(Vector3(cell, 0.01, 0.9), origin + rot * local, rot,
					Color(0.05, 0.05, 0.05) if black else Color(0.95, 0.95, 0.95))
	# Gantry.
	var post := Color(0.85, 0.85, 0.88)
	var span := road_width * 0.5 + 2.5
	for side: float in [-1.0, 1.0]:
		_static_box_basis(Vector3(0.5, 7.0, 0.5), origin + rot * Vector3(side * span, 3.5, 0.0), rot, post)
	_paint(Vector3(span * 2.0 + 0.5, 1.4, 0.4), origin + rot * Vector3(0.0, 6.6, 0.0), rot, Color(0.1, 0.12, 0.2))
	var title := Label3D.new()
	title.text = "RRS  ·  %s" % track_name.to_upper()
	title.font_size = 96
	title.pixel_size = 0.01
	title.outline_size = 12
	title.modulate = Color(1.0, 0.82, 0.25)
	title.transform = Transform3D(rot, origin + rot * Vector3(0.0, 6.6, 0.25))
	add_child(title)


## 150 / 100 / 50 m boards before every tight corner, on the outside.
func _build_brake_boards() -> void:
	var n := _samples.size()
	var tight := 1.0 / 70.0
	var calm := 1.0 / 300.0
	var k := 0
	var guard := 0
	while k < n and guard < n * 2:
		guard += 1
		var s: Dictionary = _samples[k]
		if absf(s.curv) < tight:
			k += 1
			continue
		# Walk back to where the corner starts.
		var entry := k
		while absf(_samples[(entry - 1 + n) % n].curv) > calm and entry > k - 60:
			entry -= 1
		var entry_off: float = _samples[(entry + n) % n].off
		var outside := -signf(s.curv)  # left turn -> boards on the right
		for dist: int in [150, 100, 50]:
			var off := fposmod(entry_off - dist, length)
			var pos := _at(off)
			var tangent := (_at(off + 1.0) - _at(off - 1.0)).normalized()
			var right := tangent.cross(Vector3.UP).normalized()
			var spot := pos + right * outside * (road_width * 0.5 + 3.5)
			_brake_board(spot, tangent, str(dist))
		# Skip past this corner.
		while k < n and absf(_samples[k].curv) > calm:
			k += 1
		k += 1


func _brake_board(pos: Vector3, tangent: Vector3, text: String) -> void:
	# Face the oncoming cars.
	var rot := Basis.looking_at(tangent, Vector3.UP)
	_paint(Vector3(0.12, 2.2, 0.12), pos + Vector3(0, 1.1, 0), rot, Color(0.9, 0.9, 0.9))
	_paint(Vector3(1.6, 1.1, 0.08), pos + Vector3(0, 2.4, 0), rot, Color(0.95, 0.95, 0.95))
	var label := Label3D.new()
	label.text = text
	label.font_size = 80
	label.pixel_size = 0.01
	label.modulate = Color.BLACK
	label.outline_size = 0
	label.transform = Transform3D(rot, pos + Vector3(0, 2.4, 0) - tangent * 0.06)
	add_child(label)


# --- Helpers -----------------------------------------------------------------

func _color_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	_materials[key] = mat
	return mat


func _paint(size: Vector3, pos: Vector3, rot: Basis, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = _color_mat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.transform = Transform3D(rot, pos)
	add_child(mi)


func _static_box(size: Vector3, pos: Vector3, color: Color) -> void:
	_static_box_basis(size, pos, Basis.IDENTITY, color)


func _static_box_basis(size: Vector3, pos: Vector3, rot: Basis, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.transform = Transform3D(rot, pos)
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


## Small noisy texture (PS2-era style), tiled in world space.
func _noise_material(a: Color, b: Color, world_scale: float) -> StandardMaterial3D:
	var px := 64
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in px:
		for x in px:
			img.set_pixel(x, y, a.lerp(b, rng.randf()))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * world_scale
	mat.roughness = 1.0
	return mat


## Asphalt with white edge lines. u runs across the road, v along it.
func _road_texture() -> ImageTexture:
	var w := 64
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var base := Color(0.2, 0.2, 0.22)
	for y in h:
		for x in w:
			img.set_pixel(x, y, base.lerp(Color(0.27, 0.27, 0.29), rng.randf() * 0.8))
	var line := Color(0.92, 0.92, 0.9)
	img.fill_rect(Rect2i(2, 0, 2, h), line)
	img.fill_rect(Rect2i(w - 4, 0, 2, h), line)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
