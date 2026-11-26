class_name ObstacleCourse
extends Node3D
## Obstacle course on a hilly village road: a timed run through checkpoints.
## Village street with a cone slalom and a walled chicane, boost pads into a
## gap jump, a wrecking-ball alley, a narrow bridge over a ravine and a wobbly
## plank bridge, four tight hairpins up a hill, a seesaw, a lift down a cliff,
## a sideways roller conveyor, a turntable, boosts into a loop, and the road
## back down to the village. Fall off or get stuck: R / Y puts you back at the
## last checkpoint (it also happens by itself after a fall). Best time saved.
## Built from code; uses the trackside kit for houses, trees and blocks.

const LAYER_WORLD := 1
const LAYER_CARS := 2
const LAYER_PROPS := 4
const LAYER_WHEELS_ONLY := 8  ## tyres ride it, car bodies pass (the loop)
const KIT := "res://assets/track_kit/track_kit.glb"
var save_path := "user://obstacle_course.cfg"  ## best time (tests use another file)
const CELL := 8.0
const BOUNDS := Rect2(-130.0, -730.0, 480.0, 860.0)  ## terrain area (x, z)

const GRASS := Color(0.34, 0.5, 0.24)
const CONCRETE := Color(0.62, 0.6, 0.57)
const STEEL := Color(0.25, 0.26, 0.28)
const WOOD := Color(0.5, 0.36, 0.22)
const BOOST := Color(1.0, 0.55, 0.1)
const VERGE := Color(0.33, 0.36, 0.22)  ## the sloped road edge into the grass

## Run state (the HUD reads these).
var checkpoints: Array[Transform3D] = []
var next_cp := 0
var running := false
var run_time := 0.0
var best_time := INF
var best_splits := PackedFloat32Array()
var splits := PackedFloat32Array()
var message := ""
var message_color := Color.WHITE
var message_left := 0.0

var _car: Vehicle
var _respawn := Transform3D()
var _spawn := Transform3D()
var _upside := 0.0
var _kit: Dictionary = {}
var _batches: Dictionary = {}
var _mats: Dictionary = {}
var _road_tex: ImageTexture
var _ground: Array[Vector4] = []     ## road samples the land follows: x, y, z, half width
var _holes: Array[Dictionary] = []   ## {rect: Rect2 (x, z), y: float}: land sunk below
var _clear: Array[Vector4] = []      ## everything drivable (keep trees off): x, y, z, radius
var _pendulums: Array[Dictionary] = []
var _planks: Array[Dictionary] = []
var _lift: AnimatableBody3D
var _boom: AnimatableBody3D
var _loop_box := AABB()
var loop_line := PackedVector3Array()  ## the loop's centre line (tests follow it)
var _turntable: AnimatableBody3D
var _rollers: Array[Node3D] = []
var _boost_cool: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	add_to_group("obstacle_course")
	_load_kit()
	_road_tex = _make_road_texture()
	_build_atmosphere()
	_build_course()
	_build_terrain()
	_build_trees()
	_flush_kit()
	_build_hud()
	_load_best()


## Where the car starts (just behind the start gate).
func get_spawn_transform() -> Transform3D:
	return _spawn


# --- the course ----------------------------------------------------------------------

