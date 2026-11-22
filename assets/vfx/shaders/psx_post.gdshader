shader_type canvas_item;
// Retro screen effect: low internal resolution, reduced colour depth and
// ordered (Bayer) dithering, like PS1/PS2-era output.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 virtual_resolution = vec2(426.0, 240.0);
// Levels per colour channel (32 = PS1 15-bit colour).
uniform float color_levels = 32.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 cell = floor(SCREEN_UV * virtual_resolution);
	vec2 uv = (cell + 0.5) / virtual_resolution;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	int idx = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float threshold = (BAYER[idx] + 0.5) / 16.0 - 0.5;
	float steps = color_levels - 1.0;
	c = floor(c * steps + 0.5 + threshold * dither_strength) / steps;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
