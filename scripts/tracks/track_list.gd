class_name TrackList
extends RefCounted
## Every circuit layout the player can pick. A Circuit with
## `use_selected_track` builds the one in GameSettings.track.
## Each layout ends with a straight run into the start/finish line (the grid,
## grandstands and pits sit there).
## Elevation: "profile" = [lap fraction, height m] key points of the real
## circuit (times "height_scale"), or "hills" = how many metres of gentle
## made-up rise and fall (the same at a spot whichever way the track runs).

const TRACKS: Array[Dictionary] = [
	{
		"id": "greenhill", "name": "GREENHILL RING", "seed": 11, "theme": "hills", "hills": 20.0,
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
		"id": "greenhill_rev", "name": "GREENHILL REVERSE", "seed": 12, "theme": "hills", "hills": 20.0,
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
		"id": "kestrel", "name": "KESTREL PARK", "seed": 23, "theme": "mountains", "hills": 30.0,
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
	{
		"id": "monza", "name": "MONZA", "seed": 31, "theme": "hills", "real": true, "hills": 5.0,
		"tagline": "Temple of speed. Huge straights, tight chicanes, late braking.",
		# Real F1 layout (open f1-circuits outline data), scaled down to about 60%.
		"points": [
			Vector2(0, 0), Vector2(0, -364), Vector2(21, -373), Vector2(25, -382), Vector2(5, -442), Vector2(1, -457),
			Vector2(-1, -472), Vector2(-2, -564), Vector2(1, -588), Vector2(8, -615), Vector2(13, -629), Vector2(30, -657),
			Vector2(42, -672), Vector2(69, -698), Vector2(103, -720), Vector2(142, -736), Vector2(166, -742), Vector2(283, -763),
			Vector2(405, -781), Vector2(414, -800), Vector2(455, -818), Vector2(583, -874), Vector2(593, -877), Vector2(610, -877),
			Vector2(628, -869), Vector2(640, -856), Vector2(646, -841), Vector2(671, -704), Vector2(669, -687), Vector2(659, -678),
			Vector2(503, -574), Vector2(468, -547), Vector2(386, -465), Vector2(205, -276), Vector2(196, -262), Vector2(201, -221),
			Vector2(199, -208), Vector2(192, -190), Vector2(168, -163), Vector2(164, -146), Vector2(161, -48), Vector2(153, 422),
			Vector2(148, 438), Vector2(130, 457), Vector2(110, 464), Vector2(93, 463), Vector2(72, 457), Vector2(56, 447),
			Vector2(38, 428), Vector2(25, 408), Vector2(14, 382), Vector2(8, 353), Vector2(-4, 227),
		],
	},
	{
		"id": "spa", "name": "SPA-FRANCORCHAMPS", "seed": 37, "theme": "mountains", "real": true,
		# Real rise and fall (Stavelot = 0, Les Combes ~100 m), exaggerated a
		# little: the layout is halved but the hills only lose a fifth.
		"height_scale": 0.8, "profile": [
			[0.0, 55.0], [0.03, 57.0], [0.065, 44.0], [0.1, 22.0], [0.125, 38.0], [0.15, 52.0], [0.2, 68.0],
			[0.29, 100.0], [0.33, 90.0], [0.4, 72.0], [0.5, 50.0], [0.58, 30.0], [0.64, 2.0],
			[0.7, 6.0], [0.8, 25.0], [0.88, 40.0], [0.94, 50.0],
		],
		"tagline": "Ardennes classic. La Source hairpin, Eau Rouge, the long Kemmel run.",
		# Real F1 layout (open f1-circuits outline data), scaled down to about 60%.
		"points": [
			Vector2(0, 0), Vector2(0, -114), Vector2(11, -119), Vector2(56, -56), Vector2(68, -33), Vector2(88, 17),
			Vector2(117, 173), Vector2(136, 211), Vector2(139, 222), Vector2(138, 246), Vector2(124, 290), Vector2(129, 432),
			Vector2(125, 462), Vector2(47, 784), Vector2(33, 834), Vector2(21, 843), Vector2(-2, 846), Vector2(-14, 855),
			Vector2(-31, 907), Vector2(-41, 920), Vector2(-50, 924), Vector2(-203, 937), Vector2(-217, 932), Vector2(-226, 919),
			Vector2(-225, 904), Vector2(-217, 892), Vector2(-202, 887), Vector2(-141, 885), Vector2(-127, 880), Vector2(-119, 867),
			Vector2(-106, 802), Vector2(-99, 776), Vector2(-54, 649), Vector2(-53, 640), Vector2(-57, 621), Vector2(-68, 604),
			Vector2(-102, 581), Vector2(-113, 576), Vector2(-136, 572), Vector2(-146, 572), Vector2(-160, 575), Vector2(-184, 589),
			Vector2(-302, 681), Vector2(-312, 687), Vector2(-321, 690), Vector2(-332, 690), Vector2(-349, 683), Vector2(-372, 651),
			Vector2(-380, 645), Vector2(-397, 639), Vector2(-407, 640), Vector2(-423, 647), Vector2(-503, 688), Vector2(-523, 687),
			Vector2(-534, 676), Vector2(-560, 618), Vector2(-562, 601), Vector2(-554, 577), Vector2(-547, 568), Vector2(-516, 542),
			Vector2(-476, 521), Vector2(-450, 512), Vector2(-407, 501), Vector2(-384, 498), Vector2(-275, 502), Vector2(-261, 502),
			Vector2(-233, 497), Vector2(-208, 487), Vector2(-188, 475), Vector2(-123, 427), Vector2(-110, 408), Vector2(-105, 397),
			Vector2(-88, 285), Vector2(-77, 252), Vector2(-65, 222), Vector2(-32, 158), Vector2(-7, 167),
		],
	},
	{
		"id": "silverstone", "name": "SILVERSTONE", "seed": 41, "theme": "hills", "real": true, "hills": 6.0,
		"tagline": "Old airfield. Fast sweepers through Maggotts, Becketts and Chapel.",
		# Real F1 layout (open f1-circuits outline data), scaled down to about 60%.
		"points": [
			Vector2(0, 0), Vector2(0, -112), Vector2(3, -132), Vector2(9, -147), Vector2(17, -156), Vector2(31, -167),
			Vector2(48, -173), Vector2(135, -189), Vector2(172, -191), Vector2(316, -187), Vector2(373, -208), Vector2(395, -203),
			Vector2(443, -180), Vector2(463, -177), Vector2(477, -179), Vector2(518, -201), Vector2(530, -204), Vector2(544, -204),
			Vector2(556, -199), Vector2(569, -187), Vector2(596, -134), Vector2(606, -123), Vector2(906, 78), Vector2(971, 128),
			Vector2(987, 142), Vector2(995, 153), Vector2(1000, 166), Vector2(1002, 178), Vector2(1000, 190), Vector2(990, 212),
			Vector2(982, 221), Vector2(969, 228), Vector2(937, 240), Vector2(913, 251), Vector2(880, 273), Vector2(845, 301),
			Vector2(789, 340), Vector2(785, 351), Vector2(802, 377), Vector2(800, 394), Vector2(792, 401), Vector2(769, 417),
			Vector2(754, 423), Vector2(740, 427), Vector2(717, 430), Vector2(691, 414), Vector2(494, 232), Vector2(487, 226),
			Vector2(481, 214), Vector2(479, 201), Vector2(480, 190), Vector2(497, 107), Vector2(493, 76), Vector2(487, 63),
			Vector2(427, -28), Vector2(421, -41), Vector2(424, -54), Vector2(434, -61), Vector2(485, -71), Vector2(498, -80),
			Vector2(496, -95), Vector2(441, -123), Vector2(414, -128), Vector2(399, -128), Vector2(109, 135), Vector2(97, 152),
			Vector2(94, 165), Vector2(95, 178), Vector2(100, 193), Vector2(114, 202), Vector2(159, 212), Vector2(168, 215),
			Vector2(175, 223), Vector2(179, 234), Vector2(180, 245), Vector2(175, 257), Vector2(169, 265), Vector2(153, 273),
			Vector2(135, 271), Vector2(53, 221), Vector2(31, 196), Vector2(10, 165), Vector2(2, 134),
		],
	},
	{
		"id": "istanbul", "name": "ISTANBUL PARK", "seed": 47, "theme": "hills", "real": true,
		# Downhill plunge into Turn 1, Turn 8 on the side of the hill.
		"height_scale": 1.0, "profile": [
			[0.0, 20.0], [0.06, 10.0], [0.1, 4.0], [0.16, 10.0], [0.22, 16.0], [0.3, 14.0],
			[0.36, 18.0], [0.42, 22.0], [0.52, 18.0], [0.58, 14.0], [0.62, 12.0], [0.72, 18.0],
			[0.82, 22.0], [0.92, 24.0],
		],
		"tagline": "Runs anticlockwise. Home of the endless four-apex Turn 8.",
		# Real F1 layout (open f1-circuits outline data), scaled down to about 60%.
		"points": [
			Vector2(0, 0), Vector2(0, -150), Vector2(-3, -163), Vector2(-12, -170), Vector2(-82, -169), Vector2(-97, -172),
			Vector2(-117, -180), Vector2(-137, -199), Vector2(-153, -224), Vector2(-169, -273), Vector2(-177, -334), Vector2(-175, -393),
			Vector2(-165, -450), Vector2(-154, -478), Vector2(-153, -491), Vector2(-156, -506), Vector2(-166, -522), Vector2(-180, -532),
			Vector2(-194, -538), Vector2(-242, -542), Vector2(-252, -546), Vector2(-256, -554), Vector2(-244, -594), Vector2(-238, -621),
			Vector2(-238, -637), Vector2(-244, -645), Vector2(-253, -648), Vector2(-296, -650), Vector2(-306, -647), Vector2(-315, -639),
			Vector2(-485, -431), Vector2(-499, -419), Vector2(-511, -416), Vector2(-521, -419), Vector2(-529, -424), Vector2(-535, -432),
			Vector2(-542, -454), Vector2(-543, -472), Vector2(-540, -486), Vector2(-512, -555), Vector2(-463, -652), Vector2(-464, -662),
			Vector2(-479, -714), Vector2(-486, -722), Vector2(-527, -746), Vector2(-538, -749), Vector2(-583, -735), Vector2(-605, -724),
			Vector2(-634, -704), Vector2(-641, -694), Vector2(-646, -678), Vector2(-648, -654), Vector2(-626, -339), Vector2(-621, -320),
			Vector2(-614, -312), Vector2(-604, -311), Vector2(-568, -322), Vector2(-551, -318), Vector2(-282, -160), Vector2(-270, -145),
			Vector2(-257, -123), Vector2(-135, 304), Vector2(-129, 313), Vector2(-119, 317), Vector2(-110, 317), Vector2(-98, 311),
			Vector2(-93, 303), Vector2(-89, 278), Vector2(-79, 269), Vector2(-25, 289), Vector2(-9, 285),
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


## The same smooth closed curve a Circuit builds from `points` (with an
## optional height per point; empty = flat).
static func make_curve(points: PackedVector2Array, heights: PackedFloat32Array = PackedFloat32Array()) -> Curve3D:
	var curve := Curve3D.new()
	var n := points.size()
	var hs := heights if heights.size() == n else PackedFloat32Array()
	if hs.is_empty():
		hs.resize(n)
		hs.fill(0.0)
	for i in n:
		var p := Vector3(points[i].x, hs[i], points[i].y)
		var prev := Vector3(points[(i - 1 + n) % n].x, hs[(i - 1 + n) % n], points[(i - 1 + n) % n].y)
		var next := Vector3(points[(i + 1) % n].x, hs[(i + 1) % n], points[(i + 1) % n].y)
		# Catmull-Rom tangent direction, but each handle is limited to a third
		# of its own segment so uneven spacing (a long straight next to a tight
		# corner) can't make the curve overshoot into a kink.
		var dir := (next - prev).normalized()
		var len_in := p.distance_to(prev) / 3.0
		var len_out := p.distance_to(next) / 3.0
		curve.add_point(p, -dir * len_in, dir * len_out)
	curve.add_point(curve.get_point_position(0), curve.get_point_in(0), curve.get_point_out(0))
	curve.bake_interval = 1.0
	return curve


## The road's centre line for track `id`, with its hills. With elevation it
## is rebuilt from evenly spaced points (every ~6 m) so the slopes are smooth.
static func track_curve(id: String) -> Curve3D:
	var t := get_track(id)
	var flat := make_curve(points_of(id))
	if not (t.has("profile") or t.has("hills")):
		return flat
	var total := flat.get_baked_length()
	var n := int(total / 6.0)
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	var scale: float = t.get("height_scale", 1.0)
	for k in n:
		var p := flat.sample_baked(total * k / n, true)
		pts.append(Vector2(p.x, p.z))
		if t.has("profile"):
			hs.append(profile_height(t.profile, float(k) / n) * scale)
		else:
			hs.append(rolling_height(p.x, p.z, t.hills))
	hs = _blend_nearby(pts, hs, 30.0)
	# Lowest point at 0 so the land never dips below the base.
	var low := 1e9
	for h in hs:
		low = minf(low, h)
	for i in hs.size():
		hs[i] -= low
	return make_curve(pts, hs)


## Averages each point's height with every road point within `radius` on the
## map, so where two stretches run side by side (a tight chicane, a hairpin)
## their road surfaces meet at the same height instead of leaving a lip.
static func _blend_nearby(pts: PackedVector2Array, hs: PackedFloat32Array, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(hs.size())
	var r2 := radius * radius
	for i in pts.size():
		var sum := 0.0
		var wsum := 0.0
		for j in pts.size():
			var d2 := pts[i].distance_squared_to(pts[j])
			if d2 < r2:
				var w := 1.0 - sqrt(d2) / radius
				w *= w
				sum += hs[j] * w
				wsum += w
		out[i] = sum / wsum
	return out


## Smooth (Catmull-Rom) height along the lap from [fraction, height] keys.
static func profile_height(keys: Array, f: float) -> float:
	var n := keys.size()
	f = fposmod(f, 1.0)
	var k := n - 1
	for i in n:
		if float(keys[i][0]) > f:
			k = i - 1
			break
	k = (k + n) % n
	var f0: float = keys[k][0]
	var f1: float = keys[(k + 1) % n][0]
	if f1 <= f0:
		f1 += 1.0
	var t := clampf((f - f0 if f >= f0 else f + 1.0 - f0) / (f1 - f0), 0.0, 1.0)
	var p0: float = keys[(k - 1 + n) % n][1]
	var p1: float = keys[k][1]
	var p2: float = keys[(k + 1) % n][1]
	var p3: float = keys[(k + 2) % n][1]
	var t2 := t * t
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t)


## Gentle made-up rise and fall, 0..amount metres, long waves (~400-900 m).
static func rolling_height(x: float, z: float, amount: float) -> float:
	var v := 0.5 + 0.28 * sin(x * 0.0105 + 1.3) * cos(z * 0.0085 - 0.4) 			+ 0.22 * sin((x + z) * 0.0068 + 2.1)
	return clampf(v, 0.0, 1.0) * amount


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
