extends SceneTree
## Invisible hitboxes: every collision shape is compared with what is drawn.
## Points are sampled inside each collider; a point counts as "visible" if
## rays in all six directions hit drawn geometry (it sits inside / under
## something you can see). A collider whose points are mostly not covered
## is solid space with nothing drawn there.
## - Tracks: barriers, pit walls, gantries and the kit's solid pieces
##   (stands, buildings, billboards, marshal posts...).
## - Cars: the collision hull round each car model (antennas, mirrors and
##   spoilers can stretch a convex hull far past the body).
## Run WINDOWED (headless keeps no multimesh positions, so the batched kit
## pieces would all seem to sit at the origin), e.g. off screen with an
## override.cfg containing window/size/no_focus=true:
##   Godot_console.exe --path . --position -2500,0 -s res://tests/hitbox_check.gd -- [--tracks=a,b] [--cars=a,b] [--skip-tracks] [--skip-cars]

const PROBE_LAYER := 1 << 19
const LIMIT_TRACK := 0.35   ## a collider with more than this share uncovered fails
const LIMIT_CAR := 0.12

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	GameSettings.damage = 0
	_run.call_deferred()


func _run() -> void:
	var tracks := PackedStringArray()
	for t in TrackList.TRACKS:
		tracks.append(t.id)
	var cars := CarRoster.ids()
	var do_tracks := true
	var do_cars := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tracks="):
			tracks = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--cars="):
			cars = arg.get_slice("=", 1).split(",")
		elif arg == "--skip-tracks":
			do_tracks = false
		elif arg == "--skip-cars":
			do_cars = false
	if do_tracks:
		for id in tracks:
			await _check_track(id)
	if do_cars:
		await _check_cars(cars)
	print("hitbox_check %s" % ("PASSED" if _ok else "FAILED"))
	quit()


# --- tracks ----------------------------------------------------------------------

func _check_track(id: String) -> void:
	GameSettings.track = id
	var scene := await _load_practice()
	var car := scene.get_node("Vehicle") as Vehicle
	car.global_position = Vector3(0, -800, 0)
	car.freeze = true
	await _frames(3)
	var probe := _visual_probe(scene, [car])
	await _frames(2)
	var space := car.get_world_3d().direct_space_state
	var groups := {}  # body / shape name -> [samples, uncovered, worst position]
	for body in scene.find_children("*", "StaticBody3D", true, false):
		var sb := body as StaticBody3D
		if sb == probe or sb.has_meta(&"surface_grip"):
			continue
		for cs in sb.find_children("*", "CollisionShape3D", false, false):
			var shape := (cs as CollisionShape3D).shape
			if shape is ConcavePolygonShape3D or shape is HeightMapShape3D:
				continue  # trimesh solids are the drawn mesh itself
			var size := Vector3.ZERO
			var local := AABB()
			if shape is BoxShape3D:
				size = (shape as BoxShape3D).size
				local = AABB(-size * 0.5, size)
			elif shape is ConvexPolygonShape3D:
				var cpts := (shape as ConvexPolygonShape3D).points
				local = AABB(cpts[0], Vector3.ZERO)
				for q in cpts:
					local = local.expand(q)
				size = local.size
			else:
				continue
			if size.y >= 30.0 or size.x > 400.0 or size.z > 400.0:
				continue  # the invisible walls at the edge of the map
			var xf := (cs as CollisionShape3D).global_transform
			var key := "%s / %s" % [sb.name, _kind_near(scene, xf.origin)]
			if not groups.has(key):
				groups[key] = [0, 0, Vector3.ZERO, 0]
			var g: Array = groups[key]
			g[3] = int(g[3]) + 1
			for p in _box_points(local, xf):
				if not shape is BoxShape3D and not _inside_body(space, p, sb):
					continue
				g[0] = int(g[0]) + 1
				if not _covered(space, p, size.length() + 1.0):
					g[1] = int(g[1]) + 1
					g[2] = p
	print("%s:" % id)
	for key: String in groups:
		var g: Array = groups[key]
		var share := float(g[1]) / maxf(float(g[0]), 1.0)
		# The armco rail is open (posts with a rail on top): its hull spans the
		# gaps between the posts, so a lot of it is "not drawn" by design.
		var bad := share > LIMIT_TRACK and not key.ends_with("armco")
		print("    [%s] %-36s %4d shapes, %3.0f%% of their volume not drawn%s" % ["FAIL" if bad else "ok", key, g[3],
				share * 100.0, ("  (e.g. at %s)" % str((g[2] as Vector3).round())) if bad else ""])
		if bad:
			_ok = false
	scene.queue_free()
	current_scene = null
	await _frames(3)


