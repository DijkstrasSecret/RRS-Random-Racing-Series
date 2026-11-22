// Cloud cover as a sum of waves that repeats every `field_size` metres, so
// clouds can drift forever and wrap around. TrackAtmosphere uses the exact
// same formula (cloud_density) to place the cloud puffs, and the screen
// effect uses it for the shadows, so shadows line up with the clouds.

const vec4 CLOUD_WAVES[8] = vec4[8](
	vec4(9.0, 4.0, 0.30, 0.3), vec4(5.0, -11.0, 0.26, 1.7),
	vec4(-13.0, 6.0, 0.22, 4.1), vec4(14.0, 9.0, 0.18, 2.2),
	vec4(3.0, -17.0, 0.15, 5.0), vec4(19.0, -7.0, 0.12, 0.9),
	vec4(-8.0, -15.0, 0.10, 3.3), vec4(22.0, 13.0, 0.08, 1.1));

float cloud_density(vec2 p, float size, float threshold) {
	float f = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 w = CLOUD_WAVES[i];
		f += w.z * sin(6.2831853 * (w.x * p.x + w.y * p.y) / size + w.w);
	}
	f /= 1.41;
	return smoothstep(threshold, threshold + 0.35, f);
}
