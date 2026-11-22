class_name TrackDressing
extends Node3D
## Everything around a Circuit's road (design concept §8): grass run-off,
## gravel traps, barriers with catch fences and spectators, grandstands, pit
## building, control tower, billboards, marshal posts, a farm and forests.
## Uses the Blender kit in assets/track_kit/track_kit.glb.
##
## Run-off: the barrier line sits 5-7 m from the road on the inside of
## corners and up to 24 m on the outside of fast corners, so there is room
## to run wide before a barrier stops the car.

const KIT := "res://assets/track_kit/track_kit.glb"
const LAYER_WORLD := 1
## Kit piece lengths along the barrier line (metres).
const LENGTH := {"armco": 4.0, "concrete_red": 3.0, "concrete_white": 3.0, "tirewall": 2.0, "fence": 4.0}
const SPONSORS: PackedStringArray = ["RRS", "TURBO FIZZ", "GRIPMAX TYRES", "VOLT OIL", "HYPERCOLA",
	"NITRO NOODLES", "MOTOMART", "APEX WATCHES"]
const SPONSOR_COLORS: PackedColorArray = [Color(0.95, 0.75, 0.1), Color(0.85, 0.15, 0.12),
	Color(0.12, 0.3, 0.75), Color(0.1, 0.55, 0.3), Color(0.95, 0.95, 0.95), Color(0.95, 0.45, 0.05)]
const SHIRTS: PackedColorArray = [Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.8), Color(0.95, 0.8, 0.15),
	Color(0.95, 0.95, 0.95), Color(0.2, 0.6, 0.3), Color(0.95, 0.45, 0.1), Color(0.2, 0.2, 0.22),
	Color(0.6, 0.25, 0.7)]

var circuit: Circuit
var _meshes: Dictionary = {}
var _batches: Dictionary = {}  # mesh name -> Array[Transform3D]
var _colors: Dictionary = {}  # mesh name -> Array[Color]
var _barrier_body: StaticBody3D
var _solid_body: StaticBody3D
var _rng := RandomNumberGenerator.new()
## Barrier distance from the centre line per sample, for left (0) / right (1).
var _barrier_dist: Array[PackedFloat32Array] = []
var _outside_corner: Array[PackedFloat32Array] = []
var _spectator_zones: Array[Vector3] = []  # (from offset, to offset, side)
var _keep_clear: Array[Rect2] = []  # building footprints (x, z) for the trees


func _ready() -> void:
	circuit = get_parent() as Circuit
	_rng.seed = circuit.random_seed
	_load_kit()
	_barrier_body = _static_body("Barriers", 0.25, 0.2)
	_solid_body = _static_body("Buildings", 0.6, 0.0)
	_plan_runoff()
	_plan_spectator_zones()
	_build_gravel()
	_build_barriers()
	_build_spectators()
	_build_buildings()
	_build_billboards()
	_build_marshal_posts()
	_build_farm()
	_build_forest()
	_flush_batches()


# --- kit --------------------------------------------------------------------------

func _load_kit() -> void:
	var kit := (load(KIT) as PackedScene).instantiate()
	for mi in kit.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		_meshes[String(mi.name)] = mesh
	kit.free()
	# Chain-link fence: see-through where the texture is clear.
	_fix_materials("fence", func(mat: BaseMaterial3D) -> void:
		if mat.albedo_texture:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	# Spectators: shirts take each person's own colour.
	_fix_materials("spectator", func(mat: BaseMaterial3D) -> void:
		if mat.resource_name.contains("shirt"):
			mat.vertex_color_use_as_albedo = true)


func _fix_materials(mesh_name: String, fix: Callable) -> void:
	var mesh: Mesh = _meshes.get(mesh_name)
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i) as BaseMaterial3D
		if mat:
			mat = mat.duplicate() as BaseMaterial3D
			fix.call(mat)
			mesh.surface_set_material(i, mat)


func _add(mesh_name: String, xf: Transform3D, color: Color = Color.WHITE) -> void:
	if not _batches.has(mesh_name):
		_batches[mesh_name] = []
		_colors[mesh_name] = []
	_batches[mesh_name].append(xf)
	_colors[mesh_name].append(color)


