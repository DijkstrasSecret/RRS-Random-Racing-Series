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

@export var track_name: String = "Circuit"
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

## Lap fractions where sector 1 and sector 2 end (the real F1 sector lines).
var sector_splits := PackedFloat32Array([1.0 / 3.0, 2.0 / 3.0])
## Fastest sector times by anyone this session (-1 = none yet), and fastest lap.
var best_sectors := PackedFloat32Array([-1.0, -1.0, -1.0])
var best_lap: float = -1.0
## Lap fractions of the corners with grandstands (empty = the tightest ones).
var stand_corners := PackedFloat32Array()
## Run-off beside the corners: "gravel", "asphalt" or "sand".
var runoff := "gravel"
## Road surface sections: [from, to, type] lap fractions; the rest is tarmac.
var surfaces: Array = []
## Lap fractions built over water (island causeway), or (-1, -1).
var bridge := Vector2(-1.0, -1.0)
## Banked turns (an oval): [lap fraction, degrees] keys, eased between; the
## outside of the turn is the high side. Empty = flat road everywhere.
var bank_keys: Array = []
## Oval track: walls right at the outside edge, no curbs.
var oval := false
## Grip and extra rolling drag of each road surface.
const SURFACE_GRIP := {"tarmac": 1.0, "gravel": 0.78, "sand": 0.7, "wood": 0.95}
const SURFACE_DRAG := {"tarmac": 0.0, "gravel": 0.025, "sand": 0.045, "wood": 0.005}
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
## Pit lane (F1 circuits): lap distances relative to the start line where it
## leaves and rejoins (from < 0 < to), the side (+1 right / -1 left), the
## service zone. Empty = no pits.
var pit: Dictionary = {}
const PIT_OFFSET := 16.0   ## lane centre, metres from the track centre
const PIT_HALF := 4.5      ## half the lane width
const PIT_RAMP := 70.0     ## entry / exit length
const PIT_LIMIT := 16.7    ## 60 km/h
const PIT_ZONE := 36.0     ## length of the service zone
var _track_id := ""  ## set when built from the track list (use_selected_track)


func _ready() -> void:
	add_to_group("circuit")
	if use_selected_track:
		GameSettings.ensure_loaded()
		var track := TrackList.get_track(Tournament.current_track() if Tournament.active else GameSettings.track)
		points = PackedVector2Array(track.points)
		_track_id = String(track.id)
		track_name = TrackList.display_name(String(track.id))
		random_seed = int(track.seed)
		theme = String(track.get("theme", "hills"))
		if track.has("sectors"):
			sector_splits = PackedFloat32Array(track.sectors)
		stand_corners = PackedFloat32Array(track.get("stands", []))
		runoff = String(track.get("runoff", "gravel"))
		surfaces = track.get("surfaces", [])
		if track.has("bridge"):
			bridge = Vector2(track.bridge[0], track.bridge[1])
		bank_keys = track.get("bank", [])
		oval = bool(track.get("oval", false))
	_build_curve()
	_sample_curve()
	_apply_banking()
	_build_surface_grid()
	_build_environment()
	_build_ground()
	_build_road()
	_build_curbs()
	_plan_pit_lane()
	_build_verge()
	_build_causeway()
	_build_pit_lane()
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
	var spot := pos + right * lateral
	spot.y = surface_y(spot.x, spot.z, pos.y) + ROAD_Y
	var xf := Transform3D(_road_basis(off, dir), spot + Vector3(0.0, 0.1, 0.0))
	return global_transform * xf


## A car's resting basis on the road at `off`, facing `dir` (circuit space):
## tilted with the banking, level everywhere else.
func _road_basis(off: float, dir: Vector3) -> Basis:
	var b := Basis.looking_at(dir, Vector3.UP)
	var tilt := bank_slope_at(off)
	if absf(tilt) < 0.0001:
		return b
	# + slope = the right side is higher: roll left (about the forward axis).
	return Basis(dir.normalized(), -atan(tilt)) * b