## Which drawn thing is nearest a collider (for the report).
func _kind_near(scene: Node, at: Vector3) -> String:
	var best := "?"
	var best_d := 6.0
	for mmi in scene.find_children("Kit_*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var d := ((mmi as Node3D).global_transform * mm.get_instance_transform(i)).origin.distance_to(at)
			if d < best_d:
				best_d = d
				best = String(mmi.name).trim_prefix("Kit_")
	return best


func _box_points(local: AABB, xf: Transform3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for ix in 4:
		for iy in 4:
			for iz in 4:
				var f := Vector3((ix + 0.5) / 4.0, (iy + 0.5) / 4.0, (iz + 0.5) / 4.0) - Vector3(0.5, 0.5, 0.5)
				out.append(xf * (local.get_center() + f * local.size * 0.9))
	return out


func _inside_body(space: PhysicsDirectSpaceState3D, p: Vector3, body: CollisionObject3D) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = body.collision_layer
	for r in space.intersect_point(q, 8):
		if r.collider == body:
			return true
	return false


# --- cars --------------------------------------------------------------------------

## Cars: rays come in from all round (sides, ends, corners, from above) and
## stop at the collision shape and at the drawn car. The gap between the two
## is invisible padding another car would hit first. The old single hull
## round the whole car is measured the same way for comparison.
const OLD_HULL_LAYER := 1 << 18
const GAP := 0.1

func _check_cars(cars: PackedStringArray) -> void:
	print("cars:  (share of rays where the hitbox sticks out 10-60 cm past the drawn car, worst such gap)")
	for id in cars:
		GameSettings.p1_car = id
		GameSettings.track = "monza"
		var scene := await _load_practice()
		var car := scene.get_node("Vehicle") as Vehicle
		car.freeze = true
		car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 300, 0))
		await _frames(3)
		_visual_probe(car, [], true, scene)
		var old := _old_hull_body(car, scene)
		await _frames(3)
		var space := car.get_world_3d().direct_space_state
		_dbg.clear()
		_dbg_all.clear()
		var now := _gaps(space, car, car.collision_layer)
		if OS.get_environment("GAP_DEBUG") != "":
			var keys := _dbg_all.keys()
			keys.sort()
			for k: String in keys:
				print("      %-18s %d / %d" % [k, int(_dbg.get(k, 0)), int(_dbg_all[k])])
		var before := _gaps(space, car, OLD_HULL_LAYER)
		var bad := now.x > 0.15
		print("    [%s] %-10s now %3.0f%% (worst %.2f m)   one-piece hull %3.0f%% (worst %.2f m)" % [
				"FAIL" if bad else "ok", id, now.x * 100.0, now.y, before.x * 100.0, before.y])
		if bad:
			_ok = false
		old.queue_free()
		scene.queue_free()
		current_scene = null
		await _frames(3)


var _dbg := {}
var _dbg_all := {}

