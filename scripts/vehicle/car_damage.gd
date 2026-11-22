class_name CarDamage
extends Node3D
## Crash damage for one car (added by Vehicle when damage is on).
## - Reads the car's contacts from Jolt each tick (ground is ignored), turns
##   the hardest hit into damage for one zone: front, rear, left, right, roof.
## - Visual: dents the body (and livery) where it was hit, darkens the paint
##   round the dent, breaks head / brake lamps, sparks when scraping, a burst
##   of debris on big hits, engine smoke when the front is badly hurt.
## - FULL: less engine power from front damage, a little more drag, and the
##   steering pulls towards a damaged side.
## Measured hits (Bavaro, tests/damage_probe.gd): barrier at 60 km/h ~16 kNs,
## car into car at 40 km/h ~4 kNs.

signal damaged(zone: int, amount: float)

enum Zone { FRONT, REAR, LEFT, RIGHT, ROOF }
const ZONE_NAMES: PackedStringArray = ["FRONT", "REAR", "LEFT", "RIGHT", "ROOF"]
## Speed change (m/s) a hit must cause before it does any damage.
const HIT_THRESHOLD := 1.8
## Furthest a body vertex can be pushed in, in metres.
const MAX_DENT := 0.34

var level: int = 2  ## 1 = visual only, 2 = visual + mechanical
var zones := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])

var _car: Vehicle
var _cooldown := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _recent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _meshes: Array[Dictionary] = []
var _half_length := 2.2
var _bottom_y := 0.2
var _roof_y := 1.1  ## above this (car space) a hit counts as the roof
var _sparks: CPUParticles3D
var _debris: CPUParticles3D
var _smoke: CPUParticles3D


func setup(car: Vehicle, damage_level: int) -> void:
	_car = car
	level = damage_level
	car.contact_monitor = true
	car.max_contacts_reported = maxi(car.max_contacts_reported, 8)
	_prepare_meshes()
	_measure_body()
	_make_particles()


## 0..1 overall (for the HUD and tests).
func total() -> float:
	var t := 0.0
	for z in zones:
		t += z
	return t / zones.size()


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	for i in _cooldown.size():
		_cooldown[i] = maxf(_cooldown[i] - delta, 0.0)
		if _cooldown[i] <= 0.0:
			_recent[i] = 0.0
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	if state == null:
		return
	var best := 0.0
	var sum_imp := 0.0
	var sum_pos := Vector3.ZERO
	var sum_dir := Vector3.ZERO
	var scrape := false
	var scrape_pos := Vector3.ZERO
	for c in state.get_contact_count():
		var other := state.get_contact_collider_object(c)
		if other == null or other.has_meta(&"surface_grip"):
			continue  # road, grass, kerbs, gravel, terrain
		var pos := state.get_contact_local_position(c)
		var rel := state.get_contact_local_velocity_at_position(c) - state.get_contact_collider_velocity_at_position(c)
		var n := state.get_contact_local_normal(c)
		var tangential := (rel - n * rel.dot(n)).length()
		if tangential > 3.0:
			scrape = true
			scrape_pos = pos
		var imp_vec := state.get_contact_impulse(c)
		var impulse := imp_vec.length()
		best = maxf(best, impulse)
		# A flat side against a flat wall is reported at the box's corners:
		# average the points, and take the zone from the push's direction.
		sum_imp += impulse
		sum_pos += pos * impulse
		sum_dir += imp_vec
	_sparks.emitting = scrape
	if scrape:
		_sparks.global_position = scrape_pos
	if best > 0.0 and sum_imp > 0.0:
		var inv := _car.global_transform.affine_inverse()
		_hit(inv * (sum_pos / sum_imp), best / _car.mass, inv.basis * sum_dir)


## A hit at `local_pos` (car space) that changed the car's speed by `dv` m/s.
func _hit(local_pos: Vector3, dv: float, push: Vector3 = Vector3.ZERO) -> void:
	if dv < HIT_THRESHOLD:
		return
	var amount := clampf((dv - HIT_THRESHOLD) / 20.0, 0.0, 0.6)
	var zone := _zone_of(local_pos, push)
	# One crash shows up over several ticks: count only the strongest part.
	var extra := amount - _recent[zone]
	if extra <= 0.005:
		return
	_recent[zone] = amount
	_cooldown[zone] = 0.35
	zones[zone] = minf(zones[zone] + extra, 1.0)
	_dent(local_pos, extra, zone)
	if extra > 0.12:
		_debris.global_position = _car.global_transform * local_pos
		_debris.restart()
	_apply_effects()
	damaged.emit(zone, extra)


