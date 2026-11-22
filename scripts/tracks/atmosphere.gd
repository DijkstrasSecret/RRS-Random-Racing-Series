class_name TrackAtmosphere
extends Node3D
## Sky, sun (or moon), fog, clouds and the full-screen atmosphere effect for
## a circuit, set by the time of day and weather from the race settings.
## The sun is placed relative to the main straight, so at sunset it sits
## low ahead of you as you come down the straight.

enum DayTime { MORNING, NOON, SUNSET, NIGHT }
enum Weather { CLEAR, HAZY, FOG }

const CLOUD_HEIGHT := 260.0
const FIELD_SIZE := 3000.0
const WIND := Vector2(4.5, 1.6)
## Must match CLOUD_WAVES in cloud_field.gdshaderinc.
const CLOUD_WAVES: Array[Vector4] = [
	Vector4(9, 4, 0.30, 0.3), Vector4(5, -11, 0.26, 1.7), Vector4(-13, 6, 0.22, 4.1), Vector4(14, 9, 0.18, 2.2),
	Vector4(3, -17, 0.15, 5.0), Vector4(19, -7, 0.12, 0.9), Vector4(-8, -15, 0.10, 3.3), Vector4(22, 13, 0.08, 1.1),
]

## Per time of day: sun height and angle from the main straight (degrees),
## light colour/energy, sky colours, ambient, and effect strengths.
const TIMES := {
	DayTime.MORNING: {"elev": 16.0, "yaw": 115.0, "light": Color(1.0, 0.86, 0.72), "energy": 1.05,
		"top": Color(0.32, 0.52, 0.82), "horizon": Color(0.86, 0.82, 0.78), "ground": Color(0.32, 0.34, 0.3),
		"sun": Color(1.0, 0.82, 0.6), "ambient": 0.55, "shadows": 0.32, "rays": 0.45, "flare": 0.35,
		"cloud_lit": Color(1.0, 0.95, 0.9), "cloud_shade": Color(0.66, 0.68, 0.75)},
	DayTime.NOON: {"elev": 58.0, "yaw": -50.0, "light": Color(1.0, 0.98, 0.94), "energy": 1.25,
		"top": Color(0.2, 0.42, 0.84), "horizon": Color(0.72, 0.8, 0.9), "ground": Color(0.3, 0.33, 0.3),
		"sun": Color(1.0, 0.96, 0.88), "ambient": 0.65, "shadows": 0.42, "rays": 0.25, "flare": 0.3,
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.72, 0.76, 0.84)},
	DayTime.SUNSET: {"elev": 7.0, "yaw": 8.0, "light": Color(1.0, 0.58, 0.32), "energy": 1.1,
		"top": Color(0.22, 0.24, 0.5), "horizon": Color(0.95, 0.6, 0.45), "ground": Color(0.28, 0.22, 0.24),
		"sun": Color(1.0, 0.62, 0.32), "ambient": 0.35, "shadows": 0.22, "rays": 0.55, "flare": 0.4,
		"cloud_lit": Color(1.0, 0.68, 0.5), "cloud_shade": Color(0.42, 0.32, 0.45)},
	DayTime.NIGHT: {"elev": 38.0, "yaw": 150.0, "light": Color(0.55, 0.65, 0.95), "energy": 0.32,
		"top": Color(0.012, 0.018, 0.05), "horizon": Color(0.06, 0.08, 0.14), "ground": Color(0.02, 0.025, 0.03),
		"sun": Color(0.8, 0.85, 1.0), "ambient": 0.32, "shadows": 0.0, "rays": 0.0, "flare": 0.0,
		"cloud_lit": Color(0.2, 0.23, 0.32), "cloud_shade": Color(0.07, 0.08, 0.12)},
}

var time_of_day: int = DayTime.SUNSET
var weather: int = Weather.CLEAR
## Unit vector pointing at the sun (or moon at night).
var sun_dir := Vector3.UP
var environment: Environment
var sun: DirectionalLight3D

var _cloud_threshold := 0.3


## `main_dir` is the direction of the main straight (x, z); `centre` the
## middle of the circuit.
func build(main_dir: Vector2, centre: Vector2) -> void:
	var t: Dictionary = TIMES[time_of_day]
	var yaw := deg_to_rad(t.yaw)
	var flat := Vector3(main_dir.x, 0.0, main_dir.y).normalized().rotated(Vector3.UP, -yaw)
	var elev := deg_to_rad(t.elev)
	sun_dir = (flat * cos(elev) + Vector3.UP * sin(elev)).normalized()
	_cloud_threshold = [0.32, 0.12, -0.05][weather]
	if time_of_day == DayTime.NIGHT:
		_cloud_threshold += 0.15
	var horizon: Color = t.horizon
	if weather == Weather.FOG:
		horizon = horizon.lerp(Color(0.6, 0.62, 0.66) * (0.25 if time_of_day == DayTime.NIGHT else 1.0), 0.5)
	_build_environment(t, horizon)
	_build_sun(t)
	_build_clouds(t, horizon, centre)
	_build_screen_fx(t)


