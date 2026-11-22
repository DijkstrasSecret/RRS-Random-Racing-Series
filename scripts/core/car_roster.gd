class_name CarRoster
extends RefCounted
## Every car in the game, with the info the garage shows. Cars are original
## designs (fictional names) inspired by real models.
## apply() turns any Vehicle instance into the chosen car before it is ready.

## Sorted by class (D slowest ... A fastest), then roughly by pace.
const CARS: Array[Dictionary] = [
	{"id": "kartal", "tier": 0, "livery": true, "name": "KARTAL 77 SL", "tagline": "1977 rear-drive classic. Light, slow, loves to slide."},
	{"id": "mirelle", "tier": 0, "livery": true, "name": "MIRELLE 15D", "tagline": "French diesel supermini. Frugal, light and forgiving."},
	{"id": "kerkenez", "tier": 0, "livery": true, "name": "KERKENEZ 98 SX", "tagline": "90s rear-drive saloon. Soft, simple, happy sideways."},
	{"id": "atmaca", "tier": 0, "livery": true, "name": "ATMACA 90 STANCE", "tagline": "Slammed on air ride. Stiff, low and tail-happy."},
	{"id": "quadra", "tier": 1, "livery": true, "name": "QUADRA 16D", "tagline": "Compact diesel sedan. Easy and composed."},
	{"id": "romola", "tier": 1, "livery": true, "name": "ROMOLA STELLA 16D", "tagline": "Italian diesel hatch. Nimble and playful."},
	{"id": "kaze", "tier": 1, "name": "KAZE SORA 16I", "tagline": "Rev-happy petrol sedan. Sharp and dependable."},
	{"id": "dingo", "tier": 1, "name": "DINGO 13T", "tagline": "Boxy little turbo SUV. Tall, but surprisingly brisk."},
	{"id": "piccolo", "tier": 1, "livery": true, "name": "PICCOLO 16", "tagline": "Retro city hatch. Go-kart steering."},
	{"id": "harcourt", "tier": 1, "name": "HARCOURT X21", "tagline": "V6 executive saloon. Smooth and refined."},
	{"id": "psx_hatch", "tier": 1, "name": "RETRO HATCH", "tagline": "Lively little 80s hatchback.",
		"model": "res://assets/cars/psx_hatch/psx_hatch.glb", "config": "res://assets/cars/psx_hatch/psx_hatch.tres",
		"paint_reference": "res://assets/cars/psx_hatch/psx_hatch_red.png"},
	{"id": "mammoth", "tier": 2, "name": "MAMMOTH 20TD", "tagline": "Twin-turbo diesel pickup. Heavy, tall, unstoppable."},
	{"id": "orion", "tier": 2, "name": "ORION ARC 6", "tagline": "Electric streamliner. Rear-drive, slippery and silent."},
	{"id": "bastion", "tier": 2, "name": "BASTION 350D", "tagline": "Off-road icon. A brick with a big diesel heart."},
	{"id": "bavaro", "tier": 2, "name": "BAVARO 4 GRAN", "tagline": "Rear-drive four-door coupe. Balanced and quick."},
	{"id": "braxton", "tier": 2, "livery": true, "name": "BRAXTON BRAWLER V6", "tagline": "American muscle. Big, loud and loose at the rear."},
	{"id": "ashford", "tier": 3, "name": "ASHFORD GT12", "tagline": "V12 grand tourer. Rear-drive, handle with care."},
	{"id": "bellmont", "tier": 3, "name": "BELLMONT WINGSPAN V8", "tagline": "Luxury express. All-wheel drive, V8, huge brakes."},
	{"id": "hanlong", "tier": 3, "name": "HANLONG E9", "tagline": "Electric, all-wheel drive. Brutal launch, silent speed."},
]

const DRIVE_NAMES: PackedStringArray = ["FRONT", "REAR", "ALL-WHEEL"]
## Car classes, slowest first.
const TIER_NAMES: PackedStringArray = ["D", "C", "B", "A"]
const TIER_TITLES: PackedStringArray = ["CLASSIC", "STREET", "SPORT", "SUPER"]
const TIER_COLORS: PackedColorArray = [Color(0.55, 0.8, 0.45), Color(0.35, 0.7, 1.0), Color(0.75, 0.5, 1.0), Color(1.0, 0.45, 0.3)]