func _build_course() -> void:
	# A: village street, gentle climb, cone slalom.
	var a := _smooth([Vector3(0, 0, 14), Vector3(0, 0, 0), Vector3(0, 0.5, -40), Vector3(0, 1.5, -80),
			Vector3(6, 3, -130), Vector3(0, 4, -180), Vector3(0, 4, -200)])
	_road(a, 9.0)
	_spawn = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(0, 0.6, 8))
	_gate(_along(a, 14.0), 9.0, "START / FINISH")
	for i in 7:
		var xf := _along(a, 64.0 + i * 10.0)
		_cone(xf * Vector3(2.3 if i % 2 == 0 else -2.3, 0.0, 0.0))
	_village(a, 9.0)
	_gate(_along(a, _length(a) - 8.0), 9.0, "1")

	# B: narrow walled chicane.
	var b := _smooth([Vector3(0, 4, -200), Vector3(0, 4, -206), Vector3(2.5, 4, -214), Vector3(5, 4, -222), Vector3(5, 4, -228),
			Vector3(0, 4, -237), Vector3(-5, 4, -246), Vector3(-5, 4, -252), Vector3(-2.5, 4, -260), Vector3(0, 4, -266), Vector3(0, 4, -272)], 1.5)
	_road(b, 6.0)
	_walls(b, 6.0)

	# C: downhill with boost pads into a kicker and a gap jump.
	var c := _smooth([Vector3(0, 4, -272), Vector3(0, 3, -300), Vector3(0, 0, -350), Vector3(0, -2, -395)])
	_road(c, 9.0)
	for d: float in [22.0, 44.0, 66.0]:
		_boost_pad(_along(c, d), 7.0)
	_ramp(Vector3(0, -2, -395), Vector3(0, 0.6, -406), 9.0)    # kicker
	_ramp(Vector3(0, -0.6, -421), Vector3(0, -2, -434), 9.0)   # landing
	_holes.append({"rect": Rect2(-22, -421, 44, 16), "y": -30.0})

	# D: wrecking-ball alley.
	var d_path := _smooth([Vector3(0, -2, -434), Vector3(0, -2, -470), Vector3(0, -2, -520), Vector3(0, -2, -560)])
	_road(d_path, 9.0)
	_gate(_along(d_path, 4.0), 9.0, "2")
	for i in 4:
		_pendulum(Vector3(0, -2, -468.0 - i * 24.0), i * 0.25)
	_gate(_along(d_path, _length(d_path) - 6.0), 9.0, "3")

	# E: turn east, a narrow bridge over a ravine, then a wobbly plank bridge.
	var e := _smooth([Vector3(0, -2, -560), Vector3(2, -2, -580), Vector3(15, -2, -593), Vector3(36, -2, -595)])
	_road(e, 8.0)
	var bridge := _smooth([Vector3(36, -2, -595), Vector3(110, -2, -595)])
	_road(bridge, 4.5, [], false)
	_bridge_supports(36.0, 110.0, -595.0, -2.0, 4.5)
	_holes.append({"rect": Rect2(34, -614, 140, 38), "y": -32.0})
	_plank_bridge(110.0, 160.0, -595.0, -2.0, 5.0)
	var f := _smooth([Vector3(160, -2, -595), Vector3(185, -2, -595), Vector3(200, -2, -603), Vector3(200, -2, -610)])
	_road(f, 8.0)
	_gate(_along(f, 12.0), 8.0, "4")

	# G: four tight hairpins up the hill.
	var g: Array = [Vector3(200, -2, -610)]
	g.append_array(_line(Vector3(200, -2, -610), Vector3(200, 6, -655), 4.0))
	g.append_array(_hairpin(Vector3(208, 6, -655), 8.0, -1.0))
	g.append_array(_line(Vector3(216, 6, -655), Vector3(216, 14, -610), 4.0))
	g.append_array(_hairpin(Vector3(224, 14, -610), 8.0, 1.0))
	g.append_array(_line(Vector3(232, 14, -610), Vector3(232, 22, -655), 4.0))
	g.append_array(_hairpin(Vector3(240, 22, -655), 8.0, -1.0))
	g.append_array(_line(Vector3(248, 22, -655), Vector3(248, 26, -604), 4.0))
	var hp := PackedVector3Array(g)
	_road(hp, 6.0)
	_gate(_along(hp, _length(hp) - 4.0), 6.0, "5")

	# H: on top: the seesaw, then the lift down the cliff.
	_road(_smooth([Vector3(248, 26, -604), Vector3(248, 26, -597)]), 8.0)
	_seesaw(Vector3(248, 26, -589.5), 8.0, 14.0)
	_road(_smooth([Vector3(248, 26, -582), Vector3(248, 26, -552)]), 8.0)
	_build_lift(Vector3(248, 0, -547), 10.0, 26.0, 10.0)
	_holes.append({"rect": Rect2(241, -553, 14, 12), "y": 9.4})
	var lower := _smooth([Vector3(248, 10, -542), Vector3(248, 10, -500)])
	_road(lower, 8.0)
	_gate(_along(lower, 12.0), 8.0, "6")

	# I: sideways roller conveyor and a turntable.
	_conveyor(Vector3(248, 10, -494), 8.0, 12.0, Vector3(2.5, 0, 0))
	_road(_smooth([Vector3(248, 10, -488), Vector3(248, 10, -470)]), 8.0)
	_build_turntable(Vector3(248, 10, -461), 9.0)

	# J: boosts into the loop.
	var run_in := _smooth([Vector3(248, 10, -452), Vector3(248, 10, -415)])
	_road(run_in, 8.0)
	for dd: float in [6.0, 16.0, 26.0]:
		_boost_pad(_along(run_in, dd), 7.0)
	var out := _loop(Vector3(248, 10, -415), 62.0, 10.0, 8.0)

	# K: back down to the village and the finish.
	var home := _smooth([out, out + Vector3(0, 0, 18), Vector3(258, 6, -330), Vector3(255, 3, -220),
			Vector3(248, 1, -110), Vector3(236, 0, -10), Vector3(210, 0, 38), Vector3(120, 0, 46),
			Vector3(40, 0, 42), Vector3(8, 0, 30), Vector3(0, 0, 14)])
	_road(home, 9.0)
	_gate(_along(home, 14.0), 9.0, "7")
	_village(home, 9.0, _length(home) - 170.0)


