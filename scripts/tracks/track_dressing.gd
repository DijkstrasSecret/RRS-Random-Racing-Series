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
	_build_paddock()
	_build_car_park()
	_build_camping()
	_build_hamlets()
	_build_forest()
	_flush_batches()
	if circuit.atmosphere and circuit.atmosphere.time_of_day == TrackAtmosphere.DayTime.NIGHT:
		_build_night_lamps()


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


## Spectators stand on the outside of the six tightest corners and along
## the grandstand side of the start straight.
func _plan_spectator_zones() -> void:
	var s := _samples()
	var n := s.size()
	var corners: Array[int] = []
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return absf(s[a].curv) > absf(s[b].curv))
	if not circuit.stand_corners.is_empty():
		# The circuit's famous corners: the sharpest bit within 50 m of each.
		for f in circuit.stand_corners:
			var at := int(f * n) % n
			var best := at
			for j in range(-25, 26):
				var q := (at + j + n) % n
				if absf(s[q].curv) > absf(s[best].curv):
					best = q
			corners.append(best)
	else:
		for i in order:
			var near := false
			for c in corners:
				if absi(c - i) < 60 or absi(c - i) > n - 60:
					near = true
			if not near:
				corners.append(i)
			if corners.size() >= 6:
				break
	for c in corners:
		var off: float = s[c].off
		var side := 1 if s[c].curv > 0.0 else 0  # outside of the turn
		_spectator_zones.append(Vector3(off - 50.0, off + 50.0, side))
	# Start straight, grandstand side (opposite the pits, which face the infield).
	_spectator_zones.append(Vector3(circuit.length - 230.0, circuit.length - 25.0, 1 - circuit.infield_side()))


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
	var p := circuit.to_global(s.pos + s.right * sign_ * dist)
	# On whatever ground is really there (road, verge or land): on hills the
	# land beside the road dips and rises, and barriers must sit on it.
	p.y = circuit.surface_height(p.x, p.z)
	return p


## A spot is usable if no other part of the track is closer than intended.
func _clear_of_track(p: Vector3, dist: float) -> bool:
	return circuit.distance_from_centre(p) >= dist - 1.0


# --- night lighting ----------------------------------------------------------------

## Lamp posts just behind the barriers every ~45 m, alternating sides, each
## with a warm light pool on the road.
func _build_night_lamps() -> void:
	var s := _samples()
	var n := s.size()
	var step := maxi(int(45.0 / circuit.sample_step), 1)
	var post := BoxMesh.new()
	post.size = Vector3(0.18, 7.0, 0.18)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.25, 0.26, 0.28)
	post.material = post_mat
	var head := BoxMesh.new()
	head.size = Vector3(0.5, 0.18, 1.4)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.88, 0.65)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.85, 0.6)
	head_mat.emission_energy_multiplier = 6.0
	head.material = head_mat
	var posts: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var k := 0
	for i in range(0, n, step):
		var side := k % 2
		k += 1
		var dist := minf(_barrier_dist[side][i] + 1.5, circuit.road_width * 0.5 + 9.0)
		var base := _side_point(i, side, dist)
		if not _clear_of_track(base, dist):
			continue
		var towards: Vector3 = s[i].right * (-1.0 if side == 1 else 1.0)
		var yaw := atan2(towards.x, towards.z)
		posts.append(Transform3D(Basis.IDENTITY, base + Vector3(0, 3.5, 0)))
		var lamp_pos := base + towards * 0.6 + Vector3(0, 7.0, 0)
		heads.append(Transform3D(Basis(Vector3.UP, yaw), lamp_pos))
		var light := OmniLight3D.new()
		light.position = to_local(lamp_pos + towards * 2.5 - Vector3(0, 0.5, 0))
		light.omni_range = 30.0
		light.omni_attenuation = 1.2
		light.light_energy = 3.6
		light.light_color = Color(1.0, 0.82, 0.58)
		add_child(light)
	for pair: Array in [[post, posts], [head, heads]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		var list: Array[Transform3D] = pair[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- run-off surfaces --------------------------------------------------------------

func _build_gravel() -> void:
	var asphalt := circuit.runoff == "asphalt"
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
			if not _clear_of_track(circuit.to_global(s[i].pos + s[i].right * sign_ * (di - 1.5)), di - 1.5):
				continue
			# Strips about 3 m wide, every corner laid on the ground beneath.
			var strips := maxi(1, int(ceil((maxf(di, dj) - 1.5 - inner) / 3.0)))
			for k in strips:
				var t0 := float(k) / strips
				var t1 := float(k + 1) / strips
				var a_in := _gravel_point(s[i], sign_, lerpf(inner, di - 1.5, t0))
				var a_out := _gravel_point(s[i], sign_, lerpf(inner, di - 1.5, t1))
				var b_in := _gravel_point(s[j], sign_, lerpf(inner, dj - 1.5, t0))
				var b_out := _gravel_point(s[j], sign_, lerpf(inner, dj - 1.5, t1))
				st.set_normal(Vector3.UP)
				# Painted asphalt run-off: a green strip by the kerb, then grey.
				st.set_color(Color(0.16, 0.5, 0.26) if asphalt and k == 0 else Color.WHITE)
				# Keep every triangle facing up (clockwise from above) on both sides.
				var tris := [a_in, a_out, b_out, a_in, b_out, b_in] if side == 0 else [a_in, b_out, a_out, a_in, b_in, b_out]
				for v: Vector3 in tris:
					st.set_uv(Vector2(v.x, v.z) * 0.25)
					st.add_vertex(v)
			any = true
	if not any:
		return
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	if asphalt:
		mat.albedo_texture = _speckle_texture(Color(0.4, 0.41, 0.44), Color(0.33, 0.34, 0.37))
		mat.vertex_color_use_as_albedo = true
	else:
		mat.albedo_texture = _speckle_texture(Color(0.72, 0.64, 0.5), Color(0.58, 0.5, 0.4))
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var body := StaticBody3D.new()
	body.name = "Runoff" if asphalt else "Gravel"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	# Gravel slows a car hard; painted asphalt grips nearly like the road.
	body.set_meta(&"surface_grip", 0.92 if asphalt else 0.45)
	body.set_meta(&"surface_drag", 0.01 if asphalt else 0.25)
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


## A gravel corner `dist` from the centre line, on the ground (circuit space).
func _gravel_point(smp: Dictionary, sign_: float, dist: float) -> Vector3:
	var p: Vector3 = smp.pos + smp.right * sign_ * dist
	var g := circuit.to_global(p)
	p.y = circuit.to_local(Vector3(g.x, circuit.surface_height(g.x, g.z), g.z)).y + 0.03
	return p


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
	# The piece's front (+Z) must face the road; on hills it tilts with the slope.
	var x := chord / length * (-1.0 if side == 1 else 1.0)
	var z := x.cross(Vector3.UP)
	# Tilt with the slope. On a bank steeper than about 1 in 3 (inside a hairpin
	# whose two legs are at different heights) leave the piece out: it would
	# stand on end or sink into the bank.
	if absf(b.y - a.y) > length * 0.35:
		return
	var mid := (a + b) * 0.5
	# Ground dipping or bulging between the two ends (inside a hairpin): the
	# rail would float or sink in the middle, so leave this piece out too.
	for t: float in [0.25, 0.5, 0.75]:
		var p := a.lerp(b, t)
		if absf(p.y - circuit.surface_height(p.x, p.z)) > 0.3:
			return
	var x3 := (b - a).normalized() * (-1.0 if side == 1 else 1.0)
	var rot := Basis(x3, z.cross(x3), z)
	length = a.distance_to(b)
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


## A frame beside the track, `extra` metres behind the barrier, whose +Z
## faces the road. Its basis is all zero if that spot would be on the track.
func _frame(off: float, side: int, extra: float) -> Transform3D:
	var s := _samples()
	var i := int(fposmod(off, circuit.length) / circuit.length * s.size()) % s.size()
	var dist := _barrier_dist[side][i] + extra
	var p := _side_point(i, side, dist)
	if not _clear_of_track(p, dist - 4.0):
		return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), p)
	var to_road := _side_point(i, side, 0.0) - p
	to_road.y = 0.0
	var z := to_road.normalized()
	var x := Vector3.UP.cross(z)
	return Transform3D(Basis(x, Vector3.UP, z), p)