## Slope across the road at `off` (height gained per metre to the right).
func bank_slope_at(off: float) -> float:
	if bank_keys.is_empty() or _samples.is_empty():
		return 0.0
	var n := _samples.size()
	var f := fposmod(off, length) / length * n
	var i := int(f)
	return lerpf(float(_samples[i % n].tilt), float(_samples[(i + 1) % n].tilt), f - i)


## Where a car should be put back on the road (world space): `lateral`
## metres right of the centre line at `off`, on the surface, banked.
func road_transform(off: float, lateral: float, lift: float = 0.3) -> Transform3D:
	var c := _at(off)
	var dir := (_at(off + 1.0) - _at(off - 1.0)).normalized()
	var spot := c + dir.cross(Vector3.UP).normalized() * lateral
	spot.y = surface_y(spot.x, spot.z, c.y) + ROAD_Y
	var b := _road_basis(off, dir)
	return global_transform * Transform3D(b, spot + b.y * lift)


## Distance (m) along the lap from the start line to the point nearest `world_pos`.
func progress_at(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))


## Road surface type at lap distance `off`: "tarmac", "gravel", "sand" or "wood".
func surface_at(off: float) -> String:
	var f := fposmod(off, length) / length
	for sec in surfaces:
		if f >= float(sec[0]) and f < float(sec[1]):
			return String(sec[2])
	return "tarmac"


## True if lap distance `off` is on the causeway over the water.
func on_bridge(off: float) -> bool:
	if bridge.x < 0.0:
		return false
	var f := fposmod(off, length) / length
	return f >= bridge.x and f < bridge.y


## Side of the road the infield is on (0 = left, 1 = right): pits go there.
func infield_side() -> int:
	var turning := 0.0
	for smp: Dictionary in _samples:
		turning += float(smp.curv)
	return 0 if turning > 0.0 else 1


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
		v[i] = minf(sqrt(_banked_accel(lateral_accel * float(_samples[i].grip), float(_samples[i].tilt)) / maxf(k, 0.0001)), top_speed)
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
			var decel := maxf(brake_accel * float(_samples[idx].grip) + 9.81 * grade, brake_accel * 0.4)
			v[idx] = minf(v[idx], sqrt(next * next + 2.0 * decel * step))
	return v


## Sideways acceleration a car can hold on a banked road (slope `tilt`)
## when the tyres alone give `accel`: the banking holds part of the turn.
static func _banked_accel(accel: float, tilt: float) -> float:
	var t := absf(tilt)
	if t < 0.0001:
		return accel
	return (accel + 9.81 * t) / maxf(1.0 - accel / 9.81 * t, 0.25)


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
			"surf": surface_at(off),
			"grip": float(SURFACE_GRIP[surface_at(off)]),
			"bridge": on_bridge(off),
			"tilt": 0.0,
		})
		outline.append(Vector2(pos.x, pos.z))
		_bounds = Rect2(pos.x, pos.z, 0, 0) if k == 0 else _bounds.expand(Vector2(pos.x, pos.z))


## Banking: each sample's slope across the road from the track's bank keys.
func _apply_banking() -> void:
	if bank_keys.is_empty():
		return
	# The outside of the turns is the infield's other side.
	var dir := 1.0 if infield_side() == 0 else -1.0
	for smp: Dictionary in _samples:
		smp.tilt = tan(deg_to_rad(bank_degrees(bank_keys, float(smp.off) / length))) * dir


## Banking in degrees at lap fraction `f`: eased between the keys.
static func bank_degrees(keys: Array, f: float) -> float:
	var n := keys.size()
	f = fposmod(f, 1.0)
	for i in n:
		var a: Array = keys[i]
		var b: Array = keys[(i + 1) % n]
		var fa := float(a[0])
		var fb := float(b[0]) + (1.0 if i == n - 1 else 0.0)
		var ff := f if f >= fa else f + 1.0
		if ff >= fa and ff <= fb:
			return lerpf(float(a[1]), float(b[1]), smoothstep(fa, fb, ff))
	return float(keys[0][1])


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