func _flush_batches() -> void:
	for mesh_name: String in _batches:
		var list: Array = _batches[mesh_name]
		if list.is_empty() or not _meshes.has(mesh_name):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = mesh_name == "spectator"
		mm.mesh = _meshes[mesh_name]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			if mm.use_colors:
				mm.set_instance_color(i, _colors[mesh_name][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit_" + mesh_name
		mmi.multimesh = mm
		add_child(mmi)


func _static_body(node_name: String, friction: float, bounce: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = bounce
	body.physics_material_override = pm
	add_child(body)
	return body


func _box_collider(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


# --- layout ------------------------------------------------------------------------

func _samples() -> Array[Dictionary]:
	return circuit._samples


## How far the barriers sit from the centre line on each side, smoothed so
## the barrier line flows instead of zig-zagging.
func _plan_runoff() -> void:
	var s := _samples()
	var n := s.size()
	var half := circuit.road_width * 0.5
	for side in 2:
		var raw := PackedFloat32Array()
		var outside := PackedFloat32Array()
		raw.resize(n)
		outside.resize(n)
		for i in n:
			var curv: float = s[i].curv
			var k := clampf(absf(curv) * 70.0, 0.0, 1.0)
			var is_outside := (curv > 0.0 and side == 1) or (curv < 0.0 and side == 0)
			outside[i] = k if is_outside else 0.0
			raw[i] = lerpf(8.0, 24.0, k) if is_outside else lerpf(7.0, 5.0, k)
		# Widest value nearby, then a moving average.
		var widened := PackedFloat32Array()
		widened.resize(n)
		var out_w := PackedFloat32Array()
		out_w.resize(n)
		for i in n:
			var m := 0.0
			var o := 0.0
			for j in range(-12, 13):
				m = maxf(m, raw[(i + j + n) % n])
				o = maxf(o, outside[(i + j + n) % n])
			widened[i] = m
			out_w[i] = o
		var smooth := PackedFloat32Array()
		smooth.resize(n)
		for i in n:
			var total := 0.0
			for j in range(-10, 11):
				total += widened[(i + j + n) % n]
			smooth[i] = half + total / 21.0
		_barrier_dist.append(smooth)
		_outside_corner.append(out_w)


## Spectators stand on the outside of the three tightest corners and along
## the grandstand side of the start straight.
func _plan_spectator_zones() -> void:
	var s := _samples()
	var n := s.size()
	var corners: Array[int] = []
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return absf(s[a].curv) > absf(s[b].curv))
	for i in order:
		var near := false
		for c in corners:
			if absi(c - i) < 60 or absi(c - i) > n - 60:
				near = true
		if not near:
			corners.append(i)
		if corners.size() >= 3:
			break
	for c in corners:
		var off: float = s[c].off
		var side := 1 if s[c].curv > 0.0 else 0  # outside of the turn
		_spectator_zones.append(Vector3(off - 50.0, off + 50.0, side))
	# Start straight, left side (grandstands).
	_spectator_zones.append(Vector3(circuit.length - 230.0, circuit.length - 25.0, 0))


func _in_spectator_zone(off: float, side: int) -> bool:
	for z in _spectator_zones:
		if int(z.z) != side:
			continue
		var a := fposmod(z.x, circuit.length)
		var b := fposmod(z.y, circuit.length)
		if (a <= b and off >= a and off <= b) or (a > b and (off >= a or off <= b)):
			return true
	return false


## Point beside the road at `dist` from the centre line (side 0 = left, 1 = right).
func _side_point(i: int, side: int, dist: float) -> Vector3:
	var s: Dictionary = _samples()[i]
	var sign_ := 1.0 if side == 1 else -1.0
	return circuit.to_global(s.pos + s.right * sign_ * dist)


## A spot is usable if no other part of the track is closer than intended.
func _clear_of_track(p: Vector3, dist: float) -> bool:
	return circuit.distance_from_centre(p) >= dist - 1.0


# --- run-off surfaces --------------------------------------------------------------

func _build_gravel() -> void:
	var s := _samples()
	var n := s.size()
	var half := circuit.road_width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for side in 2:
		var sign_ := 1.0 if side == 1 else -1.0
		for i in n:
			var j := (i + 1) % n
			var di := _barrier_dist[side][i]
			var dj := _barrier_dist[side][j]
			if _outside_corner[side][i] < 0.45 or di - half < 13.0:
				continue
			var inner := half + circuit.curb_width + 2.5
			var a_in: Vector3 = s[i].pos + s[i].right * sign_ * inner
			var b_in: Vector3 = s[j].pos + s[j].right * sign_ * inner
			var a_out: Vector3 = s[i].pos + s[i].right * sign_ * (di - 1.5)
			var b_out: Vector3 = s[j].pos + s[j].right * sign_ * (dj - 1.5)
			if not _clear_of_track(circuit.to_global(a_out), di - 1.5):
				continue
			var y := Vector3.UP * 0.02
			st.set_normal(Vector3.UP)
			for v: Vector3 in [a_in, a_out, b_out, a_in, b_out, b_in]:
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v + y)
			any = true
	if not any:
		return
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _speckle_texture(Color(0.72, 0.64, 0.5), Color(0.58, 0.5, 0.4))
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var body := StaticBody3D.new()
	body.name = "Gravel"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface_grip", 0.45)
	body.set_meta(&"surface_drag", 0.25)
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


func _speckle_texture(a: Color, b: Color) -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, a.lerp(b, rng.randf()))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- barriers & fences -------------------------------------------------------------

func _barrier_type(i: int, side: int) -> String:
	var off: float = _samples()[i].off
	if _in_spectator_zone(off, side):
		return "concrete_red" if int(off / 3.0) % 2 == 0 else "concrete_white"
	if _outside_corner[side][i] > 0.55:
		return "tirewall"
	return "armco"


func _build_barriers() -> void:
	var s := _samples()
	var n := s.size()
	for side in 2:
		var i := 0
		var anchor := _side_point(0, side, _barrier_dist[side][0])
		while i < n:
			var kind := _barrier_type(i, side)
			var seg_len: float = LENGTH[kind]
			var j := i
			var end := anchor
			while j < n + 1 and end.distance_to(anchor) < seg_len and j - i < 30:
				j += 1
				end = _side_point(j % n, side, _barrier_dist[side][j % n])
			var dist := _barrier_dist[side][i]
			if _clear_of_track(anchor, dist) and _clear_of_track(end, _barrier_dist[side][j % n]):
				_place_segment(kind, anchor, end, side, seg_len)
				if kind.begins_with("concrete"):
					var back := (anchor - end).cross(Vector3.UP).normalized() * (0.6 if side == 1 else -0.6)
					_place_segment("fence", anchor + back, end + back, side, LENGTH["fence"], false)
			anchor = end
			i = j


func _place_segment(kind: String, a: Vector3, b: Vector3, side: int, seg_len: float, solid: bool = true) -> void:
	var chord := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := chord.length()
	if length < 0.3:
		return
	# The piece's front (+Z) must face the road.
	var x := chord / length * (-1.0 if side == 1 else 1.0)
	var rot := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	var mid := (a + b) * 0.5
	var xf := Transform3D(rot.scaled_local(Vector3(length / seg_len, 1.0, 1.0)), mid)
	_add(kind, xf)
	if solid:
		var depth := 1.3 if kind == "tirewall" else 0.6
		var back := -0.3 if kind == "tirewall" else 0.0
		_box_collider(_barrier_body, Vector3(length, 1.1, depth),
				Transform3D(rot, mid + rot * Vector3(0.0, 0.55, back)))


# --- people & buildings --------------------------------------------------------------

func _build_spectators() -> void:
	var s := _samples()
	var n := s.size()
	for side in 2:
		for i in n:
			if not _in_spectator_zone(s[i].off, side):
				continue
			for row in 3:
				if _rng.randf() > 0.75:
					continue
				var dist := _barrier_dist[side][i] + 2.2 + row * 1.1 + _rng.randf_range(-0.2, 0.2)
				var p := _side_point(i, side, dist)
				if not _clear_of_track(p, dist):
					continue
				var to_road := (_side_point(i, side, 0.0) - p)
				to_road.y = 0.0
				var face := to_road.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
				var x := Vector3.UP.cross(face)
				var sc := _rng.randf_range(0.92, 1.08)
				var xf := Transform3D(Basis(x, Vector3.UP, face).scaled_local(Vector3.ONE * sc), p)
				_add("spectator", xf, SHIRTS[_rng.randi() % SHIRTS.size()])


## Places a kit building beside the track facing the road.
func _place_building(kind: String, off: float, side: int, extra: float) -> void:
	var s := _samples()
	var i := int(fposmod(off, circuit.length) / circuit.length * s.size()) % s.size()
	var dist := _barrier_dist[side][i] + extra
	var p := _side_point(i, side, dist)
	if not _clear_of_track(p, dist - 4.0):
		return
	var to_road := _side_point(i, side, 0.0) - p
	to_road.y = 0.0
	var z := to_road.normalized()
	var x := Vector3.UP.cross(z)
	var xf := Transform3D(Basis(x, Vector3.UP, z), p)
	_add(kind, xf)
	_solid(kind, xf)


func _solid(kind: String, xf: Transform3D) -> void:
	var mesh: Mesh = _meshes.get(kind)
	if mesh == null:
		return
	var aabb := mesh.get_aabb()
	_box_collider(_solid_body, aabb.size, xf * Transform3D(Basis.IDENTITY, aabb.get_center()))
	var corners := [xf * aabb.position, xf * aabb.end, xf * Vector3(aabb.position.x, 0, aabb.end.z),
		xf * Vector3(aabb.end.x, 0, aabb.position.z)]
	var r := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for c: Vector3 in corners:
		r = r.expand(Vector2(c.x, c.z))
	_keep_clear.append(r.grow(6.0))


func _build_buildings() -> void:
	var length := circuit.length
	# Start straight: grandstands on the left, pits and tower on the right.
	_place_building("grandstand", length - 75.0, 0, 9.5)
	_place_building("grandstand", length - 125.0, 0, 9.5)
	_place_building("grandstand", length - 175.0, 0, 9.5)
	_place_building("pit_building", length - 120.0, 1, 12.0)
	_place_building("control_tower", length - 35.0, 1, 10.0)
	# A stand behind each spectator corner.
	for zi in mini(3, _spectator_zones.size() - 1):
		var z := _spectator_zones[zi]
		_place_building("grandstand", (z.x + z.y) * 0.5, int(z.z), 9.0)


func _build_billboards() -> void:
	var s := _samples()
	var n := s.size()
	var placed := 0
	var i := 40
	while i < n and placed < 12:
		if absf(s[i].curv) < 1.0 / 400.0:
			var side := placed % 2
			var dist := _barrier_dist[side][i] + 4.0
			var p := _side_point(i, side, dist)
			if _clear_of_track(p, dist) and not _in_spectator_zone(s[i].off, side):
				var to_road := _side_point(i, side, 0.0) - p
				to_road.y = 0.0
				var z := to_road.normalized()
				var xf := Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), p)
				_billboard(xf, placed)
				placed += 1
				i += 55
				continue
		i += 5