## Places a kit building beside the track facing the road.
func _place_building(kind: String, off: float, side: int, extra: float) -> void:
	var xf := _frame(off, side, extra)
	if xf.basis.x == Vector3.ZERO:
		return
	for r in _keep_clear:
		if r.has_point(Vector2(xf.origin.x, xf.origin.z)):
			return  # already something here
	_add(kind, xf)
	_solid(kind, xf)
	if kind == "grandstand":
		_fill_grandstand(xf)


## Fans in the stand: every step of the stand gets a scattering of people.
func _fill_grandstand(xf: Transform3D) -> void:
	for row in 8:
		var h := 0.6 + row * 0.55
		var z := 4.0 - row * 1.1 - 0.3
		var x := -19.3
		while x < 19.3:
			if _rng.randf() < 0.45:
				var sc := _rng.randf_range(0.9, 1.05)
				var local := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25)).scaled(Vector3.ONE * sc),
						Vector3(x + _rng.randf_range(-0.15, 0.15), h, z))
				_add("spectator", xf * local, SHIRTS[_rng.randi() % SHIRTS.size()])
			x += 0.85


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
	# Start straight: pits and tower on the infield side (as at real circuits),
	# the main grandstands facing them.
	var pits := circuit.infield_side()
	var stands := 1 - pits
	_place_building("grandstand", length - 75.0, stands, 9.5)
	_place_building("grandstand", length - 125.0, stands, 9.5)
	_place_building("grandstand", length - 175.0, stands, 9.5)
	_place_building("grandstand", length - 225.0, stands, 9.5)
	_place_building("pit_building", length - 120.0, pits, 12.0)
	_place_building("control_tower", length - 35.0, pits, 10.0)
	_place_building("grandstand", length - 200.0, pits, 9.5)
	_place_building("grandstand", length + 30.0, stands, 9.5)
	# Stands behind each spectator corner (two along the tightest ones).
	for zi in _spectator_zones.size() - 1:
		var z := _spectator_zones[zi]
		var mid := (z.x + z.y) * 0.5
		_place_building("grandstand", mid, int(z.z), 9.0)
		if zi < 3:
			_place_building("grandstand", mid + 46.0, int(z.z), 9.0)


# --- paddock, car park, camping, hamlets ---------------------------------------------