## Smooth path through points (Catmull-Rom), one point every `step` metres.
func _smooth(pts: Array, step: float = 3.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		var segs := maxi(int(ceil(p1.distance_to(p2) / step)), 1)
		for k in segs:
			var t := float(k) / segs
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func _line(a: Vector3, b: Vector3, step: float) -> Array:
	var out: Array = []
	var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
	for k in range(1, n + 1):
		out.append(a.lerp(b, float(k) / n))
	return out


## Half-circle turn round `centre` (from x - r to x + r), bulging north
## (side = -1, towards -z) or south (+1).
func _hairpin(centre: Vector3, r: float, side: float) -> Array:
	var out: Array = []
	for k in range(1, 12):
		var a := PI - PI * k / 12.0
		out.append(centre + Vector3(cos(a) * r, 0.0, side * sin(a) * r))
	return out


func _length(path: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i].distance_to(path[i - 1])
	return l


## Frame at distance `d` along the path: origin on the road, -Z = forward.
func _along(path: PackedVector3Array, d: float) -> Transform3D:
	var acc := 0.0
	for i in range(1, path.size()):
		var seg := path[i].distance_to(path[i - 1])
		if acc + seg >= d or i == path.size() - 1:
			var t := clampf((d - acc) / maxf(seg, 0.001), 0.0, 1.0)
			var p := path[i - 1].lerp(path[i], t)
			var fwd := (path[i] - path[i - 1]).normalized()
			var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
			return Transform3D(Basis.looking_at(flat, Vector3.UP), p)
		acc += seg
	return Transform3D(Basis.IDENTITY, path[path.size() - 1])


# --- roads -----------------------------------------------------------------------------

## A road ribbon along `path`, `width` wide, with its own collision. `ups`
## (optional, one per point) tilts it (the loop); `ground` = the land follows it.
func _road(path: PackedVector3Array, width: float, ups: Array = [], ground: bool = true, layer: int = LAYER_WORLD, visual: bool = true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var n := path.size()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var downs: Array[Vector3] = []
	var dist := 0.0
	var vs: Array[float] = []
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var up: Vector3 = ups[i] if i < ups.size() else Vector3.UP
		var right := t.cross(up).normalized()
		var up2 := right.cross(t).normalized()
		lefts.append(path[i] - right * width * 0.5)
		rights.append(path[i] + right * width * 0.5)
		downs.append(-up2)
		if i > 0:
			dist += path[i].distance_to(path[i - 1])
		vs.append(dist / width)
		if ground and i % 2 == 0:
			_ground.append(Vector4(path[i].x, path[i].y, path[i].z, width * 0.5))
		_clear.append(Vector4(path[i].x, path[i].y, path[i].z, width * 0.5 + 3.0))
	for i in n - 1:
		var l0 := lefts[i]
		var r0 := rights[i]
		var l1 := lefts[i + 1]
		var r1 := rights[i + 1]
		st.set_uv(Vector2(0, vs[i]))
		st.add_vertex(l0)
		st.set_uv(Vector2(1, vs[i + 1]))
		st.add_vertex(r1)
		st.set_uv(Vector2(1, vs[i]))
		st.add_vertex(r0)
		st.set_uv(Vector2(0, vs[i]))
		st.add_vertex(l0)
		st.set_uv(Vector2(0, vs[i + 1]))
		st.add_vertex(l1)
		st.set_uv(Vector2(1, vs[i + 1]))
		st.add_vertex(r1)
		faces.append_array([l0, r1, r0, l0, l1, r1])
		if ground:
			var out0 := (l0 - r0).normalized() * 1.4
			var out1 := (l1 - r1).normalized() * 1.4
			var drop := Vector3.DOWN * 0.55
			var ll0 := l0 + out0 + drop
			var ll1 := l1 + out1 + drop
			var rr0 := r0 - out0 + drop
			var rr1 := r1 - out1 + drop
			faces.append_array([ll0, l1, l0, ll0, ll1, l1, r0, rr1, rr0, r0, r1, rr1])
			for tri: Array in [[ll0, l1, l0], [ll0, ll1, l1], [r0, rr1, rr0], [r0, r1, rr1]]:
				for v: Vector3 in tri:
					side.add_vertex(v)
			continue
		# Edges: a slab 40 cm thick so the road reads as solid.
		var d0 := downs[i] * 0.4
		var d1 := downs[i + 1] * 0.4
		for e: Array in [[l0, l1], [r1, r0]]:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			side.add_vertex(a)
			side.add_vertex(b + (d1 if e[0] == l0 else d0))
			side.add_vertex(a + (d0 if e[0] == l0 else d1))
			side.add_vertex(a)
			side.add_vertex(b)
			side.add_vertex(b + (d1 if e[0] == l0 else d0))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta(&"surface_grip", 1.0)
	body.set_meta(&"surface_drag", 0.0)
	body.set_meta(&"road", true)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body, true)
	if not visual:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	side.generate_normals()
	var side_mesh := side.commit()
	var side_mat := _mat(VERGE if ground else CONCRETE).duplicate() as StandardMaterial3D
	side_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	side_mesh.surface_set_material(0, side_mat)
	var smi := MeshInstance3D.new()
	smi.mesh = side_mesh
	body.add_child(smi)


func _make_road_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in 64:
		for x in 64:
			var v := rng.randf_range(0.18, 0.25)
			img.set_pixel(x, y, Color(v, v, v + 0.01))
	img.fill_rect(Rect2i(2, 0, 2, 64), Color(0.9, 0.9, 0.86))
	img.fill_rect(Rect2i(60, 0, 2, 64), Color(0.9, 0.9, 0.86))
	for y in range(0, 64, 16):
		img.fill_rect(Rect2i(31, y, 2, 8), Color(0.95, 0.8, 0.2))
	return ImageTexture.create_from_image(img)


## A straight ramp slab from `a` to `b` (centre line points), `width` wide.
func _ramp(a: Vector3, b: Vector3, width: float) -> void:
	_road(_smooth([a, b], 1.0), width)


## Concrete blocks with collision along both sides of a path.
func _walls(path: PackedVector3Array, width: float) -> void:
	var body := _static("Walls")
	for i in range(0, path.size() - 1, 2):
		var p := path[i]
		var t := (path[mini(i + 2, path.size() - 1)] - p)
		t.y = 0.0
		if t.length() < 0.5:
			continue
		var basis := Basis.looking_at(t.normalized(), Vector3.UP)
		for s: float in [-1.0, 1.0]:
			var pos := p + basis.x * s * (width * 0.5 + 0.4)
			var xf := Transform3D(basis.rotated(Vector3.UP, PI * 0.5), pos)
			_add("concrete_white" if (i / 2) % 2 == 0 else "concrete_red", xf)
			_box(body, Vector3(t.length() + 0.2, 0.9, 0.6), Transform3D(basis.rotated(Vector3.UP, PI * 0.5), pos + Vector3(0, 0.45, 0)))


# --- checkpoints, cones, boosts ----------------------------------------------------------

## A checkpoint gate across the road at `xf` (index = order); its trigger
## counts the run.
func _gate(xf: Transform3D, width: float, label: String) -> void:
	var index := checkpoints.size()
	var forward := -xf.basis.z
	checkpoints.append(Transform3D(xf.basis, xf.origin + forward * 4.0 + Vector3.UP * 0.6))
	var post_x := width * 0.5 + 1.2
	var body := _static("Gate%d" % index)
	var col := Color(0.9, 0.12, 0.1) if index == 0 else Color(0.15, 0.55, 1.0)
	for s: float in [-1.0, 1.0]:
		var p := xf * Vector3(s * post_x, 2.5, 0.0)
		_box(body, Vector3(0.5, 5.0, 0.5), Transform3D(xf.basis, p))
		_paint(Vector3(0.5, 5.0, 0.5), Transform3D(xf.basis, p), Color(0.92, 0.92, 0.9))
	_paint(Vector3(post_x * 2.0 + 0.5, 1.1, 0.3), Transform3D(xf.basis, xf * Vector3(0, 5.4, 0)), col)
	var text := Label3D.new()
	text.text = label if index == 0 else "CHECKPOINT " + label
	text.font_size = 96
	text.pixel_size = 0.01
	text.outline_size = 12
	text.transform = Transform3D(xf.basis, xf * Vector3(0, 5.4, 0.2))
	add_child(text)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = LAYER_CARS
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + 2.0, 8.0, 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	area.add_child(cs)
	area.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 3.0)
	area.body_entered.connect(func(b: Node3D) -> void: _through_gate(b, index))
	add_child(area)


func _cone(pos: Vector3) -> void:
	var cone := RigidBody3D.new()
	cone.mass = 4.0
	cone.collision_layer = LAYER_PROPS
	cone.collision_mask = 1 | 2 | 4
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = 0.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.4
	cone.add_child(cs)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.26
	mesh.height = 0.8
	mesh.material = _mat(Color(1.0, 0.45, 0.05))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.4
	cone.add_child(mi)
	cone.position = pos + Vector3.UP * 0.05
	add_child(cone)


