shader_type sky;
// Retro sky: a few colour bands from horizon to zenith, a glowing sun (or a
// pale moon), stars at night, and a layer of soft stylised clouds.
//
// Clouds (the approach of stylised Godot sky shaders such as "Stylized Sky" /
// "fake volumetric" clouds): each view ray is projected onto a flat layer at
// cloud_height; cover = the same wave field that drives the cloud shadows on
// the ground (cloud_field.gdshaderinc) broken up by a few octaves of noise for
// fluffy edges. Light: a second look-up nudged towards the sun says how much
// cloud is between this spot and the sun (thicker = darker), plus a darker
// belly where the cloud is dense and a bright rim near the sun. The light is
// stepped into a few flat tones so it suits the PS1 / PS2 look.

#include "res://assets/vfx/shaders/cloud_field.gdshaderinc"

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

uniform float cloud_amount = 1.0;
uniform float cloud_height = 260.0;
uniform float cloud_threshold = 0.3;
uniform float field_size = 3000.0;
uniform vec2 wind = vec2(4.5, 1.6);
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.74, 0.82);
uniform float cloud_steps = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

// Raw cloud "thickness" at a spot on the cloud layer (wind already applied):
// the big wave field decides where the cloud banks are (and matches the
// shadows), domain-warped noise makes them clump into rounded cumulus heaps,
// smaller noise gives the puffy cauliflower edges.
float raw_cover(vec2 p) {
	float big = cloud_density(p, field_size, cloud_threshold);
	vec2 q = p * 0.0032;
	vec2 warp = vec2(fbm(q + vec2(3.1, 1.7)), fbm(q + vec2(8.3, 2.8)));
	float heaps = fbm(q + warp * 1.8);
	float puffs = fbm(p * 0.014);
	return big * 0.42 + heaps * 0.62 + puffs * 0.3 - 0.12;
}

// Cloud cover (0..1), crisp-edged.
float cover(vec2 p) {
	return smoothstep(0.5, 0.56, raw_cover(p));
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

	// --- Clouds
	if (cloud_amount > 0.0 && y > 0.01) {
		// A gently curved layer (like a dome) rather than a flat plane, so
		// clouds near the horizon stay big and round instead of thin streaks.
		// Straight up it matches the flat layer the cloud shadows use.
		float t = (cloud_height - POSITION.y) / (y * 0.82 + 0.18);
		vec2 p = POSITION.xz + d.xz * t - wind * TIME;
		float raw = raw_cover(p);
		float a = smoothstep(0.5, 0.56, raw);
		if (a > 0.001) {
			// How much cloud lies towards the sun from here (self-shadowing).
			vec2 towards = normalize(s.xz + vec2(0.0001)) * 110.0;
			float block = cover(p + towards) * 0.6 + cover(p + towards * 2.2) * 0.4;
			float light = clamp(1.0 - block * 0.9, 0.0, 1.0);
			light *= mix(1.0, 0.7, smoothstep(0.6, 0.85, raw));  // thick middle = darker belly
			// Cumulus look from below: the edge nearer to us (the bottom on
			// screen) is a flat, shaded base; the far edge (top) catches light.
			vec2 away = normalize(d.xz + vec2(0.0001)) * 90.0;
			float base = 1.0 - cover(p - away);
			float crown = 1.0 - cover(p + away);
			light = clamp(light * (1.0 - 0.45 * base) + 0.25 * crown, 0.0, 1.0);
			light = floor(light * cloud_steps + 0.5) / cloud_steps;  // flat retro tones
			vec3 cloud = mix(cloud_shade, cloud_lit, light);
			// Bright rim on thin edges near the sun.
			float rim = pow(max(c, 0.0), 6.0) * (1.0 - a) * 1.4;
			cloud += sun_color * rim * (1.0 - moon);
			// Far away the layer melts into the horizon haze.
			float far = smoothstep(1000.0, 1500.0, t);
			cloud = mix(cloud, horizon_color, far * 0.85);
			a *= cloud_amount * (1.0 - smoothstep(0.55, 1.0, far)) * smoothstep(0.01, 0.06, y);
			col = mix(col, cloud, clamp(a, 0.0, 1.0) * (1.0 - disc * 0.0));
		}
	}
	COLOR = col;
}
