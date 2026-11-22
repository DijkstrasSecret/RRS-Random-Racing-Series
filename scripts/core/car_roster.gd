class_name CarRoster
extends RefCounted
## Every car in the game, with the info the garage shows. Cars are original
## designs (fictional names) inspired by real models.
## apply() turns any Vehicle instance into the chosen car before it is ready.

const CARS: Array[Dictionary] = [
	{"id": "kartal", "name": "KARTAL 77 SL", "tagline": "1977 rear-drive classic. Light, slow, loves to slide."},
	{"id": "romola", "name": "ROMOLA STELLA 16D", "tagline": "Italian diesel hatch. Nimble and playful."},
	{"id": "quadra", "name": "QUADRA 16D", "tagline": "Compact diesel sedan. Easy and composed."},
	{"id": "psx_hatch", "name": "RETRO HATCH", "tagline": "Lively little 80s hatchback.",
		"model": "res://assets/cars/psx_hatch/psx_hatch.glb", "config": "res://assets/cars/psx_hatch/psx_hatch.tres",
		"paint_reference": "res://assets/cars/psx_hatch/psx_hatch_red.png"},
	{"id": "bavaro", "name": "BAVARO 4 GRAN", "tagline": "Rear-drive four-door coupe. Balanced and quick."},
	{"id": "hanlong", "name": "HANLONG E9", "tagline": "Electric, all-wheel drive. Brutal launch, silent speed."},
	{"id": "bellmont", "name": "BELLMONT WINGSPAN V8", "tagline": "Luxury express. All-wheel drive, V8, huge brakes."},
	{"id": "ashford", "name": "ASHFORD GT12", "tagline": "V12 grand tourer. Rear-drive, handle with care."},
]

const DRIVE_NAMES: PackedStringArray = ["FRONT", "REAR", "ALL-WHEEL"]


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
static func apply(car: Vehicle, id: String, paint: Color = Color(0, 0, 0, 0)) -> void:
	var e := entry(id)
	car.config = config(id)
	car.body_model = load(model_path(id)) as PackedScene
	car.paint_reference = load(e.paint_reference) if e.has("paint_reference") else null
	car.paint_color = paint
	car.paint_texture = null
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