## Height of whatever you would stand on at a world position: the road (and
## curbs) on the track, else the higher of the land and the grass verge.
## Trackside objects are placed with this so they sit on the visible ground.
func surface_height(x: float, z: float) -> float:
	var local := to_local(Vector3(x, 0.0, z))
	var nearest := curve.get_closest_point(local)
	var dc := Vector2(local.x - nearest.x, local.z - nearest.z).length()
	var road := surface_y(local.x, local.z, nearest.y) + ROAD_Y
	var out := dc - road_width * 0.5
	# On the inside of a tight corner the verge is squeezed narrower (see
	# _build_verge), so it drops away faster.
	var k := nearest_sample(local.x, local.z)
	if k >= 0:
		var smp: Dictionary = _samples[k]
		var side := signf((Vector3(local.x, 0.0, local.z) - smp.pos).dot(smp.right))
		if signf(smp.curv) == -side and absf(smp.curv) > 0.0001:
			var limit := 0.85 / absf(smp.curv) - road_width * 0.5
			if limit < 9.0:
				out *= 9.0 / maxf(limit, 0.5)
	var verge := road + _verge_drop(maxf(out, 0.0))
	var land := ground_height(x, z) - global_position.y
	var h := road if out <= curb_width else maxf(land, verge)
	return h + global_position.y