## Orange chevrons on the road; driving over them kicks the car forward.
func _boost_pad(xf: Transform3D, width: float) -> void:
	var on_road := Transform3D(xf.basis, xf.origin + Vector3.UP * 0.03)
	for k in 3:
		for s: float in [-1.0, 1.0]:
			var piece := Transform3D(on_road.basis.rotated(on_road.basis.y, s * 0.6), on_road * Vector3(s * width * 0.17, 0, -k * 1.2))
			_paint(Vector3(width * 0.4, 0.04, 0.35), piece, BOOST, 1.6)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = LAYER_CARS
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 1.6, 3.5)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	area.add_child(cs)
	area.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.8)
	var fwd := -xf.basis.z
	area.body_entered.connect(func(b: Node3D) -> void:
		var car := b as Vehicle
		if car == null or _t - float(_boost_cool.get(car, -9.0)) < 0.6:
			return
		_boost_cool[car] = _t
		car.apply_central_impulse(fwd * car.mass * 7.5)
		if car == _car:
			_say("BOOST!", BOOST, 0.7))
	add_child(area)


# --- obstacles -----------------------------------------------------------------------------

## A wrecking ball on a chain from a gantry, swinging across the road.
func _pendulum(base: Vector3, phase: float) -> void:
	var height := 13.0
	var length := 10.5
	var gantry := _static("Gantry")
	for s: float in [-1.0, 1.0]:
		var p := base + Vector3(s * 7.0, height * 0.5, 0)
		_box(gantry, Vector3(0.6, height, 0.6), Transform3D(Basis.IDENTITY, p))
		_paint(Vector3(0.6, height, 0.6), Transform3D(Basis.IDENTITY, p), Color(0.85, 0.75, 0.1))
	_paint(Vector3(15.0, 0.7, 0.7), Transform3D(Basis.IDENTITY, base + Vector3(0, height, 0)), Color(0.85, 0.75, 0.1))
	var pivot := Node3D.new()
	pivot.position = base + Vector3(0, height, 0)
	add_child(pivot)
	var chain := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = length
	cyl.material = _mat(STEEL)
	chain.mesh = cyl
	chain.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(chain)
	var ball := AnimatableBody3D.new()
	ball.collision_layer = LAYER_WORLD | LAYER_PROPS
	ball.collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ball.add_child(cs)
	var mesh := SphereMesh.new()
	mesh.radius = 1.6
	mesh.height = 3.2
	mesh.radial_segments = 12
	mesh.rings = 6
	var m := _mat(Color(0.16, 0.16, 0.18)).duplicate() as StandardMaterial3D
	m.metallic = 0.8
	m.roughness = 0.35
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	ball.add_child(mi)
	# The ball is moved itself each tick (a body moved only through its
	# parent doesn't move in the physics world).
	ball.position = pivot.position + Vector3(0, -length, 0)
	add_child(ball)
	_pendulums.append({"pivot": pivot, "ball": ball, "length": length, "phase": phase})


## Pillars under the narrow bridge, down into the ravine.
func _bridge_supports(x0: float, x1: float, z: float, y: float, width: float) -> void:
	var body := _static("BridgeSupports")
	var x := x0 + 12.0
	while x < x1 - 4.0:
		var p := Vector3(x, y - 16.0, z)
		_box(body, Vector3(2.0, 30.0, width * 0.7), Transform3D(Basis.IDENTITY, p))
		_paint(Vector3(2.0, 30.0, width * 0.7), Transform3D(Basis.IDENTITY, p), CONCRETE)
		x += 18.0


## Planks that bob and roll, each a moving body; rope rails either side.
func _plank_bridge(x0: float, x1: float, z: float, y: float, width: float) -> void:
	var x := x0
	var i := 0
	while x < x1 - 0.5:
		var plank := AnimatableBody3D.new()
		plank.collision_layer = LAYER_WORLD
		plank.collision_mask = 0
		plank.set_meta(&"surface_grip", 0.95)
		plank.set_meta(&"surface_drag", 0.0)
		plank.set_meta(&"road", true)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.15, 0.25, width)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		plank.add_child(cs)
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		mesh.material = _mat(WOOD if i % 2 == 0 else WOOD.darkened(0.15))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		plank.add_child(mi)
		var base := Vector3(x + 0.6, y - 0.125, z)
		plank.position = base
		add_child(plank)
		_planks.append({"body": plank, "base": base, "i": i})
		_clear.append(Vector4(base.x, base.y, base.z, width * 0.5 + 3.0))
		x += 1.2
		i += 1
	for s: float in [-1.0, 1.0]:
		_paint(Vector3(x1 - x0, 0.08, 0.08), Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, y + 0.9, z + s * (width * 0.5 + 0.2))), WOOD)


## A plank on a hinge: drive up, it tips over and lets you down the far side.
func _seesaw(pivot: Vector3, width: float, length: float) -> void:
	var stand := _static("SeesawStand")
	var hinge_at := pivot + Vector3(0, 1.2, 0)
	_box(stand, Vector3(width * 0.6, 1.0, 1.0), Transform3D(Basis.IDENTITY, pivot + Vector3(0, 0.5, 0)))
	_paint(Vector3(width * 0.6, 1.0, 1.0), Transform3D(Basis.IDENTITY, pivot + Vector3(0, 0.5, 0)), CONCRETE)
	var plank := RigidBody3D.new()
	plank.name = "Seesaw"
	plank.mass = 700.0
	plank.collision_layer = LAYER_WORLD
	plank.collision_mask = LAYER_WORLD | LAYER_CARS
	plank.angular_damp = 1.5
	# Heavier on the near side, so it swings back after a car has gone over
	# (it stayed tipped away, a wall for the next lap).
	plank.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	plank.center_of_mass = Vector3(0, 0, -1.0)
	plank.can_sleep = false
	plank.set_meta(&"surface_grip", 1.0)
	plank.set_meta(&"surface_drag", 0.0)
	plank.set_meta(&"road", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.4, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	plank.add_child(cs)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh.material = _mat(Color(0.75, 0.55, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	plank.add_child(mi)
	# Resting with the near end (smaller z) down.
	plank.transform = Transform3D(Basis(Vector3.RIGHT, -asin(1.2 / (length * 0.5))), hinge_at)
	add_child(plank)
	var joint := HingeJoint3D.new()
	joint.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), hinge_at)  # hinge axis along x
	add_child(joint)
	joint.node_a = joint.get_path_to(stand)
	joint.node_b = joint.get_path_to(plank)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(14.0))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-14.0))
	_clear.append(Vector4(pivot.x, pivot.y, pivot.z, length * 0.6))


