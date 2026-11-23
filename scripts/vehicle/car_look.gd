class_name CarLook
extends RefCounted
## Gives a car model (as imported, no Vehicle) the in-game PS1 look: the
## wobbly vertex-snapped, affine-textured material, glowing lamps and glossy
## paint / glass / chrome. Used by the garage / car select previews and the
## car portraits, so they match how the cars look in a race.

const PSX_SHADER := preload("res://assets/vfx/shaders/psx_lit.gdshader")
## How far (m) livery decals are pulled towards the camera so the PS1 vertex
## snapping can't push the body through them.
const LIVERY_PULL := 0.04


const PSX_DECAL_SHADER := preload("res://assets/vfx/shaders/psx_decal.gdshader")


## Turns a PS1 material into the decal version (for liveries): it keeps its
## settings, and gets the depth offset so the body can't poke through.
static func make_decal(mat: ShaderMaterial) -> void:
	mat.shader = PSX_DECAL_SHADER
	mat.set_shader_parameter("depth_pull", LIVERY_PULL)


## The model's baked shading texture (<model>_shade.png next to the .glb), or null.
static func shade_texture(model: Node) -> Texture2D:
	if model == null or model.scene_file_path == "":
		return null
	var path := model.scene_file_path.get_basename() + "_shade.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Paint a little muted and deeper, like a PS1 palette (liveries stay bright).
static func grade_paint(c: Color) -> Color:
	var g := Color.from_hsv(c.h, c.s * 0.85, c.v * 0.86, c.a)
	return g


## Body surfaces get the baked shading (strength SHADE_AMOUNT).
const SHADE_AMOUNT := 1.0

static func apply_shade(mat: ShaderMaterial, mi: MeshInstance3D, shade: Texture2D) -> void:
	if shade and String(mi.name).begins_with("body"):
		mat.set_shader_parameter("shade_tex", shade)
		mat.set_shader_parameter("shade_amount", SHADE_AMOUNT)


## Swaps every surface of `model` to the PS1 material. `snap_resolution`
## is the virtual screen size the vertices snap to (smaller = more wobble).
static func apply_retro(model: Node, snap_resolution: Vector2) -> void:
	var shade := shade_texture(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = PSX_DECAL_SHADER if (String(mi.name).begins_with("livery") or String(mi.get_parent().name).begins_with("livery")) else PSX_SHADER
			mat.set_shader_parameter("albedo_tex", base.albedo_texture)
			var paint := base.resource_name.to_lower().contains("paint")
			mat.set_shader_parameter("albedo_color", grade_paint(base.albedo_color) if paint else base.albedo_color)
			mat.set_shader_parameter("snap_resolution", snap_resolution)
			apply_shade(mat, mi, shade)
			if String(mi.name).begins_with("livery") or String(mi.get_parent().name).begins_with("livery"):
				make_decal(mat)
			var mat_name := base.resource_name.to_lower()
			if base.emission_enabled:
				mat.set_shader_parameter("emission_color", base.emission)
				mat.set_shader_parameter("emission_energy", 0.6 if mat_name.contains("headlight") else 0.5)
			var rough := -1.0
			var metal := 0.0
			if mat_name.contains("paint"):
				rough = 0.5
				metal = 0.15
			elif mat_name.contains("glass"):
				rough = 0.25
				metal = 0.15
			elif mat_name.contains("chrome") or mat_name.contains("silver"):
				rough = 0.18
				metal = 0.9
			if rough >= 0.0:
				mat.set_shader_parameter("roughness_value", rough)
				mat.set_shader_parameter("metallic_value", metal)
				mat.set_shader_parameter("specular_value", 0.6)
			mi.set_surface_override_material(i, mat)