## How far the verge has dropped `out` metres beyond the road edge.
func _verge_drop(out: float) -> float:
	for i in VERGE.size() - 1:
		var a: Array = VERGE[i]
		var b: Array = VERGE[i + 1]
		if out <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (out - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(VERGE[VERGE.size() - 1][1]) - (out - float(VERGE[VERGE.size() - 1][0])) * 0.5


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
					var smp: Dictionary = _samples[k]
					var h := p.y
					if smp.tilt != 0.0:
						# Banked: higher toward the outside of the turn.
						var right: Vector3 = smp.right
						h += float(smp.tilt) * ((x - p.x) * right.x + (z - p.z) * right.z)
					sum += h * w
					wsum += w
	return sum / wsum if wsum > 0.0 else fallback


## Index of the centre-line sample nearest a map position (circuit space),
## searched up to ~2 grid cells away; -1 if none that close.
func nearest_sample(x: float, z: float) -> int:
	var cx := int(floor(x / SURFACE_CELL))
	var cz := int(floor(z / SURFACE_CELL))
	var best := -1
	var best_d := 1e18
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for k: int in _surface_grid.get(Vector2i(cx + dx, cz + dz), []):
				var p: Vector3 = _samples[k].pos
				var d := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
				if d < best_d:
					best_d = d
					best = k
	return best


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
	var tools := {}
	var half := road_width * 0.5
	var n := _samples.size()
	for k in n:
		var a: Dictionary = _samples[k]
		var b: Dictionary = _samples[(k + 1) % n]
		var kind: String = a.surf
		if not tools.has(kind):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[kind] = t
		var st: SurfaceTool = tools[kind]
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
	for kind: String in tools:
		var mesh := (tools[kind] as SurfaceTool).commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _road_texture() if kind == "tarmac" else _surface_texture(kind)
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.surface_set_material(0, mat)
		var body_name := "Road" if kind == "tarmac" else "Road_" + kind
		_add_static_mesh(body_name, mesh, SURFACE_GRIP[kind], SURFACE_DRAG[kind])


## Road textures for the loose / wooden sections (one tile = road width x road width).
func _surface_texture(kind: String) -> ImageTexture:
	var w := 64
	var img := Image.create_empty(w, w, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var a := Color(0.52, 0.45, 0.36)
	var b := Color(0.64, 0.56, 0.45)
	if kind == "sand":
		a = Color(0.82, 0.74, 0.55)
		b = Color(0.9, 0.84, 0.66)
	elif kind == "wood":
		a = Color(0.42, 0.3, 0.2)
		b = Color(0.52, 0.38, 0.25)
	for y in w:
		for x in w:
			var c := a.lerp(b, rng.randf())
			if kind == "wood":
				# Planks across the road, dark gaps between them.
				c = a.lerp(b, 0.4 + 0.3 * sin(float(x) * 0.7 + float(y / 6) * 2.1)) * (0.55 if y % 6 == 0 else 1.0)
			elif kind != "sand" and absf(float(x) - w * 0.5) > w * 0.36:
				c = c.lerp(Color(0.4, 0.36, 0.3), 0.35)  # loose stones pushed to the edges
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_curbs() -> void:
	if oval:
		return
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
		if a.surf != "tarmac" or b.surf != "tarmac":
			continue
		var color := red if int(a.off / 2.0) % 2 == 0 else white
		st.set_color(color)
		for side: float in [-1.0, 1.0]:
			var a_in := _on_surface(a.pos + a.right * side * half)
			var b_in := _on_surface(b.pos + b.right * side * half)
			# Level across with the road edge (on the inside of a hairpin the
			# blend would otherwise pick up the other side's height).
			var ao: Vector3 = a.pos + a.right * side * (half + curb_width)
			var bo: Vector3 = b.pos + b.right * side * (half + curb_width)
			var a_out := Vector3(ao.x, a_in.y + 0.04, ao.z)
			var b_out := Vector3(bo.x, b_in.y + 0.04, bo.z)
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


## Grass verge along both road edges, sloping from the road edge down into
## the ground. The land is a 16 m grid that can't follow every crest and dip
## of a hilly road exactly; the verge hides the step and gives a car leaving
## the road a slope to run onto instead of an edge to drop off. Where the
## land is higher it simply stays buried.
const VERGE := [[0.0, -0.01], [1.5, -0.08], [4.0, -0.6], [9.0, -2.6]]  ## [metres out, metres down]

func _build_verge() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := road_width * 0.5
	var n := _samples.size()
	var rows: Array = []  # per sample, per side: points from road edge outwards
	for k in n:
		var smp: Dictionary = _samples[k]
		var per_side: Array = []
		for side: float in [-1.0, 1.0]:
			# On the inside of a tight corner the verge is narrower so it can't fold over.
			var inside := signf(smp.curv) == -side and absf(smp.curv) > 0.0001
			var limit := 0.85 / absf(smp.curv) - half if inside else 999.0
			var pts := PackedVector3Array()
			var edge: Vector3 = smp.pos + smp.right * side * half
			var edge_y := surface_y(edge.x, edge.z, smp.pos.y) + ROAD_Y
			for v: Array in VERGE:
				var out := minf(float(v[0]), maxf(limit, 0.5) * float(v[0]) / 9.0) if inside else float(v[0])
				var p: Vector3 = smp.pos + smp.right * side * (half + out)
				var y := edge_y + float(v[1])
				# Nearer to some other bit of road than to its own (inside a
				# hairpin, beside another stretch): tuck it well down, so it
				# can't come up beside that road.
				var owner := nearest_sample(p.x, p.z)
				if owner >= 0:
					var q: Vector3 = _samples[owner].pos
					if Vector2(q.x - p.x, q.z - p.z).length() < half + out - 1.5:
						y -= 3.0
				# Under the pit apron: tuck it away.
				if not pit.is_empty() and side == float(pit.side) and absf(pit_lateral(float(smp.off))) > 0.5:
					y -= 3.0
				pts.append(Vector3(p.x, y, p.z))
			per_side.append(pts)
		rows.append(per_side)
	for k in n:
		var a_rows: Array = rows[k]
		var b_rows: Array = rows[(k + 1) % n]
		if _samples[k].bridge or _samples[(k + 1) % n].bridge:
			continue  # over the water: no grass verge
		for side in 2:
			var a: PackedVector3Array = a_rows[side]
			var b: PackedVector3Array = b_rows[side]
			for r in VERGE.size() - 1:
				# _quad wants the left edge first (left side: outer edge is left).
				if side == 1:
					_verge_quad(st, a[r], a[r + 1], b[r + 1], b[r])
				else:
					_verge_quad(st, a[r + 1], a[r], b[r], b[r + 1])
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = terrain._detail_texture() if terrain else null
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_add_static_mesh("Verge", mesh, 0.55, 0.05)


# --- Pit lane ------------------------------------------------------------------------

## Finds the straight through the start line and fits the pit lane on it.
func _plan_pit_lane() -> void:
	if _track_id == "" or not String(TrackList.get_track(_track_id).get("series", "")) in ["F1", "NASCAR"]:
		return
	# (An oval's turns are wide but banked: only the front stretch counts.)
	var limit := 1.0 / 400.0 if oval else 1.0 / 100.0
	var back := 0.0
	while back < 600.0 and absf(curvature_at(length - back - 10.0)) < limit:
		back += 5.0
	var fwd := 0.0
	while fwd < 400.0 and absf(curvature_at(fwd + 10.0)) < limit:
		fwd += 5.0
	var from := -back + 10.0
	var to := fwd - 5.0
	# Ramps as long as the straight allows (45..70 m).
	var ramp := clampf((to - from - PIT_ZONE - 24.0) * 0.5, 0.0, PIT_RAMP)
	if ramp < 45.0:
		return  # straight too short for a pit lane
	var zone_mid := (from + ramp + to - ramp) * 0.5
	pit = {"from": from, "to": to, "ramp": ramp, "side": 1.0 if infield_side() == 1 else -1.0,
		"zone_from": zone_mid - PIT_ZONE * 0.5, "zone_to": zone_mid + PIT_ZONE * 0.5}


## Lap distance relative to the start line (-length/2 .. length/2).
func _rel(off: float) -> float:
	var o := fposmod(off, length)
	return o - length if o > length * 0.5 else o


## Signed lateral position of the pit lane centre at lap distance `off`
## (+ = right of the centre line); 0 where there is no lane.
func pit_lateral(off: float) -> float:
	if pit.is_empty():
		return 0.0
	var r := _rel(off)
	if r <= float(pit.from) or r >= float(pit.to):
		return 0.0
	var ramp := float(pit.ramp)
	var k := smoothstep(float(pit.from), float(pit.from) + ramp, r) * smoothstep(float(pit.to), float(pit.to) - ramp, r)
	return k * PIT_OFFSET * float(pit.side)


## Signed sideways offset of a world position from the centre line (+ = right).
func lateral_of(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	var off := curve.get_closest_offset(local)
	var c := _at(off)
	var tangent := (_at(off + 1.0) - _at(off - 1.0)).normalized()
	return (local - c).dot(tangent.cross(Vector3.UP).normalized())


## True if the position is in the pit lane (off the track, on the lane).
func in_pit_lane(world_pos: Vector3) -> bool:
	if pit.is_empty():
		return false
	var off := progress_at(world_pos)
	var lat := pit_lateral(off)
	if absf(lat) < road_width * 0.5 + 2.0:
		return false
	return absf(lateral_of(world_pos) - lat) < PIT_HALF + 1.0


## True if the position is in the service zone (pit boxes).
func in_pit_zone(world_pos: Vector3) -> bool:
	if not in_pit_lane(world_pos):
		return false
	var r := _rel(progress_at(world_pos))
	return r >= float(pit.zone_from) and r <= float(pit.zone_to)


## Lap distance of the middle of the service zone.
func pit_zone_mid() -> float:
	return fposmod((float(pit.zone_from) + float(pit.zone_to)) * 0.5, length)


func _right_at_local(off: float) -> Vector3:
	return (_at(off + 1.0) - _at(off - 1.0)).normalized().cross(Vector3.UP).normalized()


## Ground spots the terrain must keep below the pit apron: [world x, z, max y].
func pit_ground_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if pit.is_empty():
		return out
	var r := float(pit.from)
	while r <= float(pit.to):
		var lat := absf(pit_lateral(r))
		if lat > 1.0:
			var c := _at(fposmod(r, length))
			var right := _right_at_local(r) * float(pit.side)
			var lo := road_width * 0.5
			while lo <= lat + PIT_HALF + 6.0:
				var g := to_global(c + right * lo)
				out.append(Vector3(g.x, g.z, to_global(c).y + ROAD_Y - 0.06))
				lo += 3.0
		r += 3.0
	return out


## Concrete apron, the lane itself, the pit wall, boxes and the 60 boards.
func _build_pit_lane() -> void:
	if pit.is_empty():
		return
	var apron := SurfaceTool.new()
	apron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lane := SurfaceTool.new()
	lane.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := road_width * 0.5
	var side := float(pit.side)
	var step := 3.0
	var r := float(pit.from)
	var wall_body := StaticBody3D.new()
	wall_body.name = "PitWall"
	wall_body.collision_layer = LAYER_WORLD
	wall_body.collision_mask = 0
	var any_wall := false
	while r < float(pit.to):
		var r2 := minf(r + step, float(pit.to))
		var la := absf(pit_lateral(r))
		var lb := absf(pit_lateral(r2))
		var ca := _at(fposmod(r, length))
		var cb := _at(fposmod(r2, length))
		var ra := _right_at_local(r) * side
		var rb := _right_at_local(r2) * side
		var y := Vector3.UP * (ROAD_Y + 0.005)
		if la > 1.0 or lb > 1.0:
			# Apron: from the road edge out past the lane.
			_side_quad(apron, ca + ra * half + y, ca + ra * (la + PIT_HALF + 6.0) + y,
					cb + rb * half + y, cb + rb * (lb + PIT_HALF + 6.0) + y, side)
		# The lane strip (with its painted edges) never reaches onto the track:
		# where it splits off / rejoins, its inner edge is the road's edge.
		if la + PIT_HALF > half + 1.0 and lb + PIT_HALF > half + 1.0:
			var up := Vector3.UP * 0.012
			_side_quad(lane, ca + ra * maxf(la - PIT_HALF, half) + y + up, ca + ra * (la + PIT_HALF) + y + up,
					cb + rb * maxf(lb - PIT_HALF, half) + y + up, cb + rb * (lb + PIT_HALF) + y + up, side)
		# Pit wall between the track and the lane, where the lane is clear of the road.
		if la > half + PIT_HALF + 2.5 and lb > half + PIT_HALF + 2.5:
			var wa := ca + ra * (half + 2.4)
			var wb := cb + rb * (half + 2.4)
			var mid := (wa + wb) * 0.5 + Vector3.UP * (ROAD_Y + 0.5)
			var along := wb - wa
			var col := Color(0.92, 0.92, 0.9) if int(r / 6.0) % 2 == 0 else Color(0.85, 0.15, 0.12)
			_box(wall, mid, ra * 0.25, Vector3.UP * 0.5, along * 0.5, col)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.5, 1.0, along.length())
			cs.shape = bs
			cs.transform = Transform3D(Basis.looking_at(along.normalized(), Vector3.UP), mid)
			wall_body.add_child(cs)
			any_wall = true
		r = r2
	var apron_mesh := apron.commit()
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.58, 0.58, 0.6)
	amat.roughness = 1.0
	amat.cull_mode = BaseMaterial3D.CULL_DISABLED
	apron_mesh.surface_set_material(0, amat)
	_add_static_mesh("Road_pit_apron", apron_mesh, 0.95, 0.0)
	var lane_mesh := lane.commit()
	var lmat := StandardMaterial3D.new()
	lmat.albedo_texture = _road_texture()
	lmat.albedo_color = Color(0.85, 0.85, 0.9)
	lmat.roughness = 0.9
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lane_mesh.surface_set_material(0, lmat)
	_add_static_mesh("Road_pit_lane", lane_mesh, 1.0, 0.0)
	# Pit boxes painted along the service zone (team colours).
	var boxes := SurfaceTool.new()
	boxes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := [Color(0.9, 0.1, 0.1), Color(0.1, 0.35, 0.9), Color(0.95, 0.75, 0.1), Color(0.1, 0.65, 0.3)]
	var k := 0
	var z := float(pit.zone_from)
	while z < float(pit.zone_to) - 4.0:
		var c := _at(fposmod(z + 3.0, length))
		var rr := _right_at_local(z + 3.0) * side
		var lat := absf(pit_lateral(z + 3.0))
		var fw := (_at(z + 4.0) - _at(z + 2.0)).normalized()
		_box(boxes, c + rr * (lat + PIT_HALF * 0.55) + Vector3.UP * (ROAD_Y + 0.025), rr * 1.6, Vector3.UP * 0.005, fw * 2.6, colors[k % colors.size()])
		k += 1
		z += 6.0
	boxes.generate_normals()
	var box_mesh := boxes.commit()
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	box_mesh.surface_set_material(0, bmat)
	var bmi := MeshInstance3D.new()
	bmi.name = "PitBoxes"
	bmi.mesh = box_mesh
	add_child(bmi)
	if any_wall:
		wall.generate_normals()
		var wall_mesh := wall.commit()
		var wmat := StandardMaterial3D.new()
		wmat.vertex_color_use_as_albedo = true
		wall_mesh.surface_set_material(0, wmat)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wall_mesh
		wall_body.add_child(wmi)
	add_child(wall_body)
	# 60 km/h board at the lane entry, outside the lane once it's clear of the track.
	var e := float(pit.from) + float(pit.ramp)
	var ce := _at(fposmod(e, length))
	var spot := ce + _right_at_local(e) * side * (absf(pit_lateral(e)) + PIT_HALF + 1.5)
	_brake_board(to_global(spot), direction_at(e), "60")


## A flat quad from inner / outer edge points at two stations (either side).
func _side_quad(st: SurfaceTool, a_in: Vector3, a_out: Vector3, b_in: Vector3, b_out: Vector3, side: float) -> void:
	if side > 0.0:
		_quad(st, a_in, a_out, b_out, b_in, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	else:
		_quad(st, a_out, a_in, b_in, b_out, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


## Wooden posts and side beams under the causeway, down into the water.
func _build_causeway() -> void:
	if bridge.x < 0.0:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := road_width * 0.5
	var wood := Color(0.36, 0.26, 0.18)
	var floor_y := to_local(Vector3(0, TrackTerrain.SEA_LEVEL - 2.0, 0)).y
	for k in _samples.size():
		var smp: Dictionary = _samples[k]
		if not smp.bridge:
			continue
		var pos: Vector3 = smp.pos
		var right: Vector3 = smp.right
		var fwd: Vector3 = smp.tangent
		# Side beams along the deck edges.
		for side: float in [-1.0, 1.0]:
			var c := pos + right * side * (half + 0.15) + Vector3.UP * (ROAD_Y - 0.25)
			_box(st, c, right * 0.18, Vector3.UP * 0.35, fwd * 1.05, wood)
		if k % 5 == 0:
			for side: float in [-1.0, 1.0, 0.0]:
				var top := pos + right * side * (half - 0.4)
				var mid := Vector3(top.x, (top.y + floor_y) * 0.5, top.z)
				_box(st, mid, right * 0.25, Vector3.UP * (top.y - floor_y) * 0.5, fwd * 0.25, wood)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Causeway"
	mi.mesh = mesh
	add_child(mi)


## A box centred on `c` with half-axes `ax`, `ay`, `az`.
func _box(st: SurfaceTool, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color) -> void:
	var corners := []
	for i in 8:
		corners.append(c + ax * (1.0 if i & 1 else -1.0) + ay * (1.0 if i & 2 else -1.0) + az * (1.0 if i & 4 else -1.0))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for idx: int in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.set_color(col)
			st.add_vertex(corners[idx])


func _verge_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var nrm := (b - a).cross(d - a)
	st.set_normal(nrm.normalized() if nrm.y > 0.0001 else Vector3.UP)
	for v: Vector3 in [a, c, b, a, d, c]:
		var g := to_global(v)
		st.set_color(terrain._ground_color(0.0, 0.0, g.x, g.z) if terrain else Color(0.3, 0.5, 0.22))
		st.set_uv(Vector2(g.x, g.z) * 0.08)
		st.add_vertex(v)


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
	# Part of the track (road of any surface, curbs): not "off track" there.
	if node_name.begins_with("Road") or node_name == "Curbs":
		body.set_meta(&"road", true)
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
			var lat := road_width * 0.5 + 3.5
			# On the pit side, stand behind the pit lane, not between it and the track.
			var pit_lat := pit_lateral(off)
			if absf(pit_lat) > 0.5 and signf(pit_lat) == outside:
				lat = absf(pit_lat) + PIT_HALF + 3.0
			_brake_board(pos + right * outside * lat, tangent, str(dist))
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
	body.name = "TrackProp"
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
	add_child(body, true)


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
