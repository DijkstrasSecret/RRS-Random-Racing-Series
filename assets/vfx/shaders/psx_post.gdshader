shader_type canvas_item;
// Retro screen effect: low internal resolution, reduced colour depth and
// ordered (Bayer) dithering. PS1 = sharp blocky pixels; PS2 = the same low
// resolution blended smoothly (the soft, slightly blurry PS2 picture).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 virtual_resolution = vec2(640.0, 360.0);
// Levels per colour channel (32 = PS1 15-bit colour).
uniform float color_levels = 48.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;
// 0 = blocky pixels (PS1), 1 = smooth bilinear upscale (PS2).
uniform float smooth_upscale : hint_range(0.0, 1.0) = 1.0;
// Gentle barrel lens (0 = flat). Edges are pulled in a little.
uniform float fisheye : hint_range(0.0, 0.4) = 0.0;
// 0..1: blur streaking out from the centre towards the edges (speed).
uniform float speed_blur : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

// Colour of one low-resolution pixel, quantised and dithered.
vec2 lens(vec2 uv) {
	if (fisheye <= 0.0) {
		return uv;
	}
	vec2 d = uv - 0.5;
	d.x *= aspect;
	float r2 = dot(d, d);
	// Barrel: sample further out the further from the centre, scaled so the
	// corners still reach the corners.
	float corner = 0.25 * (aspect * aspect + 1.0);
	float k = (1.0 + fisheye * r2) / (1.0 + fisheye * corner);
	d *= k;
	d.x /= aspect;
	return d + 0.5;
}

vec3 sample_scene(vec2 uv) {
	uv = lens(uv);
	vec3 c = textureLod(screen_tex, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
	if (speed_blur > 0.0) {
		vec2 d = uv - 0.5;
		float edge = smoothstep(0.12, 0.5, length(d * vec2(aspect, 1.0)) / aspect * 1.4);
		float amount = speed_blur * edge * 0.035;
		if (amount > 0.0005) {
			vec3 acc = c;
			for (int k = 1; k <= 4; k++) {
				acc += textureLod(screen_tex, clamp(uv - d * amount * float(k), vec2(0.0), vec2(1.0)), 0.0).rgb;
			}
			c = acc / 5.0;
		}
	}
	return c;
}

vec3 cell_color(vec2 cell) {
	vec2 uv = (cell + 0.5) / virtual_resolution;
	vec3 c = sample_scene(uv);
	int idx = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float threshold = (BAYER[idx] + 0.5) / 16.0 - 0.5;
	float steps = color_levels - 1.0;
	return clamp(floor(c * steps + 0.5 + threshold * dither_strength) / steps, 0.0, 1.0);
}

void fragment() {
	vec2 p = SCREEN_UV * virtual_resolution;
	vec3 blocky = cell_color(floor(p));
	vec3 c = blocky;
	if (smooth_upscale > 0.0) {
		vec2 q = p - 0.5;
		vec2 i = floor(q);
		vec2 f = fract(q);
		vec3 smooth_c = mix(
			mix(cell_color(i), cell_color(i + vec2(1.0, 0.0)), f.x),
			mix(cell_color(i + vec2(0.0, 1.0)), cell_color(i + vec2(1.0, 1.0)), f.x),
			f.y);
		c = mix(blocky, smooth_c, smooth_upscale);
	}
	COLOR = vec4(c, 1.0);
}
