class_name CarLook
extends RefCounted
## Gives a car model (as imported, no Vehicle) the in-game PS1 look: the
## wobbly vertex-snapped, affine-textured material, glowing lamps and glossy
## paint / glass / chrome. Used by the garage / car select previews and the
## car portraits, so they match how the cars look in a race.

const PSX_SHADER := preload("res://assets/vfx/shaders/psx_lit.gdshader")


## Swaps every surface of `model` to the PS1 material. `snap_resolution`
## is the virtual screen size the vertices snap to (smaller = more wobble).
static func apply_retro(model: Node, snap_resolution: Vector2) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = PSX_SHADER
			mat.set_shader_parameter("albedo_tex", base.albedo_texture)
			mat.set_shader_parameter("albedo_color", base.albedo_color)
			mat.set_shader_parameter("snap_resolution", snap_resolution)
			var mat_name := base.resource_name.to_lower()
			if base.emission_enabled:
				mat.set_shader_parameter("emission_color", base.emission)
				mat.set_shader_parameter("emission_energy", 3.0 if mat_name.contains("headlight") else 1.6)
			var rough := -1.0
			var metal := 0.0
			if mat_name.contains("paint"):
				rough = 0.3
				metal = 0.35
			elif mat_name.contains("glass"):
				rough = 0.08
				metal = 0.55
			elif mat_name.contains("chrome") or mat_name.contains("silver"):
				rough = 0.18
				metal = 0.9
			if rough >= 0.0:
				mat.set_shader_parameter("roughness_value", rough)
				mat.set_shader_parameter("metallic_value", metal)
				mat.set_shader_parameter("specular_value", 0.6)
			mi.set_surface_override_material(i, mat)
