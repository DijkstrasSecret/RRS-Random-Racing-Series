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
## Radius (m) of the road-surface blend (and its lookup grid cell).
const SURFACE_CELL := 9.0

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
## Height (m) of each control point; empty = flat.
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var road_width: float = 12.0
@export var curb_width: float = 1.4
## Corners tighter than this radius (m) get curbs.
@export var curb_radius: float = 220.0
@export var sample_step: float = 2.0
@export var tree_count: int = 240
@export var tree_clearance: float = 32.0
@export var random_seed: int = 11
## Scenery around the track: "hills" (farms, villages) or "mountains" (peaks, pines, chalets).
@export var theme: String = "hills"
## Build the layout chosen in the menu (GameSettings.track) instead of `points`.
@export var use_selected_track: bool = false

var curve := Curve3D.new()
var length: float = 0.0
## Track centre line as (x, z) points, for the minimap.
var outline := PackedVector2Array()

## Sky, sun, fog and clouds (time of day and weather from the race settings).
var atmosphere: TrackAtmosphere
## Hills / mountains around the track.
var terrain: TrackTerrain
var _samples: Array[Dictionary] = []
var _materials: Dictionary = {}
var _bounds := Rect2()
var _surface_grid: Dictionary = {}  ## Vector2i cell -> sample indices
var _track_id := ""  ## set when built from the track list (use_selected_track)


func _ready() -> void:
	add_to_group("circuit")
	if use_selected_track:
		GameSettings.ensure_loaded()
		var track := TrackList.get_track(GameSettings.track)
		points = PackedVector2Array(track.points)
		_track_id = GameSettings.track
		track_name = String(track.name).capitalize()
		random_seed = int(track.seed)
		theme = String(track.get("theme", "hills"))
	_build_curve()
	_sample_curve()
	_build_surface_grid()
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
		# Ease off over sharp crests so the car doesn't go light and slide.
		var crest: float = _samples[i].crest
		if crest > 0.0:
			v[i] = minf(v[i], sqrt(9.81 * 0.9 / crest))
	var step := length / n
	# Two laps backwards so braking zones wrap past the start line.
	for pass_i in 2:
		for idx in range(n - 1, -1, -1):
			var next := v[(idx + 1) % n]
			# Downhill the brakes have gravity against them (uphill they get help).
			var grade: float = (_samples[(idx + 1) % n].pos.y - _samples[idx].pos.y) / step
			var decel := maxf(brake_accel + 9.81 * grade, brake_accel * 0.4)
			v[idx] = minf(v[idx], sqrt(next * next + 2.0 * decel * step))
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
	curve = TrackList.track_curve(_track_id) if _track_id != "" else TrackList.make_curve(points, heights)
	length = curve.get_baked_length()


func _sample_curve() -> void:
	var count := int(ceil(length / sample_step))
	for k in count:
		var off := length * k / count
		var pos := _at(off)
		var tangent := (_at(off + 1.0) - _at(off - 1.0)).normalized()
		# Turning is measured on the flat plan (crests and dips are not corners).
		var flat := Vector3(1.0, 0.0, 1.0)
		var t1 := ((pos - _at(off - 8.0)) * flat).normalized()
		var t2 := ((_at(off + 8.0) - pos) * flat).normalized()
		# + = turning left, in radians per metre.
		var curvature := t1.signed_angle_to(t2, Vector3.UP) / 16.0
		# Over a crest the slope gets less steep: + = crest (1/radius).
		var g0 := (pos.y - _at(off - 8.0).y) / 8.0
		var g1 := (_at(off + 8.0).y - pos.y) / 8.0
		var crest := (g0 - g1) / 8.0
		_samples.append({
			"pos": pos,
			"right": tangent.cross(Vector3.UP).normalized(),
			"tangent": tangent,
			"off": off,
			"curv": curvature,
			"crest": crest,
		})
		outline.append(Vector2(pos.x, pos.z))
		_bounds = Rect2(pos.x, pos.z, 0, 0) if k == 0 else _bounds.expand(Vector2(pos.x, pos.z))


func _at(off: float) -> Vector3:
	return curve.sample_baked(fposmod(off, length), true)


# --- Environment & ground ----------------------------------------------------

func _build_environment() -> void:
	GameSettings.ensure_loaded()
	atmosphere = TrackAtmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.time_of_day = GameSettings.time_of_day
	atmosphere.weather = GameSettings.weather
	add_child(atmosphere)
	atmosphere.build((points[1] - points[0]).normalized(), _bounds.get_center())