func _build_environment(t: Dictionary, horizon: Color) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/vfx/shaders/sky_retro.gdshader")
	var top: Color = t.top
	if weather == Weather.FOG:
		top = top.lerp(horizon, 0.6)
	elif weather == Weather.HAZY:
		top = top.lerp(horizon, 0.25)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", t.ground)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_color", t.sun)
	sky_mat.set_shader_parameter("sun_glow", [0.7, 0.9, 0.5][weather])
	sky_mat.set_shader_parameter("sun_size", 0.0008 if time_of_day == DayTime.NIGHT else 0.0012)
	sky_mat.set_shader_parameter("moon", 1.0 if time_of_day == DayTime.NIGHT else 0.0)
	sky_mat.set_shader_parameter("stars", 0.9 if time_of_day == DayTime.NIGHT and weather != Weather.FOG else 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = t.ambient
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = horizon
	environment.fog_density = [0.0005, 0.0018, 0.009][weather]
	environment.fog_sky_affect = [0.0, 0.35, 1.0][weather]
	environment.fog_sun_scatter = 0.12 if time_of_day == DayTime.SUNSET else 0.05
	# Soft bloom so headlights, brake lights and the sun glow.
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	world_env.add_to_group("world_environment")
	add_child(world_env)


func _build_sun(t: Dictionary) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = t.light
	sun.light_energy = t.energy * [1.0, 0.8, 0.45][weather]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	# The light (and its shadows) comes from at least 30 degrees up, even when
	# the visible sun is low: a real 7 degree sun throws shadows hundreds of
	# metres long, which looked like thin ghost trees across the track.
	var light_dir := sun_dir
	var min_elev := deg_to_rad(30.0)
	if asin(clampf(sun_dir.y, -1.0, 1.0)) < min_elev:
		var flat := Vector3(sun_dir.x, 0.0, sun_dir.z).normalized()
		light_dir = (flat * cos(min_elev) + Vector3.UP * sin(min_elev)).normalized()
	sun.basis = Basis.looking_at(-light_dir, Vector3.UP if absf(light_dir.y) < 0.98 else Vector3.FORWARD)


func _build_clouds(t: Dictionary, horizon: Color, centre: Vector2) -> void:
	var origin := centre - Vector2.ONE * FIELD_SIZE * 0.5
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 8
	puff.rings = 4
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/vfx/shaders/cloud.gdshader")
	mat.set_shader_parameter("wind", WIND)
	mat.set_shader_parameter("field_origin", origin)
	mat.set_shader_parameter("field_size", FIELD_SIZE)
	mat.set_shader_parameter("lit_color", t.cloud_lit)
	mat.set_shader_parameter("shade_color", t.cloud_shade)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("sun_dir", sun_dir)
	if weather == Weather.FOG:
		mat.set_shader_parameter("fade_start", 200.0)
		mat.set_shader_parameter("fade_end", 900.0)
	puff.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xforms: Array[Transform3D] = []
	var cell := 70.0
	var n := int(FIELD_SIZE / cell)
	for i in n:
		for j in n:
			var p := origin + Vector2(i + rng.randf(), j + rng.randf()) * cell
			var d := cloud_density(p)
			if d < 0.3:
				continue
			for k in (2 if d > 0.75 else 1):
				var r := lerpf(22.0, 48.0, d) * rng.randf_range(0.8, 1.2)
				var pos := Vector3(p.x + rng.randf_range(-25.0, 25.0), CLOUD_HEIGHT + rng.randf_range(-12.0, 18.0),
						p.y + rng.randf_range(-25.0, 25.0))
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * 1.3, r * 0.55, r))
				xforms.append(Transform3D(b, pos))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Clouds"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)


func _build_screen_fx(t: Dictionary) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/vfx/shaders/screen_fx.gdshader")
	mat.render_priority = -100  # before other see-through things (dirt, glass)
	mat.set_shader_parameter("sun_dir", sun_dir)
	mat.set_shader_parameter("sun_color", t.sun)
	mat.set_shader_parameter("shadow_strength", t.shadows * [1.0, 0.7, 0.2][weather])
	mat.set_shader_parameter("cloud_height", CLOUD_HEIGHT)
	mat.set_shader_parameter("cloud_threshold", _cloud_threshold)
	mat.set_shader_parameter("wind", WIND)
	mat.set_shader_parameter("field_size", FIELD_SIZE)
	mat.set_shader_parameter("ray_strength", t.rays * [1.0, 1.3, 0.35][weather])
	mat.set_shader_parameter("flare_strength", t.flare * [1.0, 0.6, 0.0][weather])
	mat.set_shader_parameter("glare_strength", t.flare * 0.5 * [1.0, 0.8, 0.2][weather])
	quad.material = mat
	var fx := MeshInstance3D.new()
	fx.name = "ScreenFX"
	fx.mesh = quad
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.extra_cull_margin = 16384.0
	add_child(fx)


## Same as cloud_density() in cloud_field.gdshaderinc (with no wind offset).
func cloud_density(p: Vector2) -> float:
	var f := 0.0
	for w in CLOUD_WAVES:
		f += w.z * sin(TAU * (w.x * p.x + w.y * p.y) / FIELD_SIZE + w.w)
	f /= 1.41
	return smoothstep(_cloud_threshold, _cloud_threshold + 0.35, f)