## Low-poly coloured boxes merged into one mesh: [[size, centre, colour], ...].
func _box_mesh(boxes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Array in boxes:
		var size: Vector3 = b[0]
		var c: Vector3 = b[1]
		var col: Color = b[2]
		var h := size * 0.5
		var faces := [
			[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
			[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
			[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
			[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
			[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		]
		for f: Array in faces:
			var q: Array[Vector3] = []
			for v: Vector3 in f:
				q.append(c + v * h)
			for idx: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(col)
				st.add_vertex(q[idx])
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mesh.surface_set_material(0, mat)
	return mesh


func _scatter(node_name: String, mesh: Mesh, xforms: Array[Transform3D], tints: Array[Color]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)


func _free_spot(p: Vector3, min_dist: float) -> bool:
	if not _clear_of_track(p, min_dist):
		return false
	for r in _keep_clear:
		if r.has_point(Vector2(p.x, p.z)):
			return false
	return true


## Keep trees and other things out of a rectangle (half size in the frame).
func _claim(xf: Transform3D, half: Vector2) -> void:
	var r := Rect2(Vector2(xf.origin.x, xf.origin.z), Vector2.ZERO)
	for c: Vector3 in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		var w := xf * c
		r = r.expand(Vector2(w.x, w.z))
	_keep_clear.append(r.grow(3.0))


## Team trucks and motorhomes parked behind the pit building.
func _build_paddock() -> void:
	var frame := _frame(circuit.length - 120.0, circuit.infield_side(), 34.0)
	if frame.basis.x == Vector3.ZERO:
		return
	var white := Color(0.95, 0.95, 0.95)
	var truck := _box_mesh([
		[Vector3(2.5, 3.4, 12.0), Vector3(0, 2.1, -1.5), white],
		[Vector3(2.5, 2.6, 2.6), Vector3(0, 1.7, 5.9), white],
		[Vector3(2.3, 0.9, 0.1), Vector3(0, 2.5, 7.21), Color(0.1, 0.12, 0.16)],
		[Vector3(2.6, 0.5, 14.8), Vector3(0, 0.45, 0.0), Color(0.12, 0.12, 0.13)]])
	var home := _box_mesh([
		[Vector3(2.5, 3.0, 9.0), Vector3(0, 1.9, 0), white],
		[Vector3(2.52, 0.7, 7.0), Vector3(0, 2.3, 0), Color(0.1, 0.12, 0.16)],
		[Vector3(2.6, 0.45, 9.2), Vector3(0, 0.4, 0), Color(0.12, 0.12, 0.13)]])
	var team_colors := [Color(0.85, 0.15, 0.12), Color(0.15, 0.3, 0.8), Color(0.95, 0.75, 0.1), Color(0.15, 0.55, 0.3),
		Color(0.2, 0.2, 0.22), Color(0.95, 0.45, 0.1), Color(0.55, 0.2, 0.7), Color(0.9, 0.9, 0.9)]
	var trucks: Array[Transform3D] = []
	var truck_tints: Array[Color] = []
	var homes: Array[Transform3D] = []
	var home_tints: Array[Color] = []
	for k in 8:
		var col: Color = team_colors[k]
		var xf := frame * Transform3D(Basis.IDENTITY, Vector3(-26.0 + k * 7.5, 0, 0))
		if _free_spot(xf.origin, 20.0):
			trucks.append(xf)
			truck_tints.append(col)
		var hxf := frame * Transform3D(Basis.IDENTITY, Vector3(-26.0 + k * 7.5, 0, -16.0))
		if _free_spot(hxf.origin, 20.0):
			homes.append(hxf)
			home_tints.append(col.lerp(Color.WHITE, 0.6))
	_scatter("PaddockTrucks", truck, trucks, truck_tints)
	_scatter("Motorhomes", home, homes, home_tints)
	_claim(frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, -8.0)), Vector2(34.0, 16.0))


## Rows of parked cars behind the main grandstands.
func _build_car_park() -> void:
	var frame := _frame(circuit.length - 140.0, 1 - circuit.infield_side(), 34.0)
	if frame.basis.x == Vector3.ZERO:
		return
	var car := _box_mesh([
		[Vector3(1.75, 0.7, 4.3), Vector3(0, 0.6, 0), Color(1, 1, 1)],
		[Vector3(1.55, 0.55, 2.2), Vector3(0, 1.22, -0.2), Color(0.55, 0.6, 0.66)],
		[Vector3(1.8, 0.3, 4.32), Vector3(0, 0.25, 0), Color(0.08, 0.08, 0.09)]])
	var colors := [Color(0.85, 0.85, 0.85), Color(0.15, 0.15, 0.17), Color(0.7, 0.12, 0.1), Color(0.15, 0.3, 0.7),
		Color(0.55, 0.57, 0.6), Color(0.9, 0.9, 0.88), Color(0.2, 0.45, 0.25), Color(0.8, 0.6, 0.15)]
	var xforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	for row in 5:
		for k in 22:
			if _rng.randf() < 0.22:
				continue
			var yaw := (0.0 if row % 2 == 0 else PI) + _rng.randf_range(-0.06, 0.06)
			var xf := frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(-38.0 + k * 3.6, 0, -row * 7.0 - 3.0))
			if _free_spot(xf.origin, 16.0):
				xforms.append(xf)
				tints.append(colors[_rng.randi() % colors.size()])
	if xforms.is_empty():
		return
	_scatter("CarPark", car, xforms, tints)
	var lot := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(84.0, 36.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.4, 0.37)
	mat.roughness = 1.0
	plane.material = mat
	lot.mesh = plane
	lot.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, 0.015, -15.0))
	add_child(lot)
	_claim(frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, -15.0)), Vector2(42.0, 18.0))


