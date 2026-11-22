class_name TrackList
extends RefCounted
## Every circuit layout the player can pick. A Circuit with
## `use_selected_track` builds the one in GameSettings.track.
## Each layout ends with a straight run into the start/finish line (the grid,
## grandstands and pits sit there).

const TRACKS: Array[Dictionary] = [
	{
		"id": "greenhill", "name": "GREENHILL RING", "seed": 11,
		"tagline": "Fast and flowing. A long main straight into a tight hairpin.",
		"points": [
			Vector2(0, 250), Vector2(0, -330), Vector2(20, -405), Vector2(75, -425),
			Vector2(112, -380), Vector2(108, -300), Vector2(115, -225), Vector2(170, -165),
			Vector2(240, -170), Vector2(295, -215), Vector2(360, -195), Vector2(405, -110),
			Vector2(400, 0), Vector2(345, 80), Vector2(305, 140), Vector2(330, 195),
			Vector2(300, 255), Vector2(225, 290), Vector2(150, 370), Vector2(65, 400),
			Vector2(10, 360), Vector2(0, 315),
		],
	},
	{
		"id": "greenhill_rev", "name": "GREENHILL REVERSE", "seed": 12,
		"tagline": "The Ring run backwards. New braking points everywhere.",
		"points": [
			Vector2(0, 0), Vector2(0, 250), Vector2(0, 315), Vector2(10, 360),
			Vector2(65, 400), Vector2(150, 370), Vector2(225, 290), Vector2(300, 255),
			Vector2(330, 195), Vector2(305, 140), Vector2(345, 80), Vector2(400, 0),
			Vector2(405, -110), Vector2(360, -195), Vector2(295, -215), Vector2(240, -170),
			Vector2(170, -165), Vector2(115, -225), Vector2(108, -300), Vector2(112, -380),
			Vector2(75, -425), Vector2(20, -405), Vector2(0, -330),
		],
	},
	{
		"id": "kestrel", "name": "KESTREL PARK", "seed": 23,
		"tagline": "Short and twisty. Hairpins, esses and very little rest.",
		"points": [
			Vector2(0, 0), Vector2(0, -260), Vector2(25, -320), Vector2(85, -335),
			Vector2(140, -300), Vector2(150, -230), Vector2(200, -190), Vector2(270, -210),
			Vector2(320, -260), Vector2(380, -250), Vector2(410, -190), Vector2(390, -120),
			Vector2(330, -80), Vector2(300, -20), Vector2(320, 50), Vector2(300, 110),
			Vector2(240, 130), Vector2(180, 100), Vector2(130, 130), Vector2(90, 190),
			Vector2(30, 200), Vector2(0, 150), Vector2(0, 80),
		],
	},
]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t in TRACKS:
		out.append(t.id)
	return out


static func index_of(id: String) -> int:
	for i in TRACKS.size():
		if TRACKS[i].id == id:
			return i
	return 0


static func get_track(id: String) -> Dictionary:
	return TRACKS[index_of(id)]


static func points_of(id: String) -> PackedVector2Array:
	return PackedVector2Array(get_track(id).points)


## The same smooth closed curve a Circuit builds from `points`.
static func make_curve(points: PackedVector2Array) -> Curve3D:
	var curve := Curve3D.new()
	var n := points.size()
	for i in n:
		var p := points[i]
		var prev := points[(i - 1 + n) % n]
		var next := points[(i + 1) % n]
		# Catmull-Rom tangent direction, but each handle is limited to a third
		# of its own segment so uneven spacing (a long straight next to a tight
		# corner) can't make the curve overshoot into a kink.
		var dir := Vector3(next.x - prev.x, 0.0, next.y - prev.y).normalized()
		var len_in := p.distance_to(prev) / 3.0
		var len_out := p.distance_to(next) / 3.0
		curve.add_point(Vector3(p.x, 0.0, p.y), -dir * len_in, dir * len_out)
	curve.add_point(curve.get_point_position(0), curve.get_point_in(0), curve.get_point_out(0))
	curve.bake_interval = 1.0
	return curve


## Centre line as (x, z) points every few metres, plus the lap length, for
## map previews.
static func outline(id: String, step: float = 6.0) -> Dictionary:
	var curve := make_curve(points_of(id))
	var length := curve.get_baked_length()
	var pts := PackedVector2Array()
	var count := int(ceil(length / step))
	for k in count:
		var p := curve.sample_baked(length * k / count, true)
		pts.append(Vector2(p.x, p.z))
	# Corners: stretches where the direction turns more than ~15 degrees per
	# 30 m, counted when they peak above ~23 degrees.
	var turns := PackedFloat32Array()
	var k0 := 0
	for k in count:
		var a := pts[k]
		var b := pts[(k + 5) % count]
		var c := pts[(k + 10) % count]
		turns.append(absf((b - a).angle_to(c - b)))
		if turns[k] < turns[k0]:
			k0 = k
	var corners := 0
	var in_corner := false
	var peak := 0.0
	for j in count:
		var turn := turns[(k0 + j) % count]
		if not in_corner and turn > 0.25:
			in_corner = true
			peak = turn
		elif in_corner:
			peak = maxf(peak, turn)
			if turn < 0.15:
				in_corner = false
				if peak > 0.4:
					corners += 1
	return {"points": pts, "length": length, "corners": corners}
