class_name TrackTerrain
extends Node3D
## The land around a circuit: level with the road near the track (run-off,
## barriers, stands; it climbs and dips with the track), rising into rolling hills ("hills") or big rocky peaks ("mountains")
## further out, with tiny low-poly villages / chalets far away.
## height_at(x, z) lets scenery sit on the ground.

const LAYER_WORLD := 1
const CELL := 16.0

var theme: String = "hills"
var extent: float = 1100.0

var _origin := Vector2.ZERO  ## world x, z of grid vertex (0, 0)
var _w := 0
var _h := 0
var _heights := PackedFloat32Array()
var _dist := PackedFloat32Array()
var _base := PackedFloat32Array()  ## road height of the nearest bit of track
var _rng := RandomNumberGenerator.new()


func build(circuit: Circuit) -> void:
	_rng.seed = circuit.random_seed * 31 + 5
	extent = 1300.0 if theme == "mountains" else 1100.0
	var rect: Rect2 = circuit._bounds.grow(extent)
	_origin = rect.position
	_w = int(ceil(rect.size.x / CELL)) + 1
	_h = int(ceil(rect.size.y / CELL)) + 1
	_distance_field(circuit)
	_heightfield(circuit)
	_build_mesh()
	_build_collision()
	_build_villages()


## Height of the ground at a world position (about the road's height near the track).
func height_at(x: float, z: float) -> float:
	var gx := clampf((x - _origin.x) / CELL, 0.0, _w - 1.001)
	var gz := clampf((z - _origin.y) / CELL, 0.0, _h - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var a := lerpf(_heights[iz * _w + ix], _heights[iz * _w + ix + 1], fx)
	var b := lerpf(_heights[(iz + 1) * _w + ix], _heights[(iz + 1) * _w + ix + 1], fx)
	return lerpf(a, b, fz)


## Distance from every grid point to the track centre line: exact near the
## track, then spread outwards with a two-pass chamfer transform.
func _distance_field(circuit: Circuit) -> void:
	_dist.resize(_w * _h)
	_dist.fill(1e9)
	_base.resize(_w * _h)
	_base.fill(0.0)
	for s: Dictionary in circuit._samples:
		var p: Vector3 = circuit.to_global(s.pos)
		var cx := int(round((p.x - _origin.x) / CELL))
		var cz := int(round((p.z - _origin.y) / CELL))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var x := cx + dx
				var z := cz + dz
				if x < 0 or z < 0 or x >= _w or z >= _h:
					continue
				var d := Vector2(_origin.x + x * CELL - p.x, _origin.y + z * CELL - p.z).length()
				var i := z * _w + x
				if d < _dist[i]:
					_dist[i] = d
					_base[i] = p.y
	var diag := CELL * 1.4142
	for z in _h:
		for x in _w:
			var i := z * _w + x
			if x > 0: _relax(i, i - 1, CELL)
			if z > 0:
				_relax(i, i - _w, CELL)
				if x > 0: _relax(i, i - _w - 1, diag)
				if x < _w - 1: _relax(i, i - _w + 1, diag)
	for z in range(_h - 1, -1, -1):
		for x in range(_w - 1, -1, -1):
			var i := z * _w + x
			if x < _w - 1: _relax(i, i + 1, CELL)
			if z < _h - 1:
				_relax(i, i + _w, CELL)
				if x < _w - 1: _relax(i, i + _w + 1, diag)
				if x > 0: _relax(i, i + _w - 1, diag)
	_smooth_base()


## Distance-field step: take the neighbour's track if it is nearer (and its height).
func _relax(i: int, j: int, step: float) -> void:
	if _dist[j] + step < _dist[i]:
		_dist[i] = _dist[j] + step
		_base[i] = _base[j]


## Away from the track the base height is blurred, so where two stretches of
## track at different heights meet there is a gentle slope, not a step.
func _smooth_base() -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(_base.size())
	for pass_i in 8:
		for z in _h:
			for x in _w:
				var i := z * _w + x
				var sum := 0.0
				var cnt := 0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var xx := x + dx
						var zz := z + dz
						if xx >= 0 and zz >= 0 and xx < _w and zz < _h:
							sum += _base[zz * _w + xx]
							cnt += 1
				var keep := 1.0 - smoothstep(30.0, 140.0, _dist[i])
				tmp[i] = lerpf(sum / cnt, _base[i], keep)
		var swap := _base
		_base = tmp
		tmp = swap


func _heightfield(circuit: Circuit) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = circuit.random_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.seed = circuit.random_seed + 9
	detail.frequency = 0.02
	if theme == "mountains":
		noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		noise.frequency = 0.0022
	else:
		noise.frequency = 0.003
	_heights.resize(_w * _h)
	for z in _h:
		for x in _w:
			var i := z * _w + x
			var wx := _origin.x + x * CELL
			var wz := _origin.y + z * CELL
			var d := _dist[i]
			var n := noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			var h := 0.0
			if theme == "mountains":
				h = n * (smoothstep(70.0, 320.0, d) * 110.0 + smoothstep(320.0, 1250.0, d) * 300.0)
				h += detail.get_noise_2d(wx, wz) * 6.0 * smoothstep(70.0, 200.0, d)
			else:
				h = n * (smoothstep(85.0, 380.0, d) * 70.0 + smoothstep(450.0, 1050.0, d) * 140.0)
				h += detail.get_noise_2d(wx, wz) * 2.5 * smoothstep(80.0, 200.0, d)
			# A few cm under the road next to it (like the old flat ground).
			var sink := 0.06 * (1.0 - smoothstep(40.0, 70.0, d))
			_heights[i] = _base[i] + maxf(h, 0.0) - sink
	_clear_road(circuit)


## The 16 m grid can bulge above the road in a dip: wherever the ground
## would come up through the road or curbs, lower just those grid points.
## A little further out (where cars cut corners) the grass may not be higher
## than the road beside it either.
func _clear_road(circuit: Circuit) -> void:
	var road := circuit.road_width * 0.5 + circuit.curb_width + 1.0
	var reach := 14.0
	for pass_i in 3:
		var changed := false
		for smp: Dictionary in circuit._samples:
			var c: Vector3 = circuit.to_global(smp.pos)
			var right: Vector3 = smp.right
			var lat := -reach
			while lat <= reach + 0.01:
				var q := c + right * lat
				var lq := circuit.to_local(q)
				var surf := circuit.surface_y(lq.x, lq.z, smp.pos.y)
				var limit := surf + circuit.global_position.y + Circuit.ROAD_Y - (0.08 if absf(lat) <= road else 0.0)
				var over := height_at(q.x, q.z) - limit
				if over > 0.0:
					var ix := clampi(int((q.x - _origin.x) / CELL), 0, _w - 2)
					var iz := clampi(int((q.z - _origin.y) / CELL), 0, _h - 2)
					for k: int in [iz * _w + ix, iz * _w + ix + 1, (iz + 1) * _w + ix, (iz + 1) * _w + ix + 1]:
						_heights[k] -= over
					changed = true
				lat += 2.0
		if not changed:
			break


func _ground_color(h: float, slope: float, wx: float, wz: float) -> Color:
	var v := sin(wx * 0.013) * cos(wz * 0.011) * 0.5 + 0.5
	if theme == "mountains":
		var grass := Color(0.26, 0.42, 0.2).lerp(Color(0.33, 0.45, 0.22), v)
		var rock := Color(0.42, 0.4, 0.38).lerp(Color(0.5, 0.46, 0.4), v)
		var c := grass.lerp(rock, clampf(smoothstep(0.35, 0.75, slope) + smoothstep(120.0, 190.0, h), 0.0, 1.0))
		return c.lerp(Color(0.93, 0.94, 0.97), smoothstep(215.0, 245.0, h + v * 25.0) * (1.0 - smoothstep(0.9, 1.2, slope)))
	var c2 := Color(0.3, 0.5, 0.22).lerp(Color(0.36, 0.52, 0.22), v)
	c2 = c2.lerp(Color(0.46, 0.5, 0.26), smoothstep(40.0, 110.0, h) * 0.6)
	return c2.lerp(Color(0.4, 0.42, 0.32), smoothstep(0.45, 0.9, slope) * 0.6)


func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(_w * _h)
	normals.resize(_w * _h)
	colors.resize(_w * _h)
	uvs.resize(_w * _h)
	for z in _h:
		for x in _w:
			var i := z * _w + x
			var wx := _origin.x + x * CELL
			var wz := _origin.y + z * CELL
			var hl := _heights[z * _w + maxi(x - 1, 0)]
			var hr := _heights[z * _w + mini(x + 1, _w - 1)]
			var hd := _heights[maxi(z - 1, 0) * _w + x]
			var hu := _heights[mini(z + 1, _h - 1) * _w + x]
			var n := Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			var slope := sqrt(1.0 - n.y * n.y) / maxf(n.y, 0.05)
			verts[i] = Vector3(wx, _heights[i], wz)
			normals[i] = n
			colors[i] = _ground_color(_heights[i] - _base[i], slope, wx, wz)
			uvs[i] = Vector2(wx, wz) * 0.08
	var indices := PackedInt32Array()
	for z in _h - 1:
		for x in _w - 1:
			var i := z * _w + x
			indices.append_array([i, i + 1, i + _w, i + 1, i + _w + 1, i + _w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _detail_texture()
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _detail_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in 64:
		for x in 64:
			var v := rng.randf_range(0.82, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface_grip", 0.55)
	body.set_meta(&"surface_drag", 0.05)
	var shape := HeightMapShape3D.new()
	shape.map_width = _w
	shape.map_depth = _h
	shape.map_data = _heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)
	cs.position = Vector3(_origin.x + (_w - 1) * CELL * 0.5, 0.0, _origin.y + (_h - 1) * CELL * 0.5)
	body.add_child(cs)
	add_child(body)


# --- far-away villages -------------------------------------------------------------

func _build_villages() -> void:
	var house := _house_mesh(theme == "mountains")
	var xforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var towers: Array[Transform3D] = []
	var wanted := 7 if theme == "mountains" else 11
	var placed: Array[Vector3] = []
	for attempt in 600:
		if placed.size() >= wanted:
			break
		var gx := _rng.randi_range(2, _w - 3)
		var gz := _rng.randi_range(2, _h - 3)
		var d := _dist[gz * _w + gx]
		if d < 320.0 or d > extent - 150.0:
			continue
		var wx := _origin.x + gx * CELL
		var wz := _origin.y + gz * CELL
		var h := height_at(wx, wz)
		if absf(height_at(wx + 40.0, wz) - h) > 9.0 or absf(height_at(wx, wz + 40.0) - h) > 9.0:
			continue  # too steep for a village
		if theme == "mountains" and h > 170.0:
			continue
		var centre := Vector3(wx, h, wz)
		var crowded := false
		for p in placed:
			if p.distance_to(centre) < 260.0:
				crowded = true
		if crowded:
			continue
		placed.append(centre)
		var count := _rng.randi_range(5, 12)
		for k in count:
			var off := Vector2(_rng.randf_range(-55.0, 55.0), _rng.randf_range(-55.0, 55.0))
			var px := wx + off.x
			var pz := wz + off.y
			var s := _rng.randf_range(0.8, 1.3)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.25), s))
			xforms.append(Transform3D(b, Vector3(px, height_at(px, pz) - 0.3, pz)))
			tints.append(Color.WHITE.lerp(Color(0.85, 0.8, 0.7), _rng.randf()))
		if theme == "hills" and _rng.randf() < 0.6:
			towers.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 1.0)), centre + Vector3(0, -0.3, 0)))
	_multimesh("Villages", house, xforms, tints)
	if not towers.is_empty():
		var tower_tints: Array[Color] = []
		tower_tints.resize(towers.size())
		tower_tints.fill(Color.WHITE)
		_multimesh("ChurchTowers", _tower_mesh(), towers, tower_tints)


