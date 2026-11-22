class_name WheelDirt
extends Node3D
## Dirt spray for one wheel: small dirt/grass chunks plus a faint dust puff,
## emitted only while the tyre is on a loose surface (grass, gravel).
## More speed or wheelspin = more dirt. Particles live in world space, so
## they stay behind as the car drives on.

## Surfaces with less grip than this count as off-road.
const LOOSE_GRIP := 0.85

var _chunks: GPUParticles3D
var _dust: GPUParticles3D


func _ready() -> void:
	_chunks = _make_chunks()
	_dust = _make_dust()
	add_child(_chunks)
	add_child(_dust)


## Called by the Wheel every physics tick.
func update_from(wheel: Wheel) -> void:
	var speed := absf(wheel.v_long)
	var spin := absf(wheel.omega * wheel.radius - wheel.v_long)
	var active := wheel.grounded and wheel.surface_grip < LOOSE_GRIP and (speed > 2.0 or spin > 2.0)
	_chunks.emitting = active
	_dust.emitting = active
	if not active:
		return
	global_position = wheel.contact_point + Vector3.UP * 0.05
	var strength := clampf(speed / 25.0 + spin / 8.0, 0.2, 1.0)
	_chunks.amount_ratio = strength
	_dust.amount_ratio = strength
	# Spray backwards relative to the direction the tyre is rolling.
	var back := 1.0 if wheel.omega >= 0.0 else -1.0
	(_chunks.process_material as ParticleProcessMaterial).direction = Vector3(0.0, 0.8, back)
	(_dust.process_material as ParticleProcessMaterial).direction = Vector3(0.0, 0.4, back)


func _make_chunks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DirtChunks"
	p.amount = 40
	p.lifetime = 0.8
	p.randomness = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 6, 12))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.8, 1.0)
	mat.spread = 28.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.5
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.damping_min = 0.5
	mat.damping_max = 1.5
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.08, 0.02, 0.08)
	# Each chunk is somewhere between dark earth and grass green...
	mat.color_initial_ramp = _gradient_texture([
		Color(0.22, 0.15, 0.08), Color(0.3, 0.2, 0.11), Color(0.2, 0.32, 0.12)])
	# ...and fades out at the end of its life.
	mat.color_ramp = _gradient_texture([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	quad.material = _particle_material(0.85)
	p.draw_pass_1 = quad
	return p


func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DirtDust"
	p.amount = 14
	p.lifetime = 1.3
	p.randomness = 0.4
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 6, 12))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.4, 1.0)
	mat.spread = 35.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.8
	mat.gravity = Vector3(0.0, 0.3, 0.0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.8
	mat.scale_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	mat.color_ramp = _gradient_texture([
		Color(0.45, 0.38, 0.27, 0.0), Color(0.45, 0.38, 0.27, 0.55), Color(0.5, 0.44, 0.33, 0.0)])
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	quad.material = _particle_material(0.0)
	p.draw_pass_1 = quad
	return p


## `hardness` 0 = soft round puff, 1 = solid round chunk.
func _particle_material(hardness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _round_sprite(hardness)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _gradient_texture(colors: Array[Color]) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## White disc that fades to transparent at the edge (tinted by particle colour).
func _round_sprite(hardness: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, lerpf(0.05, 0.8, hardness), 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, lerpf(0.5, 1.0, hardness)), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex
