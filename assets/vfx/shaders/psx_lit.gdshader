shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// PS1-style surface: vertices snap to a low-resolution grid (the "wobble"),
// textures are mapped without perspective correction (affine warping) and
// sampled without filtering.

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 snap_resolution = vec2(426.0, 240.0);
uniform float snap_amount : hint_range(0.0, 1.0) = 1.0;
uniform float affine_amount : hint_range(0.0, 1.0) = 1.0;
// Shiny paint, glass and chrome reflect the sky and catch the sun.
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.0;
// Lamps (head / brake lights) glow; the car changes the energy live.
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// Crash damage darkens the paint through the vertex colours (1 = use them).
uniform float vertex_tint = 0.0;

varying vec2 affine_uv;
varying float affine_w;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 half_res = snap_resolution * 0.5;
	vec2 ndc = clip.xy / clip.w;
	vec2 snapped = round(ndc * half_res) / half_res;
	clip.xy = mix(ndc, snapped, snap_amount) * clip.w;
	POSITION = clip;
	affine_uv = UV * clip.w;
	affine_w = clip.w;
}

void fragment() {
	vec2 uv = mix(UV, affine_uv / affine_w, affine_amount);
	vec4 tex = texture(albedo_tex, uv);
	ALBEDO = tex.rgb * albedo_color.rgb * mix(vec3(1.0), COLOR.rgb, vertex_tint);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	EMISSION = emission_color * emission_energy;
	METALLIC = metallic_value;
}