func _multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], tints: Array[Color]) -> void:
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A box house with a pitched roof, ~16 triangles. Chalets: dark wood, steep roof.
func _house_mesh(chalet: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.45, 0.32, 0.22) if chalet else Color(0.92, 0.88, 0.8)
	var roof := Color(0.3, 0.3, 0.33) if chalet else Color(0.68, 0.26, 0.18)
	var w := 3.5
	var d := 4.5
	var wh := 4.0
	var rh := 4.0 if chalet else 2.6
	var c := [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, 0, d), Vector3(-w, 0, d)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		_quad(st, a, b, b + Vector3(0, wh, 0), a + Vector3(0, wh, 0), wall)
	var r0 := Vector3(0, wh + rh, -d - 0.4)
	var r1 := Vector3(0, wh + rh, d + 0.4)
	var e := 0.6
	_quad(st, Vector3(-w - e, wh - 0.3, -d - 0.4), r0, r1, Vector3(-w - e, wh - 0.3, d + 0.4), roof)
	_quad(st, r0, Vector3(w + e, wh - 0.3, -d - 0.4), Vector3(w + e, wh - 0.3, d + 0.4), r1, roof)
	# Gable ends.
	_tri(st, Vector3(-w, wh, -d), Vector3(0, wh + rh, -d), Vector3(w, wh, -d), wall)
	_tri(st, Vector3(w, wh, d), Vector3(0, wh + rh, d), Vector3(-w, wh, d), wall)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


func _tower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.9, 0.88, 0.82)
	var w := 2.5
	var top := 18.0
	var c := [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		_quad(st, a, b, b + Vector3(0, top, 0), a + Vector3(0, top, 0), wall)
		_tri(st, a + Vector3(0, top, 0), b + Vector3(0, top, 0), Vector3(0, top + 9.0, 0), Color(0.3, 0.32, 0.36))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(color)
		st.add_vertex(v)