## Zone from the direction the car was pushed (car space) when known, else
## from where it was hit.
func _zone_of(p: Vector3, push: Vector3 = Vector3.ZERO) -> int:
	var a := push.abs()
	if push.length() > 0.001:
		if a.y > a.x and a.y > a.z and p.y > _roof_y:
			return Zone.ROOF
		if a.x >= a.z:
			return Zone.LEFT if p.x < 0.0 else Zone.RIGHT
		return Zone.FRONT if p.z < 0.0 else Zone.REAR
	if p.z < -_half_length * 0.45:
		return Zone.FRONT
	if p.z > _half_length * 0.45:
		return Zone.REAR
	if p.y > _roof_y:
		return Zone.ROOF
	return Zone.LEFT if p.x < 0.0 else Zone.RIGHT


## Lamps, smoke and (FULL) handling follow the damage.
func _apply_effects() -> void:
	_car.set_lamps_broken(zones[Zone.FRONT] > 0.5, zones[Zone.REAR] > 0.5)
	var front := zones[Zone.FRONT]
	_smoke.emitting = front > 0.45
	_smoke.color = Color(0.55, 0.55, 0.55, 0.6).lerp(Color(0.12, 0.12, 0.12, 0.75), clampf((front - 0.45) / 0.45, 0.0, 1.0))
	if level >= 2:
		_car.power_scale = 1.0 - 0.4 * clampf((front - 0.2) / 0.8, 0.0, 1.0)
		_car.drag_scale = 1.0 + 0.15 * (zones[Zone.FRONT] + zones[Zone.REAR]) * 0.5
		# A bent wheel pulls the car towards the damaged side (+ = right).
		_car.steer_pull = (zones[Zone.RIGHT] - zones[Zone.LEFT]) * deg_to_rad(2.5)


# --- dents ---------------------------------------------------------------------------

func _prepare_meshes() -> void:
	var model := _car.get_node_or_null("Model")
	if model == null:
		return
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if _on_wheel(mi, model):
			continue  # wheels spin on their own; everything else dents together
		var src := mi.mesh as ArrayMesh
		if src == null:
			continue
		# Each car needs its own copy (imported meshes are shared).
		var mesh := ArrayMesh.new()
		var surfaces: Array = []
		var offsets: Array = []
		var tints: Array = []
		var bends: Array = []
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if arrays[Mesh.ARRAY_COLOR] == null:
				var white := PackedColorArray()
				white.resize(count)
				white.fill(Color.WHITE)
				arrays[Mesh.ARRAY_COLOR] = white
			surfaces.append(arrays)
			var off := PackedVector3Array()
			off.resize(count)
			offsets.append(off)
			var tint := PackedFloat32Array()
			tint.resize(count)
			tint.fill(1.0)
			tints.append(tint)
			var bend := PackedVector3Array()
			bend.resize(count)
			bends.append(bend)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(s, src.surface_get_material(s))
		mi.mesh = mesh
		_car.use_vertex_tint(mi)
		_meshes.append({"mi": mi, "mesh": mesh, "surfaces": surfaces, "offsets": offsets, "tints": tints, "bends": bends})