## A platform that goes down the cliff and back up.
func _build_lift(at: Vector3, size: float, top: float, bottom: float) -> void:
	_lift = AnimatableBody3D.new()
	_lift.name = "Lift"
	_lift.collision_layer = LAYER_WORLD
	_lift.collision_mask = 0
	_lift.set_meta(&"surface_grip", 1.0)
	_lift.set_meta(&"surface_drag", 0.0)
	_lift.set_meta(&"road", true)
	_lift.set_meta(&"top", top)
	_lift.set_meta(&"bottom", bottom)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 0.6, size)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_lift.add_child(cs)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh.material = _mat(Color(0.3, 0.32, 0.36))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_lift.add_child(mi)
	# Yellow-black edge stripes.
	for s: float in [-1.0, 1.0]:
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size, 0.62, 0.5)
		bm.material = _mat(Color(0.95, 0.8, 0.1))
		stripe.mesh = bm
		stripe.position = Vector3(0, 0, s * (size * 0.5 - 0.25))
		_lift.add_child(stripe)
	_lift.position = Vector3(at.x, top - 0.3, at.z)
	add_child(_lift)
	# Guide posts at the corners.
	var posts := _static("LiftPosts")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(at.x + sx * (size * 0.5 + 0.5), (top + bottom) * 0.5 + 1.5, at.z + sz * (size * 0.5 - 0.5))
			_box(posts, Vector3(0.4, top - bottom + 3.0, 0.4), Transform3D(Basis.IDENTITY, p))
			_paint(Vector3(0.4, top - bottom + 3.0, 0.4), Transform3D(Basis.IDENTITY, p), Color(0.85, 0.75, 0.1))
	_clear.append(Vector4(at.x, top, at.z, size))
	# A boom across the top edge: down while the lift is away, so nobody
	# drives into the empty shaft.
	_boom = AnimatableBody3D.new()
	_boom.name = "LiftBoom"
	_boom.collision_layer = LAYER_WORLD
	_boom.collision_mask = 0
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(size + 1.0, 0.35, 0.35)
	var bcs := CollisionShape3D.new()
	bcs.shape = bshape
	_boom.add_child(bcs)
	for k in 6:
		var seg := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3((size + 1.0) / 6.0, 0.35, 0.35)
		sm.material = _mat(Color(0.9, 0.1, 0.08) if k % 2 == 0 else Color(0.95, 0.95, 0.92))
		seg.mesh = sm
		seg.position.x = -(size + 1.0) * 0.5 + (k + 0.5) * (size + 1.0) / 6.0
		_boom.add_child(seg)
	_boom.position = Vector3(at.x, top + 4.0, at.z - size * 0.5 - 1.0)
	_boom.set_meta(&"top", top)
	add_child(_boom)


## A belt of rollers across the road that pushes cars sideways.
func _conveyor(centre: Vector3, width: float, length: float, push: Vector3) -> void:
	var belt := StaticBody3D.new()
	belt.name = "Conveyor"
	belt.collision_layer = LAYER_WORLD
	belt.collision_mask = 0
	belt.constant_linear_velocity = push
	belt.set_meta(&"surface_grip", 1.0)
	belt.set_meta(&"surface_drag", 0.0)
	belt.set_meta(&"road", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.5, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.25, 0)
	belt.add_child(cs)
	belt.position = centre
	add_child(belt)
	var z := -length * 0.5 + 0.3
	while z < length * 0.5:
		var r := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.26
		cyl.bottom_radius = 0.26
		cyl.height = width
		cyl.radial_segments = 8
		cyl.material = _mat(Color(0.55, 0.57, 0.6) if int(z * 2.0) % 2 == 0 else Color(0.85, 0.3, 0.1))
		r.mesh = cyl
		var holder := Node3D.new()
		holder.position = centre + Vector3(0, -0.27, z)
		r.rotation = Vector3(0, 0, PI * 0.5)
		holder.add_child(r)
		add_child(holder)
		_rollers.append(r)
		z += 0.6
	_clear.append(Vector4(centre.x, centre.y, centre.z, length * 0.6))


## A big turning disc set into the road.
func _build_turntable(centre: Vector3, radius: float) -> void:
	_turntable = AnimatableBody3D.new()
	_turntable.name = "Turntable"
	_turntable.collision_layer = LAYER_WORLD
	_turntable.collision_mask = 0
	_turntable.set_meta(&"surface_grip", 1.0)
	_turntable.set_meta(&"surface_drag", 0.0)
	_turntable.set_meta(&"road", true)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_turntable.add_child(cs)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.5
	mesh.radial_segments = 24
	mesh.material = _mat(Color(0.35, 0.36, 0.4))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_turntable.add_child(mi)
	for k in 4:
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(radius * 2.0, 0.52, 0.5)
		bm.material = _mat(Color(0.95, 0.8, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.12))
		stripe.mesh = bm
		stripe.rotation.y = k * PI * 0.25
		_turntable.add_child(stripe)
	_turntable.position = centre + Vector3(0, -0.25, 0)
	add_child(_turntable)
	_ground.append(Vector4(centre.x, centre.y, centre.z, radius))
	_clear.append(Vector4(centre.x, centre.y, centre.z, radius + 3.0))


## A full loop (a helix, so the exit clears the entry), entering heading +z.
## A full loop, entering heading +z; returns where it comes out. Shaped like
## a stunt loop: the bend tightens gradually from the bottom to a tight top
## and opens out again (a round loop would hit the car with 5 g at the
## entry). It drifts `shift` sideways so the exit clears the entry.
func _loop(entry: Vector3, length: float, shift: float, width: float) -> Vector3:
	var n := 180
	var ds := length / n
	var weights: Array[float] = []
	var total := 0.0
	for k in n:
		var u := (k + 0.5) / n
		var w := smoothstep(0.0, 0.42, u) * smoothstep(0.0, 0.42, 1.0 - u)
		weights.append(w)
		total += w * ds
	var kappa := TAU / total
	var pts := PackedVector3Array([entry])
	var ups: Array = [Vector3.UP]
	var theta := 0.0
	var p := Vector3.ZERO
	var top := 0.0
	for k in n:
		theta += kappa * weights[k] * ds * 0.5
		p += Vector3(0.0, sin(theta), cos(theta)) * ds
		theta += kappa * weights[k] * ds * 0.5
		top = maxf(top, p.y)
		var u := float(k + 1) / n
		pts.append(entry + Vector3(shift * smoothstep(0.0, 1.0, u), p.y, p.z))
		ups.append(Vector3(0.0, cos(theta), -sin(theta)))
	loop_line = pts
	_road(pts, width, ups, false, LAYER_WHEELS_ONLY)
	# A hidden floor just under it for the car body, in case the suspension
	# bottoms out (it meets the road at both ends, so nothing to catch on).
	var floor_pts := PackedVector3Array()
	for k in pts.size():
		var u := float(k) / (pts.size() - 1)
		var sink := 0.3 * smoothstep(0.0, 0.12, u) * smoothstep(0.0, 0.12, 1.0 - u)
		floor_pts.append(pts[k] - (ups[k] as Vector3) * sink)
	_road(floor_pts, width, ups, false, LAYER_WORLD, false)
	var zs := [entry.z]
	for q in pts:
		zs.append(q.z)
	var z0: float = zs.min()
	var z1: float = zs.max()
	_loop_box = AABB(Vector3(entry.x - width, entry.y + 0.5, z0 - 1.0), Vector3(shift + width * 2.0, top + 2.0, z1 - z0 + 2.0))
	_ground.append(Vector4(entry.x + shift * 0.5, entry.y, (z0 + z1) * 0.5, (z1 - z0) * 0.5 + width))
	return pts[pts.size() - 1]


# --- village, trees --------------------------------------------------------------------------

## Houses and barns along a road (from `from_d` metres on).
func _village(path: PackedVector3Array, width: float, from_d: float = 0.0) -> void:
	var d := from_d + 10.0
	var total := _length(path)
	var k := 0
	while d < total - 10.0:
		var xf := _along(path, d)
		for s: float in [-1.0, 1.0]:
			if (k + int(s)) % 3 == 0:
				continue
			var kind := "barn" if k % 5 == 2 else "house"
			var off := width * 0.5 + (10.0 if kind == "barn" else 8.0)
			var pos := xf * Vector3(s * off, 0.0, 0.0)
			# Facing the road.
			var to_road := (xf.origin - pos)
			to_road.y = 0.0
			var basis := Basis.looking_at(-to_road.normalized(), Vector3.UP)
			_add(kind, Transform3D(basis, pos + Vector3.DOWN * 0.2))
			_solid(kind, Transform3D(basis, pos + Vector3.DOWN * 0.2))
			_add("bush", Transform3D(basis, xf * Vector3(s * (width * 0.5 + 3.0), 0, 2.5)))
		d += 17.0
		k += 1


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var kinds := ["tree_round", "tree_pine", "tree_pine_tall"]
	var placed := 0
	for attempt in 2600:
		if placed >= 420:
			break
		var x := rng.randf_range(BOUNDS.position.x + 10.0, BOUNDS.end.x - 10.0)
		var z := rng.randf_range(BOUNDS.position.y + 10.0, BOUNDS.end.y - 10.0)
		if not _free_spot(x, z, 7.0):
			continue
		var y := _land_height(x, z)
		var sc := rng.randf_range(0.8, 1.3)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y - 0.2, z))
		_add(kinds[rng.randi() % kinds.size()], xf)
		placed += 1


func _free_spot(x: float, z: float, margin: float) -> bool:
	for c in _clear:
		if Vector2(c.x - x, c.z - z).length() < c.w + margin:
			return false
	for h in _holes:
		if (h.rect as Rect2).grow(4.0).has_point(Vector2(x, z)):
			return false
	return true


# --- land ------------------------------------------------------------------------------------

var _heights := PackedFloat32Array()
var _gw := 0
var _gh := 0
var _noise := FastNoiseLite.new()


## Hills that follow the course: right under each road the land sits just
## below it, further out it rolls up into hills; holes (the gap, the ravine,
## the lift shaft) are sunk.
func _build_terrain() -> void:
	_noise.seed = 9
	_noise.frequency = 0.006
	_gw = int(BOUNDS.size.x / CELL) + 1
	_gh = int(BOUNDS.size.y / CELL) + 1
	_heights.resize(_gw * _gh)
	var hash := _sample_hash()
	for j in _gh:
		for i in _gw:
			var x := BOUNDS.position.x + i * CELL
			var z := BOUNDS.position.y + j * CELL
			_heights[j * _gw + i] = _height_at(x, z, hash)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in _gh - 1:
		for i in _gw - 1:
			var p := [_grid_point(i, j), _grid_point(i + 1, j), _grid_point(i + 1, j + 1), _grid_point(i, j + 1)]
			for idx: int in [0, 2, 1, 0, 3, 2]:
				var v: Vector3 = p[idx]
				var shade := 0.85 + 0.15 * _noise.get_noise_2d(v.x * 3.0, v.z * 3.0)
				var col := GRASS * shade
				if v.y < -10.0:
					col = Color(0.42, 0.36, 0.28) * shade  # rock in the ravine
				st.set_color(col)
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface_grip", 0.6)
	body.set_meta(&"surface_drag", 0.05)
	var shape := HeightMapShape3D.new()
	shape.map_width = _gw
	shape.map_depth = _gh
	shape.map_data = _heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)
	cs.position = Vector3(BOUNDS.position.x + (_gw - 1) * CELL * 0.5, 0.0, BOUNDS.position.y + (_gh - 1) * CELL * 0.5)
	body.add_child(cs)
	add_child(body)


func _grid_point(i: int, j: int) -> Vector3:
	return Vector3(BOUNDS.position.x + i * CELL, _heights[j * _gw + i], BOUNDS.position.y + j * CELL)


func _sample_hash() -> Dictionary:
	var h := {}
	for s in _ground:
		var key := Vector2i(floori(s.x / 40.0), floori(s.z / 40.0))
		if not h.has(key):
			h[key] = []
		(h[key] as Array).append(s)
	return h


