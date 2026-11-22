class_name TrackList
extends RefCounted
## Every circuit layout the player can pick (real F1 circuits, scaled down). A Circuit with
## `use_selected_track` builds the one in GameSettings.track.
## Each layout ends with a straight run into the start/finish line (the grid,
## grandstands and pits sit there).
## "series": F1 / RX (rallycross) / ISLAND, shown on the track card.
## "surfaces" = [from, to, "gravel" | "sand" | "wood"] lap fractions (rest is tarmac).
## "bridge" = [from, to] lap fractions built over water (island causeway).
## "stands" = lap fractions of the famous corners with grandstands;
## "runoff" = "gravel" (old-school traps) or "asphalt" (modern painted run-off).
## "sectors" = lap fractions where the real F1 sector 1 and 2 lines are.
## Elevation: "profile" = [lap fraction, height m] key points of the real
## circuit (times "height_scale"), or "hills" = how many metres of gentle
## made-up rise and fall (the same at a spot whichever way the track runs).

const TRACKS: Array[Dictionary] = [
	{
		"id": "monza", "name": "MONZA", "seed": 31, "theme": "hills", "series": "F1", "hills": 5.0,
		"sectors": [0.34, 0.69],  # after the Roggia chicane / after Ascari
		# Grandstands: Rettifilo, Roggia, Lesmo, Ascari, Parabolica. Gravel run-off.
		"stands": [0.11, 0.31, 0.42, 0.62, 0.88], "runoff": "gravel",
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
		"id": "spa", "name": "SPA-FRANCORCHAMPS", "seed": 37, "theme": "mountains", "series": "F1",
		"sectors": [0.31, 0.72],  # before Les Combes / after Stavelot
		# La Source, Eau Rouge, Les Combes, Pouhon, Stavelot, Bus Stop.
		"stands": [0.03, 0.1, 0.32, 0.5, 0.64, 0.95], "runoff": "gravel",
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
		"id": "silverstone", "name": "SILVERSTONE", "seed": 41, "theme": "hills", "series": "F1", "hills": 6.0,
		"sectors": [0.31, 0.70],  # after Aintree / after Chapel
		# Abbey, Maggotts-Becketts, Stowe, Vale-Club, Brooklands-Luffield. Painted asphalt run-off.
		"stands": [0.06, 0.2, 0.46, 0.7, 0.88], "runoff": "asphalt",
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
		"id": "istanbul", "name": "ISTANBUL PARK", "seed": 47, "theme": "hills", "series": "F1",
		"sectors": [0.30, 0.67],  # after Turn 6 / after Turn 11
		# Turn 1, Turns 3-4, Turn 8, Turn 9, Turns 12-14.
		"stands": [0.05, 0.21, 0.42, 0.62, 0.9], "runoff": "asphalt",
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
	{
		"id": "holjes", "name": "HÖLJES", "seed": 53, "theme": "mountains", "series": "RX", "hills": 14.0,
		"runoff": "gravel", "surfaces": [[0.1385, 0.5326, "gravel"], [0.6406, 0.8712, "gravel"]],
		"tagline": "Sweden's rallycross temple. Pine forest, loose gravel and a flying jump.",
		# Rallycross circuit, layout follows the real track's character.
		"points": [
			Vector2(0, 0), Vector2(0, -22), Vector2(0, -44), Vector2(0, -66), Vector2(4, -88), Vector2(22, -100),
			Vector2(43, -96), Vector2(57, -79), Vector2(68, -60), Vector2(79, -41), Vector2(90, -22), Vector2(101, -3),
			Vector2(118, 11), Vector2(139, 18), Vector2(162, 16), Vector2(184, 12), Vector2(206, 12), Vector2(227, 19),
			Vector2(245, 32), Vector2(258, 50), Vector2(264, 70), Vector2(267, 93), Vector2(268, 115), Vector2(270, 137),
			Vector2(272, 159), Vector2(274, 181), Vector2(273, 203), Vector2(257, 217), Vector2(235, 215), Vector2(216, 205),
			Vector2(196, 196), Vector2(175, 188), Vector2(153, 189), Vector2(135, 202), Vector2(123, 221), Vector2(103, 229),
			Vector2(82, 225), Vector2(65, 211), Vector2(48, 197), Vector2(31, 182), Vector2(14, 168), Vector2(3, 149),
			Vector2(0, 128), Vector2(0, 106), Vector2(0, 84), Vector2(0, 62), Vector2(0, 40), Vector2(0, 18),
		],
	},
	{
		"id": "lydden", "name": "LYDDEN HILL", "seed": 59, "theme": "hills", "series": "RX", "hills": 12.0,
		"runoff": "gravel", "surfaces": [[0.1660, 0.5939, "gravel"]],
		"tagline": "Where rallycross was born. Devil's Elbow, then up the gravel to North Bend.",
		# Rallycross circuit, layout follows the real track's character.
		"points": [
			Vector2(0, 0), Vector2(0, -22), Vector2(0, -44), Vector2(0, -66), Vector2(7, -86), Vector2(28, -93),
			Vector2(45, -80), Vector2(56, -61), Vector2(67, -42), Vector2(78, -23), Vector2(89, -4), Vector2(100, 15),
			Vector2(115, 32), Vector2(135, 42), Vector2(157, 44), Vector2(179, 44), Vector2(201, 44), Vector2(223, 44),
			Vector2(245, 47), Vector2(265, 56), Vector2(283, 69), Vector2(298, 86), Vector2(307, 106), Vector2(312, 128),
			Vector2(316, 149), Vector2(320, 171), Vector2(323, 193), Vector2(327, 215), Vector2(331, 236), Vector2(335, 258),
			Vector2(339, 280), Vector2(343, 302), Vector2(346, 323), Vector2(350, 345), Vector2(354, 367), Vector2(358, 388),
			Vector2(362, 410), Vector2(359, 431), Vector2(341, 443), Vector2(320, 438), Vector2(306, 421), Vector2(292, 404),
			Vector2(277, 388), Vector2(263, 371), Vector2(249, 354), Vector2(235, 337), Vector2(221, 320), Vector2(206, 303),
			Vector2(192, 286), Vector2(178, 269), Vector2(164, 252), Vector2(150, 235), Vector2(136, 218), Vector2(121, 202),
			Vector2(107, 185), Vector2(86, 176), Vector2(64, 179), Vector2(42, 180), Vector2(22, 172), Vector2(7, 156),
			Vector2(0, 134), Vector2(0, 112), Vector2(0, 90), Vector2(0, 68), Vector2(0, 46), Vector2(0, 24),
			Vector2(0, 2),
		],
	},
	{
		"id": "montalegre", "name": "MONTALEGRE", "seed": 61, "theme": "mountains", "series": "RX", "hills": 22.0,
		"runoff": "gravel", "surfaces": [[0.1210, 0.6015, "gravel"], [0.6360, 0.9240, "gravel"]],
		"tagline": "Portuguese hills. A big left-right, a long gravel sweeper and a tight hairpin.",
		# Rallycross circuit, layout follows the real track's character.
		"points": [
			Vector2(0, 0), Vector2(0, -22), Vector2(0, -44), Vector2(0, -66), Vector2(6, -87), Vector2(23, -100),
			Vector2(45, -98), Vector2(64, -87), Vector2(84, -76), Vector2(103, -65), Vector2(123, -57), Vector2(145, -61),
			Vector2(161, -76), Vector2(170, -96), Vector2(179, -116), Vector2(189, -136), Vector2(198, -156), Vector2(207, -176),
			Vector2(217, -195), Vector2(226, -215), Vector2(239, -233), Vector2(257, -245), Vector2(279, -249), Vector2(301, -245),
			Vector2(320, -234), Vector2(333, -217), Vector2(340, -196), Vector2(346, -175), Vector2(351, -153), Vector2(357, -132),
			Vector2(363, -111), Vector2(369, -90), Vector2(374, -68), Vector2(380, -47), Vector2(386, -26), Vector2(391, -5),
			Vector2(397, 17), Vector2(403, 38), Vector2(408, 59), Vector2(414, 81), Vector2(420, 102), Vector2(426, 123),
			Vector2(431, 144), Vector2(437, 166), Vector2(443, 187), Vector2(448, 208), Vector2(454, 229), Vector2(458, 251),
			Vector2(447, 270), Vector2(426, 274), Vector2(406, 265), Vector2(386, 256), Vector2(366, 246), Vector2(346, 237),
			Vector2(326, 228), Vector2(306, 218), Vector2(286, 209), Vector2(266, 200), Vector2(246, 190), Vector2(226, 181),
			Vector2(206, 172), Vector2(186, 162), Vector2(166, 153), Vector2(146, 144), Vector2(124, 140), Vector2(103, 147),
			Vector2(87, 163), Vector2(70, 176), Vector2(48, 180), Vector2(27, 175), Vector2(10, 161), Vector2(1, 141),
			Vector2(0, 120), Vector2(0, 98), Vector2(0, 76), Vector2(0, 54), Vector2(0, 32), Vector2(0, 10),
		],
	},
	{
		"id": "hell", "name": "HELL", "seed": 67, "theme": "mountains", "series": "RX", "hills": 4.0,
		"runoff": "gravel", "surfaces": [[0.3570, 0.6121, "gravel"]],
		"tagline": "Fast and flat by the Norwegian fjord. Long straights, one gravel loop.",
		# Rallycross circuit, layout follows the real track's character.
		"points": [
			Vector2(0, 0), Vector2(0, -22), Vector2(0, -44), Vector2(0, -66), Vector2(0, -88), Vector2(6, -110),
			Vector2(22, -125), Vector2(44, -129), Vector2(66, -125), Vector2(87, -121), Vector2(109, -117), Vector2(131, -114),
			Vector2(152, -110), Vector2(174, -106), Vector2(196, -102), Vector2(217, -95), Vector2(229, -77), Vector2(226, -55),
			Vector2(220, -33), Vector2(214, -12), Vector2(209, 9), Vector2(203, 31), Vector2(197, 52), Vector2(192, 73),
			Vector2(194, 95), Vector2(210, 110), Vector2(229, 121), Vector2(235, 142), Vector2(224, 161), Vector2(204, 169),
			Vector2(182, 174), Vector2(161, 180), Vector2(140, 186), Vector2(118, 191), Vector2(97, 197), Vector2(76, 203),
			Vector2(54, 207), Vector2(32, 202), Vector2(14, 189), Vector2(3, 170), Vector2(0, 148), Vector2(0, 126),
			Vector2(0, 104), Vector2(0, 82), Vector2(0, 60), Vector2(0, 38), Vector2(0, 16),
		],
	},
	{
		"id": "coral", "name": "CORAL BAY", "seed": 71, "theme": "island", "series": "ISLAND", "hills": 6.0,
		"runoff": "sand", "surfaces": [[0.0651, 0.4241, "sand"], [0.4241, 0.6303, "wood"], [0.6303, 0.8859, "sand"]],
		"bridge": [0.4241, 0.6303],  # wooden causeway over the lagoon
		"tagline": "Tropical island. Sandy roads, beach front, and a wooden causeway over the lagoon.",
		# Fictional island circuit.
		"points": [
			Vector2(0, 0), Vector2(0, -22), Vector2(0, -44), Vector2(0, -66), Vector2(0, -88), Vector2(0, -110),
			Vector2(6, -131), Vector2(23, -145), Vector2(44, -149), Vector2(67, -147), Vector2(89, -145), Vector2(111, -143),
			Vector2(133, -141), Vector2(155, -139), Vector2(177, -137), Vector2(199, -135), Vector2(221, -136), Vector2(241, -145),
			Vector2(257, -161), Vector2(269, -179), Vector2(282, -197), Vector2(295, -215), Vector2(308, -232), Vector2(329, -239),
			Vector2(349, -229), Vector2(359, -210), Vector2(369, -190), Vector2(378, -170), Vector2(387, -150), Vector2(396, -130),
			Vector2(406, -110), Vector2(411, -88), Vector2(411, -65), Vector2(405, -44), Vector2(400, -22), Vector2(394, -1),
			Vector2(388, 20), Vector2(382, 42), Vector2(377, 63), Vector2(371, 84), Vector2(365, 105), Vector2(360, 127),
			Vector2(354, 148), Vector2(348, 169), Vector2(343, 190), Vector2(337, 212), Vector2(331, 233), Vector2(325, 254),
			Vector2(320, 276), Vector2(309, 295), Vector2(289, 304), Vector2(268, 300), Vector2(250, 287), Vector2(232, 275),
			Vector2(213, 262), Vector2(192, 258), Vector2(173, 269), Vector2(165, 290), Vector2(156, 310), Vector2(137, 322),
			Vector2(115, 322), Vector2(96, 311), Vector2(83, 293), Vector2(71, 275), Vector2(58, 257), Vector2(46, 239),
			Vector2(33, 221), Vector2(20, 202), Vector2(8, 184), Vector2(1, 163), Vector2(0, 140), Vector2(0, 118),
			Vector2(0, 96), Vector2(0, 74), Vector2(0, 52), Vector2(0, 30), Vector2(0, 8),
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


## Name in normal case ("Spa-Francorchamps", "Istanbul Park").
static func display_name(id: String) -> String:
	var words: PackedStringArray = []
	for w in String(get_track(id).name).split(" "):
		var parts: PackedStringArray = []
		for p in w.split("-"):
			parts.append(p.substr(0, 1) + p.substr(1).to_lower())
		words.append("-".join(parts))
	return " ".join(words)


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
	var total := flat.get_baked_length()
	var n := int(total / 6.0)
	var pts := PackedVector2Array()
	for k in n:
		var p := flat.sample_baked(total * k / n, true)
		pts.append(Vector2(p.x, p.z))
	# The layouts are scaled down but the road is still 12 m wide: round off
	# any turn tighter than MIN_RADIUS so the inside of the road, curbs and
	# verge never fold over themselves.
	pts = _ease_tight_turns(pts, MIN_RADIUS)
	var hs := PackedFloat32Array()
	var scale: float = t.get("height_scale", 1.0)
	for k in n:
		if t.has("profile"):
			hs.append(profile_height(t.profile, float(k) / n) * scale)
		elif t.has("hills"):
			hs.append(rolling_height(pts[k].x, pts[k].y, t.hills))
		else:
			hs.append(0.0)
	hs = _blend_nearby(pts, hs, 30.0)
	# Lowest point at 0 so the land never dips below the base.
	var low := 1e9
	for h in hs:
		low = minf(low, h)
	for i in hs.size():
		hs[i] -= low
	return make_curve(pts, hs)


## Tightest turn (m) a circuit may have.
const MIN_RADIUS := 20.0


## Nudges points (evenly spaced, a closed loop) towards their neighbours
## wherever the turn is tighter than `rmin`, until none is.
static func _ease_tight_turns(pts: PackedVector2Array, rmin: float) -> PackedVector2Array:
	var n := pts.size()
	for it in 400:
		var out := pts.duplicate()
		var moved := false
		for i in n:
			var a := pts[(i - 1 + n) % n]
			var b := pts[i]
			var c := pts[(i + 1) % n]
			var cross := absf((b - a).cross(c - b))
			if cross < 0.0001:
				continue
			var r := a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * cross)
			if r < rmin:
				out[i] = b.lerp((a + c) * 0.5, 0.5)
				moved = true
		pts = out
		if not moved:
			break
	return pts


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
