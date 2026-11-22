shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_back;
// Low-poly cloud puff (MultiMesh). Drifts with the wind and wraps round the
// cloud field, fades into the horizon colour with distance. Shaded by hand:
// bright on the sunny side, a darker belly underneath.

uniform vec2 wind = vec2(4.0, 1.5);
uniform vec2 field_origin = vec2(-1500.0);
uniform float field_size = 3000.0;
uniform vec3 lit_color : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.7, 0.74, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.8, 0.88);
uniform vec3 sun_dir = vec3(0.0, 0.5, -1.0);
uniform float fade_start = 700.0;
uniform float fade_end = 2600.0;

varying vec3 world_normal;
varying float dist;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 shifted = origin.xz + wind * TIME;
	vec2 wrapped = field_origin + mod(shifted - field_origin, field_size);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(wrapped.x - origin.x, 0.0, wrapped.y - origin.z);
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	dist = length(world - CAMERA_POSITION_WORLD);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float sun = clamp(dot(world_normal, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float up = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(shade_color, lit_color, clamp(sun * 0.6 + up * 0.5, 0.0, 1.0));
	col = mix(col, horizon_color, smoothstep(fade_start, fade_end, dist) * 0.9);
	ALBEDO = col;
}
