extends SceneTree
## Off-road check for every circuit:
## - road surface: no lips / bumps across the road (two stretches overlapping)
## - road edge: no step up or big drop just off the road
## - barriers: no piece floating above or buried in the ground
## - nothing solid standing on the road
## - lists the sharp turns (radius under 45 m) with where they are on the lap
##   Godot_console.exe --headless --path . -s res://tests/trackside_check.gd [-- --track=spa]

var _ok := true
var _last_hit := ""


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var ids := TrackList.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			ids = PackedStringArray([arg.get_slice("=", 1)])
	for id in ids:
		GameSettings.track = id
		var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
		var car := scene.get_node("Vehicle") as Vehicle
		car.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(scene)
		for i in 3:
			await physics_frame
		car.global_position += Vector3.UP * 500.0  # out of the way of the rays
		await physics_frame
		_check_track(scene.get_node("Circuit") as Circuit)
		scene.queue_free()
		await process_frame
	print("trackside_check %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _check_track(c: Circuit) -> void:
	var space := root.world_3d.direct_space_state
	var dressing := c.get_node("Dressing")
	var barrier_body: StaticBody3D = dressing._barrier_body
	var half := c.road_width * 0.5
	var lips: PackedStringArray = []
	var steps: PackedStringArray = []
	for smp: Dictionary in c._samples:
		var pos := c.to_global(smp.pos)
		var right: Vector3 = smp.right
		var at := "%.0f%%" % (smp.off / c.length * 100.0)
		# Across the road.
		var lat := -half + 0.6  # off the strip seams (rays can slip through an edge)
		while lat <= half - 0.5:
			var q := pos + right * lat
			var want := c.surface_y(q.x, q.z, smp.pos.y) + Circuit.ROAD_Y
			var y := _ground(space, q, [barrier_body.get_rid()])
			if absf(y - want) > 0.08:
				lips.append("%s %+.0fm %+.2f" % [at, lat, y - want])
			lat += 1.5
		# Just off the road, both sides (over the water on a causeway: nothing there).
		for side: float in ([] if smp.bridge else [-1.0, 1.0]):
			var edge := pos + right * side * half
			var road_y := c.surface_y(edge.x, edge.z, smp.pos.y) + Circuit.ROAD_Y
			for out: float in [0.8, 3.0]:
				var q := pos + right * side * (half + out)
				if c.distance_from_centre(q) < half + out - 1.0:
					continue  # nearer another stretch of road
				var g := _ground(space, q, [barrier_body.get_rid()]) - road_y
				if g > 0.1 or g < -0.35 * out - 0.1:
					steps.append("%s %s %.1fm %+.2f (%s)" % [at, "R" if side > 0 else "L", out, g, _last_hit])
	# Barrier pieces vs the ground under their ends.
	var floating: PackedStringArray = []
	var on_road: PackedStringArray = []
	for cs: Node in barrier_body.get_children():
		var shape_node := cs as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var xf := shape_node.global_transform
		var size := (shape_node.shape as BoxShape3D).size
		var at := "%.0f%%" % (c.progress_at(xf.origin) / c.length * 100.0)
		var near := c.nearest_sample(c.to_local(xf.origin).x, c.to_local(xf.origin).z)
		if near >= 0 and c._samples[near].bridge:
			continue  # causeway railings stand on the deck edge
		if c.distance_from_centre(xf.origin) < half + 0.3:
			on_road.append(at)
		for end: float in [-0.45, 0.0, 0.45]:
			var p := xf * Vector3(size.x * end, -size.y * 0.5, 0.0)
			var g := _ground(space, p, [barrier_body.get_rid()])
			var gap := p.y - g
			if gap > 0.3 or gap < -0.6:
				floating.append("%s %+.2f (%s at %s, land %.2f, surface %.2f, %.1f m from centre)" % [at, gap, _last_hit,
						p.snapped(Vector3.ONE * 0.1), c.ground_height(p.x, p.z), c.surface_height(p.x, p.z), c.distance_from_centre(p)])
				break
	# Sharp turns.
	var turns: PackedStringArray = []
	var in_turn := false
	var tightest := 0.0
	var start := 0.0
	for smp: Dictionary in c._samples:
		var k := absf(float(smp.curv))
		if k > 1.0 / 45.0:
			if not in_turn:
				start = smp.off
				tightest = 0.0
			in_turn = true
			tightest = maxf(tightest, k)
		elif in_turn:
			in_turn = false
			turns.append("%.1f%% (r %.0f m)" % [start / c.length * 100.0, 1.0 / tightest])
	print("== %s" % c.track_name)
	_report("road surface lips", lips)
	_report("steps at the road edge", steps)
	_report("barrier pieces floating / buried", floating)
	_report("solid things on the road", on_road)
	print("  sharp turns: %s" % ", ".join(turns))


func _report(what: String, list: PackedStringArray) -> void:
	if list.is_empty():
		print("  [ok] no %s" % what)
		return
	_ok = false
	var shown := list.slice(0, 12)
	print("  [FAIL] %d %s: %s%s" % [list.size(), what, ", ".join(shown), " ..." if list.size() > 12 else ""])


## Height of the first thing below `p` (skipping `exclude`), or -99. Three
## rays a few cm apart, highest wins (one can slip through a seam).
func _ground(space: PhysicsDirectSpaceState3D, p: Vector3, exclude: Array) -> float:
	var best := -99.0
	var hit_name := "nothing"
	for o: Vector3 in [Vector3.ZERO, Vector3(0.07, 0, 0.03), Vector3(-0.03, 0, 0.07)]:
		var y := _ray(space, p + o, exclude)
		if y > best:
			best = y
			hit_name = _last_hit
	_last_hit = hit_name
	return best


func _ray(space: PhysicsDirectSpaceState3D, p: Vector3, exclude: Array) -> float:
	var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p - Vector3.UP * 12.0)
	var rids: Array[RID] = []
	for r in exclude:
		rids.append(r)
	ray.exclude = rids
	var hit := space.intersect_ray(ray)
	_last_hit = String((hit.collider as Node).name) if hit else "nothing"
	return hit.position.y if hit else -99.0
