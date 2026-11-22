shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
// Cumulus puff (one quad of a MultiMesh cloud cluster), always facing the
// camera. Soft round shape with a wobbly edge, cut out with an ordered dither
// (PS1 style, and no transparency sorting). Shaded by hand like a cel-shaded
// cloud: lit on top and on the sun side, a flat darker belly underneath, a
// few flat tones. Drifts with the wind and wraps round the cloud field.
// INSTANCE_CUSTOM.r = height of this puff in its cluster (0 base .. 1 top),
// INSTANCE_CUSTOM.g = small brightness variation.

uniform vec2 wind = vec2(4.0, 1.5);
uniform vec2 field_origin = vec2(-1500.0);
uniform float field_size = 3000.0;
uniform vec3 lit_color : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.6, 0.65, 0.76);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.8, 0.88);
uniform vec3 sun_dir = vec3(0.0, 0.5, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float fade_start = 900.0;
uniform float fade_end = 2600.0;
uniform float tones = 3.0;
uniform float rim = 0.5;  // sun glow round thin edges (0 at night)

varying float dist;
varying vec3 cam_right;
varying float rel_h;
varying float tint;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec2 shifted = origin.xz + wind * TIME;
	vec2 wrapped = field_origin + mod(shifted - field_origin, field_size);
	vec3 centre = vec3(wrapped.x, origin.y, wrapped.y);
	cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 world = centre + (cam_right * VERTEX.x + cam_up * VERTEX.y) * size;
	dist = length(centre - CAMERA_POSITION_WORLD);
	rel_h = INSTANCE_CUSTOM.r;
	tint = INSTANCE_CUSTOM.g;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	// Wobbly round outline so overlapping puffs read as a billowy heap.
	float ang = atan(q.y, q.x);
	float edge = 0.86 + 0.08 * sin(ang * 5.0 + tint * 20.0) + 0.05 * sin(ang * 9.0 + tint * 7.0);
	float a = 1.0 - smoothstep(edge - 0.18, edge, r);
	a *= 1.0 - smoothstep(fade_start, fade_end, dist);
	if (a < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 s = normalize(sun_dir);
	// Up the puff = brighter; the side facing the sun brighter still.
	float up = clamp((1.0 - UV.y) * 0.55 + rel_h * 0.6, 0.0, 1.0);
	float side = clamp(0.5 + q.x * dot(cam_right, s) * 0.6, 0.0, 1.0);
	float light = clamp(up * 0.75 + side * 0.4 - 0.15 + tint * 0.1, 0.0, 1.0);
	light = floor(light * tones + 0.5) / tones;
	vec3 col = mix(shade_color, lit_color, light);
	// Thin edges glow when the sun is behind the cloud.
	float behind = max(dot(normalize(CAMERA_POSITION_WORLD - (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz), -s), 0.0);
	col += sun_color * smoothstep(0.5, 0.95, r) * pow(behind, 4.0) * rim;
	col = mix(col, horizon_color, smoothstep(fade_start * 0.6, fade_end, dist) * 0.75);
	ALBEDO = col;
}