func _height_at(x: float, z: float, hash: Dictionary) -> float:
	var best := INF
	var best_s := Vector4(0, 0, 0, 4)
	var cx := floori(x / 40.0)
	var cz := floori(z / 40.0)
	for r: int in [1, 3, 8]:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var cell: Array = hash.get(Vector2i(cx + dx, cz + dz), [])
				for s: Vector4 in cell:
					var d := Vector2(s.x - x, s.z - z).length() - s.w
					if d < best:
						best = d
						best_s = s
		if best < r * 40.0:
			break
	var road_y := best_s.y - 0.35
	var hills := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 22.0
	var t := smoothstep(2.0, 55.0, best)
	var h := lerpf(road_y, road_y - 2.0 + hills, t)
	if best < 0.5:
		h = minf(h, road_y)
	for hole in _holes:
		var rect: Rect2 = hole.rect
		if rect.has_point(Vector2(x, z)):
			h = minf(h, float(hole.y))
		elif rect.grow(10.0).has_point(Vector2(x, z)):
			h = minf(h, lerpf(float(hole.y), h, clampf(_dist_out(rect, x, z) / 10.0, 0.0, 1.0)))
	return h


func _dist_out(r: Rect2, x: float, z: float) -> float:
	var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	return Vector2(dx, dz).length()


## Ground height of the built land (for placing trees).
func _land_height(x: float, z: float) -> float:
	var fi := clampf((x - BOUNDS.position.x) / CELL, 0.0, _gw - 1.001)
	var fj := clampf((z - BOUNDS.position.y) / CELL, 0.0, _gh - 1.001)
	var i := int(fi)
	var j := int(fj)
	var tx := fi - i
	var tz := fj - j
	var h00 := _heights[j * _gw + i]
	var h10 := _heights[j * _gw + i + 1]
	var h01 := _heights[(j + 1) * _gw + i]
	var h11 := _heights[(j + 1) * _gw + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


# --- sky ---------------------------------------------------------------------------------

func _build_atmosphere() -> void:
	var atmo := TrackAtmosphere.new()
	atmo.name = "Atmosphere"
	atmo.time_of_day = clampi(GameSettings.time_of_day, 0, 3)
	atmo.weather = clampi(GameSettings.weather, 0, 2)
	add_child(atmo)
	atmo.build(Vector2(0, -1), Vector2(120, -300))


# --- run: checkpoints, timer, respawn -----------------------------------------------------

func _through_gate(body: Node3D, index: int) -> void:
	if body != _car:
		return
	if index == 0:
		if running and next_cp == checkpoints.size():
			_finish()
		elif not running:
			running = true
			run_time = 0.0
			next_cp = 1
			splits.clear()
			_respawn = checkpoints[0]
			_say("GO!", Color(0.4, 1.0, 0.45), 1.2)
		return
	if not running or index != next_cp:
		return
	splits.append(run_time)
	_respawn = checkpoints[index]
	next_cp += 1
	var text := "CHECKPOINT %d / %d   %s" % [index, checkpoints.size() - 1, LapTimer.format_time(run_time)]
	var col := Color.WHITE
	if best_splits.size() >= index:
		var diff := run_time - best_splits[index - 1]
		text += "   %s%.2f" % ["+" if diff >= 0.0 else "-", absf(diff)]
		col = Color(1.0, 0.45, 0.4) if diff >= 0.0 else Color(0.4, 1.0, 0.45)
	_say(text, col, 2.2)


func _finish() -> void:
	running = false
	splits.append(run_time)
	var new_best := run_time < best_time
	if new_best:
		best_time = run_time
		best_splits = splits.duplicate()
		_save_best()
	_say("FINISH  %s%s" % [LapTimer.format_time(run_time), "   NEW BEST!" if new_best else ""],
			Color(1.0, 0.85, 0.3), 5.0)
	next_cp = 0


func _say(text: String, color: Color, seconds: float) -> void:
	message = text
	message_color = color
	message_left = seconds


## Back to the last checkpoint passed (or the start), standing still.
func respawn() -> void:
	if _car == null:
		return
	var xf := _respawn if running else _spawn
	_car.teleport(xf)
	# A fresh car: body repaired, wheels and tyres as new.
	if _car.damage:
		_car.damage.repair()
	for w in _car.wheels:
		w.new_tyres()
	_upside = 0.0
	_say("RESPAWN", Color(1.0, 0.8, 0.3), 1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _car == null or not is_instance_valid(_car):
		_car = null
		for node in get_tree().get_nodes_in_group("vehicles"):
			var v := node as Vehicle
			if v and v.input is PlayerInput:
				_car = v
				_respawn = _spawn
	if running:
		run_time += delta
	message_left = maxf(message_left - delta, 0.0)
	_move_things(delta)
	if _car:
		_loop_grip()
		# Fell off (into the ravine, off a cliff) or upside down too long.
		var ref_y := (_respawn if running else _spawn).origin.y
		if _car.global_position.y < ref_y - 20.0 or _car.global_position.y < -40.0:
			respawn()
		# Dropped into the lift shaft: out before the lift comes down on it.
		var in_shaft := _car.global_position - _lift.position
		if absf(in_shaft.x) < 5.0 and absf(in_shaft.z) < 5.5 and in_shaft.y < -1.0:
			respawn()
		_upside = _upside + delta if _car.global_basis.y.y < 0.2 and _car.linear_velocity.length() < 3.0 else 0.0
		if _upside > 2.5:
			respawn()
		var pi := _car.input as PlayerInput
		if pi and Input.is_action_just_pressed(pi.action_prefix + "recover"):
			respawn.call_deferred()
		if Input.is_action_just_pressed("restart"):
			running = false
			next_cp = 0
			_say("", Color.WHITE, 0.0)


func _move_things(delta: float) -> void:
	for p in _pendulums:
		var pivot: Node3D = p.pivot
		pivot.rotation.z = deg_to_rad(62.0) * sin(TAU * (_t / 4.2 + float(p.phase)))
		var ball: AnimatableBody3D = p.ball
		ball.global_position = pivot.position + pivot.basis * Vector3(0, -float(p.length), 0)
	for pl in _planks:
		var body: AnimatableBody3D = pl.body
		var i := int(pl.i)
		var base: Vector3 = pl.base
		var heave := 0.12 * sin(2.3 * _t + i * 0.45)
		var roll := 0.07 * sin(1.6 * _t + i * 0.3)
		body.transform = Transform3D(Basis(Vector3.RIGHT, roll), base + Vector3(0, heave, 0))
	if _lift:
		var top := float(_lift.get_meta(&"top"))
		var bottom := float(_lift.get_meta(&"bottom"))
		# 7 s at the top, 2.5 s down, 4 s at the bottom, 2.5 s up.
		var phase := lift_phase()
		var k := 0.0  # 0 = top, 1 = bottom
		if phase < 7.0:
			k = 0.0
		elif phase < 9.5:
			k = smoothstep(7.0, 9.5, phase)
		elif phase < 13.5:
			k = 1.0
		else:
			k = 1.0 - smoothstep(13.5, 16.0, phase)
		var p := _lift.position
		p.y = lerpf(top, bottom, k) - 0.3
		_lift.position = p
		# Boom: down from just before the lift leaves until it is back up.
		var closed := phase > 6.4 and phase < 15.9
		var bp := _boom.position
		if closed and _car:
			# Never down onto a car that is under it.
			var off := _car.global_position - bp
			if absf(off.x) < 7.0 and absf(off.z) < 3.4 and off.y > -6.0 and bp.y > top + 2.0:
				closed = false
		bp.y = move_toward(bp.y, top + (0.7 if closed else 4.0), 6.0 * delta)
		_boom.position = bp
	if _turntable:
		_turntable.rotate_y(0.45 * delta)
	for r in _rollers:
		r.rotate_y(-9.0 * delta)


## Where the lift is in its 16 s cycle (0..7 s: waiting at the top).
func lift_phase() -> float:
	return fmod(_t, 16.0)


## Inside the loop the track holds the car on (like magnets), so a car
## going fast enough doesn't drop off the top, and steers it along the
## loop's sideways drift so it comes out on the exit road.
func _loop_grip() -> void:
	if not _loop_box.has_point(_car.global_position):
		return
	var on := 0
	for w in _car.wheels:
		if w.grounded:
			on += 1
	if on < 2 or _car.linear_velocity.length() < 6.0:
		return
	# Pull towards the track only on the steep / upside-down part (at the
	# bottom the bend already presses the car down hard).
	var hold := clampf((0.5 - _car.global_basis.y.y) / 0.8, 0.0, 1.0)
	_car.apply_central_force(-_car.global_basis.y * _car.mass * 9.0 * hold)
	# Nearest point of the loop's line (by height and depth), and where it
	# sits sideways.
	var p := _car.global_position
	var best := INF
	var target_x := p.x
	for q in loop_line:
		var d := Vector2(q.y - p.y, q.z - p.z).length_squared()
		if d < best:
			best = d
			target_x = q.x
	var pull := (target_x - p.x) * 8.0 - _car.linear_velocity.x * 1.5
	_car.apply_central_force(Vector3(clampf(pull, -12.0, 12.0) * _car.mass, 0.0, 0.0))


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		best_time = float(cfg.get_value("best", "time", INF))
		best_splits = PackedFloat32Array(cfg.get_value("best", "splits", []))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "time", best_time)
	cfg.set_value("best", "splits", Array(best_splits))
	cfg.save(save_path)


# --- HUD ------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)
	var hud := CourseHud.new()
	hud.course = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)