## True if the car has a racing livery that can be switched on and off.
static func has_livery(id: String) -> bool:
	return bool(entry(id).get("livery", false))


static func tier(id: String) -> int:
	return int(entry(id).get("tier", 1))


## Car ids whose class bit is set in `mask` (bit 0 = D ... bit 3 = A).
static func ids_in_tiers(mask: int) -> PackedStringArray:
	var out := PackedStringArray()
	for c in CARS:
		if mask & (1 << int(c.tier)):
			out.append(c.id)
	return out


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CARS:
		out.append(c.id)
	return out


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CARS:
		out.append(c.name)
	return out


static func entry(id: String) -> Dictionary:
	for c in CARS:
		if c.id == id:
			return c
	return CARS[0]


static func index_of(id: String) -> int:
	for i in CARS.size():
		if CARS[i].id == id:
			return i
	return 0


static func model_path(id: String) -> String:
	return entry(id).get("model", "res://assets/cars/%s/%s.glb" % [id, id])


static func config_path(id: String) -> String:
	return entry(id).get("config", "res://assets/cars/%s/%s.tres" % [id, id])


static func config(id: String) -> VehicleConfig:
	return load(config_path(id)) as VehicleConfig


## Make `car` (not yet ready) into roster car `id`. Alpha 0 = factory paint.
static func apply(car: Vehicle, id: String, paint: Color = Color(0, 0, 0, 0), livery: bool = true) -> void:
	var e := entry(id)
	car.config = config(id)
	car.body_model = load(model_path(id)) as PackedScene
	car.paint_reference = load(e.paint_reference) if e.has("paint_reference") else null
	car.paint_color = paint
	car.paint_texture = null
	car.show_livery = livery
	car.set_meta(&"car_id", id)


## Numbers and 0..10 ratings for the garage.
static func stats(id: String) -> Dictionary:
	var c := config(id)
	# Peak power from the torque curve.
	var peak_kw := 0.0
	for p in c.torque_curve:
		var rpm := minf(p.x, c.redline_rpm)
		peak_kw = maxf(peak_kw, c.max_torque * p.y * rpm * TAU / 60.0 / 1000.0)
	var hp := peak_kw * 1.341
	# Top speed: limited by drag (power) or by gearing at the redline.
	var wheel_w := peak_kw * c.drivetrain_efficiency * 1000.0
	var v_drag := pow(wheel_w / maxf(0.5 * 1.225 * c.drag_area, 0.01), 1.0 / 3.0) * 0.96
	var top_ratio: float = c.gear_ratios[c.gear_ratios.size() - 1] * c.final_drive
	var v_gear := c.redline_rpm * TAU / 60.0 / top_ratio * c.wheel_radius
	var top_kmh := minf(v_drag, v_gear) * 3.6
	var hp_per_tonne := hp / (c.mass / 1000.0)
	var traction := 1.15 if c.drive_type == VehicleConfig.DriveType.AWD else 1.0
	var decel := minf(c.brake_torque / (c.wheel_radius * c.mass), c.tire_grip * 9.81)
	var agility := c.tire_grip * 6.0 - c.mass / 900.0 + c.steer_rate * 0.5
	if c.drive_type == VehicleConfig.DriveType.RWD:
		agility += 0.6
	return {
		"hp": roundi(hp), "kg": roundi(c.mass), "top_kmh": roundi(top_kmh),
		"drive": DRIVE_NAMES[c.drive_type], "electric": c.electric,
		"acceleration": clampf((hp_per_tonne * traction - 40.0) / 28.0, 1.0, 10.0),
		"top_speed": clampf((top_kmh - 130.0) / 20.0, 1.0, 10.0),
		"handling": clampf(agility * 1.15, 1.0, 10.0),
		"braking": clampf((decel - 6.0) / 0.6, 1.0, 10.0),
		"weight": clampf(c.mass / 240.0, 1.0, 10.0),
		"grip": clampf((c.tire_grip - 0.9) * 22.0, 1.0, 10.0),
	}