## Body size (car space) from the model, for zones and dent height.
func _measure_body() -> void:
	var box := AABB()
	var first := true
	var to_car := _car.global_transform.affine_inverse()
	for entry in _meshes:
		var mi: MeshInstance3D = entry.mi
		var b: AABB = (to_car * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	_half_length = box.size.z * 0.5
	_bottom_y = box.position.y
	_roof_y = box.position.y + box.size.y * 0.75


func _on_wheel(node: Node, model: Node) -> bool:
	while node != null and node != model:
		if String(node.name).to_lower().begins_with("wheel"):
			return true
		node = node.get_parent()
	return false


## Pushes the body in round the hit (towards the middle of the car), with a
## little crumple, and darkens the paint there.
func _dent(local_pos: Vector3, amount: float, zone: int) -> void:
	var radius := 0.45 + amount * 1.2
	var depth := 0.06 + amount * 0.45
	var inward := Vector3(-local_pos.x, 0.0, -local_pos.z)
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.DOWN
	if zone == Zone.ROOF:
		inward = Vector3.DOWN
	else:
		# The collision box touches walls with its bottom edge: dent round
		# bumper / door height instead, where it shows.
		var h := _roof_y - _bottom_y
		local_pos.y = clampf(local_pos.y, _bottom_y + h * 0.4, _bottom_y + h * 0.7)
	for entry in _meshes:
		var mi: MeshInstance3D = entry.mi
		var to_mesh := (_car.global_transform.affine_inverse() * mi.global_transform).affine_inverse()
		var from_mesh := to_mesh.affine_inverse()
		var centre := to_mesh * local_pos
		var push := (to_mesh.basis * inward).normalized() * depth
		var mesh: ArrayMesh = entry.mesh
		var surfaces: Array = entry.surfaces
		var changed := false
		for s in surfaces.size():
			var arrays: Array = surfaces[s]
			var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var off: PackedVector3Array = entry.offsets[s]
			var tint: PackedFloat32Array = entry.tints[s]
			var bend: PackedVector3Array = entry.bends[s]
			var moved := false
			for i in base.size():
				var d := base[i].distance_to(centre)
				if d >= radius:
					continue
				var w := 1.0 - d / radius
				w *= w
				# Smooth crumple from the car-space position, so the livery (just
				# on top of the body) crumples the same way and never tears.
				var p := from_mesh * base[i]
				var crumple := 1.0 + 0.35 * sin(p.x * 9.0 + p.z * 3.0) * sin(p.y * 11.0) * sin(p.z * 7.0 - p.x * 2.0)
				var o := off[i] + push * w * crumple
				if o.length() > MAX_DENT:
					o = o.normalized() * MAX_DENT
				off[i] = o
				# Crinkled metal catches the light: tilt the shading normals.
				bend[i] += Vector3(sin(p.y * 13.0 + p.z * 5.0), sin(p.z * 11.0 + p.x * 7.0),
						sin(p.x * 9.0 + p.y * 6.0)) * w * amount * 1.6
				tint[i] = maxf(tint[i] - (1.0 - d / radius) * amount * 2.4, 0.3)
				moved = true
			if moved:
				entry.offsets[s] = off
				entry.tints[s] = tint
				entry.bends[s] = bend
				changed = true
		if changed:
			_rebuild(entry)


func _rebuild(entry: Dictionary) -> void:
	var mesh: ArrayMesh = entry.mesh
	var mats: Array[Material] = []
	for s in mesh.get_surface_count():
		mats.append(mesh.surface_get_material(s))
	mesh.clear_surfaces()
	var surfaces: Array = entry.surfaces
	for s in surfaces.size():
		var arrays: Array = (surfaces[s] as Array).duplicate()
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var off: PackedVector3Array = entry.offsets[s]
		var tint: PackedFloat32Array = entry.tints[s]
		var bend: PackedVector3Array = entry.bends[s]
		var base_normals = arrays[Mesh.ARRAY_NORMAL]
		var normals := PackedVector3Array()
		if base_normals != null:
			normals.resize(base.size())
		var verts := PackedVector3Array()
		verts.resize(base.size())
		var colors := PackedColorArray()
		colors.resize(base.size())
		for i in base.size():
			verts[i] = base[i] + off[i]
			var c := base_colors[i]
			colors[i] = Color(c.r * tint[i], c.g * tint[i], c.b * tint[i], c.a)
			if base_normals != null:
				normals[i] = (base_normals[i] + bend[i]).normalized()
		if base_normals != null:
			arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, mats[s])
	# The look (PS1 / PS2) sets per-surface materials: put them back.
	_car.set_retro_level(RetroLook.level)


# --- particles -----------------------------------------------------------------------

static var _dot: Texture2D

## A soft round blob (shared by every car's sparks and smoke).
static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_dot = t
	return _dot


func _make_particles() -> void:
	_sparks = _particles(Color(1.0, 0.75, 0.3), 3.0)
	_sparks.amount = 40
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 8.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	_debris = _particles(Color(0.15, 0.15, 0.17), 0.0, true)
	_debris.amount = 16
	_debris.lifetime = 1.2
	_debris.one_shot = true
	_debris.explosiveness = 1.0
	_debris.emitting = false
	_debris.direction = Vector3.UP
	_debris.spread = 80.0
	_debris.initial_velocity_min = 2.0
	_debris.initial_velocity_max = 6.0
	_smoke = _particles(Color(0.5, 0.5, 0.5, 0.6), 0.0, false, 0.3)
	_smoke.top_level = false  # rides on the car (bonnet); the puffs stay behind
	_smoke.position = Vector3(0.0, lerpf(_bottom_y, _roof_y, 0.7), -_half_length * 0.65)
	_smoke.amount = 24
	_smoke.lifetime = 1.6
	_smoke.direction = Vector3.UP
	_smoke.spread = 15.0
	_smoke.gravity = Vector3(0.0, 1.2, 0.0)
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.4
	_smoke.scale_amount_min = 1.0
	_smoke.scale_amount_max = 1.8
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.2))
	_smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_smoke.color_ramp = fade


func _particles(color: Color, glow: float, chunks: bool = false, size: float = 0.06) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.top_level = true
	p.local_coords = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if not chunks else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.vertex_color_use_as_albedo = true
	if not chunks:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = _soft_dot()
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	var mesh: Mesh
	if chunks:
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.04, 0.1)
		mesh = box
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		mesh = quad
	mesh.surface_set_material(0, mat)
	p.mesh = mesh
	p.color = color
	add_child(p)
	return p