func _billboard(xf: Transform3D, index: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes.get("billboard")
	mi.transform = xf
	var color := SPONSOR_COLORS[index % SPONSOR_COLORS.size()]
	for surf in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(surf) as BaseMaterial3D
		if mat and mat.resource_name.contains("billboard"):
			var face := mat.duplicate() as BaseMaterial3D
			face.albedo_color = color
			mi.set_surface_override_material(surf, face)
	add_child(mi)
	var label := Label3D.new()
	label.text = SPONSORS[index % SPONSORS.size()]
	label.font_size = 110
	label.pixel_size = 0.012
	label.outline_size = 14
	label.modulate = Color.BLACK if color.get_luminance() > 0.6 else Color.WHITE
	label.outline_modulate = color.darkened(0.4)
	label.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0.0))
	add_child(label)
	_solid("billboard", xf)


func _build_marshal_posts() -> void:
	var s := _samples()
	var n := s.size()
	var last := -999
	for i in n:
		if absf(s[i].curv) > 1.0 / 90.0 and i - last > 80:
			var entry := (i - 20 + n) % n
			var side := 1 if s[i].curv > 0.0 else 0
			var dist := _barrier_dist[side][entry] + 3.0
			var p := _side_point(entry, side, dist)
			if _clear_of_track(p, dist):
				var to_road := _side_point(entry, side, 0.0) - p
				to_road.y = 0.0
				var z := to_road.normalized()
				var xf := Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), p)
				_add("marshal_post", xf)
				_solid("marshal_post", xf)
			last = i


## A little farm out in the fields.
func _build_farm() -> void:
	var area := circuit._bounds.grow(150.0)
	for attempt in 300:
		var p := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0,
				_rng.randf_range(area.position.y, area.end.y))
		if circuit.distance_from_centre(p) < 110.0:
			continue
		var yaw := _rng.randf() * TAU
		var layout := [["barn", Vector3.ZERO], ["house", Vector3(18, 0, 6)], ["house", Vector3(-6, 0, 20)]]
		for item: Array in layout:
			var offset: Vector3 = item[1]
			var xf := Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.3, 0.3)), p + offset.rotated(Vector3.UP, yaw))
			_add(item[0], xf)
			_solid(item[0], xf)
		return


func _build_forest() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = circuit.random_seed
	noise.frequency = 0.008
	var area := circuit._bounds.grow(220.0)
	var kinds := ["tree_pine", "tree_pine", "tree_pine_tall", "tree_round", "tree_round", "bush"]
	var placed := 0
	for attempt in 5000:
		if placed >= 520:
			break
		var p := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0,
				_rng.randf_range(area.position.y, area.end.y))
		# Groves: more trees where the noise is high, a few scattered elsewhere.
		var density := noise.get_noise_2d(p.x, p.z)
		if density < 0.05 and _rng.randf() > 0.12:
			continue
		var d := circuit.distance_from_centre(p)
		if d < circuit.road_width * 0.5 + 30.0:
			continue
		var blocked := false
		for r in _keep_clear:
			if r.has_point(Vector2(p.x, p.z)):
				blocked = true
				break
		if blocked:
			continue
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var sc := _rng.randf_range(0.8, 1.35)
		_add(kind, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		placed += 1
