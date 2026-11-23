extends SceneTree
## Looks for solid things where you can drive: walks every track every 3 m,
## across the road and the run-off out to just short of the barriers (and
## along the pit lane), and asks the physics what is there at bumper and
## roof height. The ground (road, grass, kerbs, terrain) doesn't count.
## Prints each hit grouped by the body it belongs to. Barriers, pit walls and
## the start gantry's legs are meant to be there (and visible); anything
## else (buildings, stands, invisible boxes) fails the check.
const EXPECTED := ["Barriers", "PitWall", "TrackProp"]
##   Godot_console.exe --headless --fixed-fps 120 --path . -s res://tests/obstacle_check.gd -- [--tracks=spa,silverstone]

var _ok := true


func _init() -> void:
	GameSettings.use_defaults()
	_run.call_deferred()


func _run() -> void:
	var tracks := PackedStringArray()
	for t in TrackList.TRACKS:
		tracks.append(t.id)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tracks="):
			tracks = arg.get_slice("=", 1).split(",")
	for id in tracks:
		await _check_track(id)
	print("obstacle_check %s" % ("PASSED" if _ok else "FAILED"))
	quit()


func _check_track(id: String) -> void:
	GameSettings.track = id
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	var car := scene.get_node("Vehicle") as Vehicle
	var player := car.get_node("PlayerInput")
	car.remove_child(player)
	player.free()
	root.add_child(scene)
	current_scene = scene
	for i in 10:
		await physics_frame
	car.global_position = Vector3(0, -500, 0)  # out of the way
	await physics_frame
	var circuit := scene.find_children("*", "Circuit", true, false)[0] as Circuit
	var dressing := circuit.get_node("Dressing")
	var space := car.get_world_3d().direct_space_state
	var hits := {}  # body name -> [count, first offset, first lateral, height]
	var samples: Array = circuit._samples
	var n := samples.size()
	var off := 0.0
	while off < circuit.length:
		var i := int(off / circuit.length * n) % n
		var c := circuit.point_at(off)
		var right := circuit.right_at(off)
		var left_edge := -float(dressing._barrier_dist[0][i]) + 1.0
		var right_edge := float(dressing._barrier_dist[1][i]) - 1.0
		var lat := left_edge
		var lats: Array[float] = []
		while lat <= right_edge:
			lats.append(lat)
			lat += 1.5
		var pl := circuit.pit_lateral(off)
		if absf(pl) > 0.5:
			for d in [-3.0, 0.0, 3.0]:
				lats.append(pl + d)
		for l: float in lats:
			var p := c + right * l
			var ground := circuit.surface_height(p.x, p.z)
			for h in [0.6, 1.5]:
				var q := PhysicsPointQueryParameters3D.new()
				q.position = Vector3(p.x, ground + h, p.z)
				q.collide_with_areas = false
				for r in space.intersect_point(q, 8):
					var body := r.collider as Node
					if body == null or body is Vehicle or body.has_meta(&"surface_grip"):
						continue
					var part := ""
					if body is CollisionObject3D:
						var owner_id := (body as CollisionObject3D).shape_find_owner(int(r.shape))
						var cs := (body as CollisionObject3D).shape_owner_get_owner(owner_id) as Node
						if cs:
							part = " / " + String(cs.name)
					var key := "%s (%s)%s" % [body.name, body.get_parent().name, part]
					if not hits.has(key):
						hits[key] = [0, off, l, h]
					hits[key][0] = int(hits[key][0]) + 1
		off += 3.0
	var bad := 0
	for key: String in hits:
		var expected := false
		for e: String in EXPECTED:
			expected = expected or key.begins_with(e)
		if expected:
			continue
		var hit: Array = hits[key]
		print("    %-40s %4d points, first at %.0f m, lateral %+.1f, height %.1f" % [key, hit[0], hit[1], hit[2], hit[3]])
		bad += 1
		_ok = false
	print("%s: %d unexpected obstacles on drivable ground" % [id, bad])
	scene.queue_free()
	current_scene = null
	for i in 3:
		await physics_frame