## (share of rays with a gap over GAP, worst gap) for collision `mask`.
func _gaps(space: PhysicsDirectSpaceState3D, car: Vehicle, mask: int) -> Vector2:
	var c := car.global_position
	var rays := 0
	var over := 0
	var worst := 0.0
	var starts: Array = []
	# Horizontal rays at several heights, all round.
	for h in [0.45, 0.65, 0.85, 1.05, 1.25]:
		for k in 48:
			var ang := TAU * k / 48.0
			var d := Vector3(sin(ang), 0.0, cos(ang))
			starts.append([c + Vector3.UP * h + d * 6.0, -d, "h%.2f %s" % [h, ["front", "side", "rear", "side"][int(round(ang / (PI * 0.5))) % 4]]])
	# Rays from above on a grid.
	for x in range(-9, 10):
		for z in range(-26, 27, 2):
			starts.append([c + Vector3(x * 0.1, 4.0, z * 0.1), Vector3.DOWN, "top"])
	for st: Array in starts:
		var from: Vector3 = st[0]
		var dir: Vector3 = st[1]
		var to := from + dir * 12.0
		var qa := PhysicsRayQueryParameters3D.create(from, to, mask)
		var hit_col := space.intersect_ray(qa)
		if hit_col.is_empty():
			continue
		var qb := PhysicsRayQueryParameters3D.create(from, to, PROBE_LAYER)
		var hit_vis := space.intersect_ray(qb)
		var col_d := from.distance_to(hit_col.position)
		var vis_d := from.distance_to(hit_vis.position) if not hit_vis.is_empty() else 12.0
		var gap := vis_d - col_d
		if gap > 0.6:
			continue  # slipped through a seam of the drawn model to its far side
		rays += 1
		if gap > GAP:
			over += 1
			if OS.get_environment("GAP_DEBUG") != "":
				_dbg[st[2]] = int(_dbg.get(st[2], 0)) + 1
		if OS.get_environment("GAP_DEBUG") != "":
			_dbg_all[st[2]] = int(_dbg_all.get(st[2], 0)) + 1
		worst = maxf(worst, gap)
	return Vector2(float(over) / maxf(rays, 1), worst)


## The previous collision: one convex hull round the whole body mesh.
func _old_hull_body(car: Vehicle, parent: Node) -> StaticBody3D:
	var body_mesh := car.get_node("Model").find_child("body*", true, false) as MeshInstance3D
	var to_car := car.global_transform.affine_inverse() * body_mesh.global_transform
	var pts := PackedVector3Array()
	var seen := {}
	for sidx in body_mesh.mesh.get_surface_count():
		for v: Vector3 in body_mesh.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX]:
			var p := to_car * v
			p.y = maxf(p.y, 0.32)
			var cell := Vector3i((p / 0.08).round())
			if not seen.has(cell):
				seen[cell] = true
				pts.append(p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var sb := StaticBody3D.new()
	sb.collision_layer = OLD_HULL_LAYER
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = car.global_transform
	return sb


func _inside(space: PhysicsDirectSpaceState3D, p: Vector3, car: Vehicle) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = car.collision_layer
	for r in space.intersect_point(q, 4):
		if r.collider == car:
			return true
	return false


# --- shared ------------------------------------------------------------------------

## A static body on its own layer with every drawn triangle of `root` (big
## ground meshes and the crowds left out).
func _visual_probe(root: Node, skip: Array, include_all: bool = false, parent: Node = null) -> StaticBody3D:
	var faces := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or _under(m, skip):
			continue
		var gx := m.global_transform
		var ab := gx * m.get_aabb()
		# Leave out only the land itself (huge); long things like the pit wall
		# and the road stay in.
		if not include_all and (String(m.name).begins_with("Terrain") or maxf(ab.size.x, ab.size.z) > 2500.0):
			continue
		for v in m.mesh.get_faces():
			faces.append(gx * v)
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or String(mmi.name).contains("spectator"):
			continue
		var base := mm.mesh.get_faces()
		for i in mm.instance_count:
			var gx := (mmi as Node3D).global_transform * mm.get_instance_transform(i)
			for v in base:
				faces.append(gx * v)
	var body := StaticBody3D.new()
	body.name = "VisualProbe"
	body.collision_layer = PROBE_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# Faces are in world space: the probe must sit at the origin, not on a car.
	(parent if parent else root).add_child(body)
	body.global_transform = Transform3D.IDENTITY
	return body


func _under(n: Node, skip: Array) -> bool:
	for s in skip:
		if s == n or (s as Node).is_ancestor_of(n):
			return true
	return false


## True if drawn geometry is found in all six directions from `p` (within `reach`).
func _covered(space: PhysicsDirectSpaceState3D, p: Vector3, reach: float) -> bool:
	for d: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(p, p + d * reach, PROBE_LAYER)
		q.hit_back_faces = true
		q.hit_from_inside = true
		if space.intersect_ray(q).is_empty():
			return false
	return true


func _load_practice() -> Node:
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	root.add_child(scene)
	current_scene = scene
	await _frames(12)
	return scene


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
