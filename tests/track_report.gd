extends SceneTree
## Prints the circuit length and its tightest corners (radius in metres).
## Run: Godot_console.exe --headless --path . -s res://tests/track_report.gd
func _init() -> void:
	var c: Circuit = load("res://scenes/tracks/circuit.tscn").instantiate()
	root.add_child(c)
	await process_frame
	print("length %.0f m" % c.length)
	var corners := []
	var off := 0.0
	while off < c.length:
		var r := 1.0 / maxf(absf(c.curvature_at(off)), 1e-5)
		corners.append([r, off])
		off += 4.0
	corners.sort_custom(func(a, b): return a[0] < b[0])
	var shown := []
	for e in corners:
		var near := false
		for s in shown:
			if absf(s - e[1]) < 60.0:
				near = true
		if near:
			continue
		shown.append(e[1])
		print("  R %4.0f m at %5.0f m  %s" % [e[0], e[1], str(c.point_at(e[1]).snapped(Vector3.ONE))])
		if shown.size() >= 12:
			break
	quit()
