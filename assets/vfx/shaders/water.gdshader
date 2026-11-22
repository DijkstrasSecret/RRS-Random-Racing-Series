shader_type spatial;
render_mode unshaded, cull_disabled;
// Tropical sea: turquoise over the shallows, deep blue further out (from how
// much water lies between the surface and the sea bed), a white foam line at
// the shore and slow sparkle. Kept flat-shaded for the PS1 look.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.3, 0.86, 0.8);
uniform vec3 deep : source_color = vec3(0.05, 0.28, 0.5);
uniform vec3 foam : source_color = vec3(0.95, 0.97, 0.95);

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water = clamp(-view.z - (-VERTEX.z), 0.0, 50.0);
	vec3 col = mix(shallow, deep, smoothstep(0.6, 7.0, water));
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world.x * 0.08 + TIME * 0.9) * sin(world.z * 0.07 - TIME * 0.7);
	col = mix(col, foam, (1.0 - smoothstep(0.05, 0.35 + wave * 0.1, water)) * 0.85);
	vec2 cell = floor(world.xz * 2.5);
	float sparkle = step(0.997, hash(cell + floor(TIME * 3.0)));
	col += vec3(sparkle * 0.3) * (1.0 - smoothstep(15.0, 80.0, -VERTEX.z));
	ALBEDO = col;
}