func _build_ground() -> void:
	var margin := 260.0
	var rect := _bounds.grow(margin)
	var centre := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var size := rect.size

	# Safety floor well below the land (the terrain is the real ground: it
	# follows the track's height and rises into hills / mountains further out).
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
	cs.position = centre + Vector3(0.0, -4.0, 0.0)
	body.add_child(cs)
	add_child(body)
	terrain = TrackTerrain.new()
	terrain.name = "Terrain"
	terrain.theme = theme
	add_child(terrain)
	terrain.build(self)

	# Invisible walls at the edge of the drivable area.
	var h := 40.0
	for wall: Array in [[Vector3(size.x, h, 1.0), Vector3(0, h * 0.5, -size.y * 0.5)],
			[Vector3(size.x, h, 1.0), Vector3(0, h * 0.5, size.y * 0.5)],
			[Vector3(1.0, h, size.y), Vector3(-size.x * 0.5, h * 0.5, 0)],
			[Vector3(1.0, h, size.y), Vector3(size.x * 0.5, h * 0.5, 0)]]:
		var wb := StaticBody3D.new()
		wb.collision_layer = LAYER_WORLD
		wb.collision_mask = 0
		var ws := BoxShape3D.new()
		ws.size = wall[0]
		var wc := CollisionShape3D.new()
		wc.shape = ws
		wc.position = centre + wall[1]
		wb.add_child(wc)
		add_child(wb)


## Ground height at a world position (about the road's height near the track).
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else 0.0


# --- Road & curbs ------------------------------------------------------------

## Height of the road surface at a map position: a blend of the centre line
## within 9 m. Along a single stretch that is just its own height; where two
## stretches overlap both get the same blend.
func surface_y(x: float, z: float, fallback: float = 0.0) -> float:
	var cx := int(floor(x / SURFACE_CELL))
	var cz := int(floor(z / SURFACE_CELL))
	var sum := 0.0
	var wsum := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for k: int in _surface_grid.get(Vector2i(cx + dx, cz + dz), []):
				var p: Vector3 = _samples[k].pos
				var d := Vector2(p.x - x, p.z - z).length()
				if d < SURFACE_CELL:
					var w := 1.0 - d / SURFACE_CELL
					w *= w
					sum += p.y * w
					wsum += w
	return sum / wsum if wsum > 0.0 else fallback


## `p` (circuit space) moved onto the road surface.
func _on_surface(p: Vector3) -> Vector3:
	return Vector3(p.x, surface_y(p.x, p.z, p.y) + ROAD_Y, p.z)


func _build_surface_grid() -> void:
	_surface_grid.clear()
	for k in _samples.size():
		var p: Vector3 = _samples[k].pos
		var key := Vector2i(int(floor(p.x / SURFACE_CELL)), int(floor(p.z / SURFACE_CELL)))
		if not _surface_grid.has(key):
			_surface_grid[key] = []
		_surface_grid[key].append(k)


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
		# Three strips across, each corner on the shared road surface (so
		# stretches that overlap in a tight chicane meet without a lip).
		for strip in 3:
			var u0 := strip / 3.0
			var u1 := (strip + 1) / 3.0
			var al := _on_surface(a.pos + a.right * half * (u0 * 2.0 - 1.0))
			var ar := _on_surface(a.pos + a.right * half * (u1 * 2.0 - 1.0))
			var bl := _on_surface(b.pos + b.right * half * (u0 * 2.0 - 1.0))
			var br := _on_surface(b.pos + b.right * half * (u1 * 2.0 - 1.0))
			_quad(st, al, ar, br, bl, Vector2(u0, va), Vector2(u1, va), Vector2(u1, vb), Vector2(u0, vb))
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
			var a_in := _on_surface(a.pos + a.right * side * half)
			var b_in := _on_surface(b.pos + b.right * side * half)
			var a_out := _on_surface(a.pos + a.right * side * (half + curb_width)) + Vector3.UP * 0.04
			var b_out := _on_surface(b.pos + b.right * side * (half + curb_width)) + Vector3.UP * 0.04
			# Lift the inner edge a hair so the curb draws over the road edge.
			a_in.y += 0.005
			b_in.y += 0.005
			# _quad wants the left edge first.
			if side > 0.0:
				_quad(st, a_in, a_out, b_out, b_in, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			else:
				_quad(st, a_out, a_in, b_in, b_out, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
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
	# a-b runs left to right, a-d forwards: their cross product points up
	# (tilted on slopes, so hills catch the light properly).
	var n := (b - a).cross(d - a)
	st.set_normal(n.normalized() if n.y > 0.0001 else Vector3.UP)
	# Clockwise seen from above = facing up (Godot's front faces), so the
	# sun, headlights and lamps light the surface.
	for pair: Array in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
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