## Fans camping in colourful tents behind two of the spectator corners.
func _build_camping() -> void:
	var tent := _tent_mesh()
	var xforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var colors := [Color(0.9, 0.3, 0.15), Color(0.2, 0.5, 0.85), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.35), Color(0.9, 0.9, 0.9)]
	for zi in mini(2, _spectator_zones.size() - 1):
		var z := _spectator_zones[zi]
		var frame := _frame((z.x + z.y) * 0.5 - 30.0, int(z.z), 26.0)
		if frame.basis.x == Vector3.ZERO:
			continue
		for k in 18:
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3))
			var xf := frame * Transform3D(b, Vector3(_rng.randf_range(-28.0, 28.0), 0, -_rng.randf_range(0.0, 18.0)))
			if _free_spot(xf.origin, 18.0):
				xforms.append(xf)
				tints.append(colors[_rng.randi() % colors.size()])
	_scatter("Tents", tent, xforms, tints)


func _tent_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 1.2
	var l := 1.6
	var top := 1.3
	var pts := [Vector3(-w, 0, -l), Vector3(w, 0, -l), Vector3(w, 0, l), Vector3(-w, 0, l), Vector3(0, top, -l), Vector3(0, top, l)]
	for tri: Array in [[0, 4, 5], [0, 5, 3], [1, 2, 5], [1, 5, 4], [0, 1, 4], [3, 5, 2]]:
		for idx: int in tri:
			st.set_color(Color.WHITE)
			st.add_vertex(pts[idx])
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


## A few small groups of houses (and a barn) around the circuit.
func _build_hamlets() -> void:
	var area := circuit._bounds.grow(260.0)
	var made := 0
	for attempt in 400:
		if made >= 5:
			break
		var p := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0, _rng.randf_range(area.position.y, area.end.y))
		var d := circuit.distance_from_centre(p)
		if d < 90.0 or d > 260.0:
			continue
		var h := circuit.ground_height(p.x, p.z)
		if absf(circuit.ground_height(p.x + 25.0, p.z) - h) > 3.0 or absf(circuit.ground_height(p.x, p.z + 25.0) - h) > 3.0:
			continue
		var blocked := false
		for r in _keep_clear:
			if r.has_point(Vector2(p.x, p.z)):
				blocked = true
		if blocked:
			continue
		made += 1
		var yaw := _rng.randf() * TAU
		for k in _rng.randi_range(3, 5):
			var q := p + Vector3(_rng.randf_range(-22.0, 22.0), 0, _rng.randf_range(-22.0, 22.0)).rotated(Vector3.UP, yaw)
			q.y = circuit.ground_height(q.x, q.z)
			var kind := "barn" if k == 0 and circuit.theme == "hills" else "house"
			var xf := Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.4, 0.4)), q)
			_add(kind, xf)
			_solid(kind, xf)


func _build_billboards() -> void:
	var s := _samples()
	var n := s.size()
	var placed := 0
	var i := 40
	while i < n and placed < 20:
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
		p.y = circuit.ground_height(p.x, p.z)
		if absf(circuit.ground_height(p.x + 20.0, p.z) - p.y) > 2.0 or absf(circuit.ground_height(p.x, p.z + 20.0) - p.y) > 2.0:
			continue  # farms want flat ground
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
	var mountains := circuit.theme == "mountains"
	var area := circuit._bounds.grow(700.0 if mountains else 600.0)
	var kinds := ["tree_pine", "tree_pine", "tree_pine_tall", "tree_round", "tree_round", "bush"]
	if mountains:
		kinds = ["tree_pine", "tree_pine", "tree_pine_tall", "tree_pine_tall", "bush"]
	var placed := 0
	var target := 1300 if mountains else 1100
	for attempt in 12000:
		if placed >= target:
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
		p.y = circuit.ground_height(p.x, p.z)
		if mountains and p.y > 175.0 + density * 40.0:
			continue  # tree line
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var sc := _rng.randf_range(0.8, 1.35)
		_add(kind, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		placed += 1
