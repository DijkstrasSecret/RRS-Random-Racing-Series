shader_type sky;
// Retro sky: a few colour bands from horizon to zenith, a glowing sun (or a
// pale moon) and stars at night. Kept simple so the PS1/PS2 screen effect
// gives it the right banded, dithered look.

uniform vec3 top_color : source_color = vec3(0.25, 0.45, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.8, 0.88);
uniform vec3 ground_color : source_color = vec3(0.3, 0.32, 0.3);
uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
// Angular size of the disc (cosine distance from the centre).
uniform float sun_size = 0.0012;
uniform float sun_glow = 0.6;
uniform float stars = 0.0;
uniform float moon = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(y, 0.0, 1.0), 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(-y * 6.0, 0.0, 1.0));
	}
	vec3 s = normalize(sun_dir);
	float c = dot(d, s);
	// Wide warm glow around the sun, brighter towards the horizon.
	float glow = pow(max(c, 0.0), 8.0) * 0.35 + pow(max(c, 0.0), 64.0) * 0.6;
	col += sun_color * glow * sun_glow * (1.0 - moon * 0.8);
	// The disc itself (HDR bright so the bloom and god rays pick it up).
	float disc = smoothstep(1.0 - sun_size * 1.4, 1.0 - sun_size, c);
	col = mix(col, sun_color * (moon > 0.5 ? 1.2 : 4.0), disc);
	if (stars > 0.0 && y > 0.0) {
		vec3 cell = floor(d * 160.0);
		float h = hash(cell.xz + cell.y * 17.31);
		float twinkle = 0.7 + 0.3 * sin(TIME * 2.0 + h * 40.0);
		col += vec3(step(0.996, h) * stars * twinkle * smoothstep(0.0, 0.25, y));
	}
	COLOR = col;
}