class CourseHud extends Control:
	var course: ObstacleCourse

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var c := course
		var w := size.x
		var panel := Rect2(w * 0.5 - 230.0, 16.0, 460.0, 96.0)
		draw_rect(panel, Color(0.035, 0.04, 0.055, 0.82))
		draw_rect(Rect2(panel.position, Vector2(panel.size.x, 3.0)), MenuStyle.ACCENT)
		var time_text := LapTimer.format_time(c.run_time) if c.running else "--:--.---"
		_text(font, Vector2(w * 0.5, 62.0), time_text, 40, Color.WHITE)
		var cp_text := "CHECKPOINT %d / %d" % [maxi(c.next_cp - 1, 0), c.checkpoints.size() - 1] if c.running else "DRIVE THROUGH THE START"
		var best := "BEST " + (LapTimer.format_time(c.best_time) if c.best_time < INF else "--")
		_text(font, Vector2(w * 0.5, 96.0), cp_text + "     " + best, 18, MenuStyle.DIM)
		if c.message_left > 0.0 and c.message != "":
			var a := clampf(c.message_left / 0.4, 0.0, 1.0)
			_text(font, Vector2(w * 0.5, size.y * 0.28), c.message, 34, Color(c.message_color, a))
		_text(font, Vector2(w * 0.5, size.y - 22.0), "R / Y: back to the last checkpoint     Backspace / View: restart", 15, Color(1, 1, 1, 0.55))

	func _text(font: Font, centre: Vector2, s: String, font_size: int, color: Color) -> void:
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var p := Vector2(centre.x - tw * 0.5, centre.y)
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.8))
		draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- kit, materials, small helpers ------------------------------------------------------------

func _load_kit() -> void:
	var kit := (load(KIT) as PackedScene).instantiate()
	for mi in kit.find_children("*", "MeshInstance3D", true, false):
		_kit[String(mi.name)] = (mi as MeshInstance3D).mesh
	kit.free()


func _add(kind: String, xf: Transform3D) -> void:
	if not _kit.has(kind):
		return
	if not _batches.has(kind):
		_batches[kind] = []
	(_batches[kind] as Array).append(xf)


func _flush_kit() -> void:
	for kind: String in _batches:
		var list: Array = _batches[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _kit[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit_" + kind
		mmi.multimesh = mm
		add_child(mmi)


## Collision shaped like a kit piece.
func _solid(kind: String, xf: Transform3D) -> void:
	if not _kit.has(kind):
		return
	var cs := CollisionShape3D.new()
	cs.shape = (_kit[kind] as Mesh).create_trimesh_shape()
	cs.transform = xf
	var body := get_node_or_null("Buildings") as StaticBody3D
	if body == null:
		body = _static("Buildings")
		body.name = "Buildings"
	body.add_child(cs)


func _static(node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body, true)
	return body


func _box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _paint(size: Vector3, xf: Transform3D, color: Color, glow: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := _mat(color)
	if glow > 0.0:
		m = m.duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	_mats[key] = m
	return m
