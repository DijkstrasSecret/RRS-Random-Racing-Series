shader_type canvas_item;
// PS1/PS2 look for a small 3D preview drawn into the UI (the car select
// showroom): the preview already renders at low resolution; this reduces
// the colours with ordered dithering, like the in-game screen effect.

uniform float color_levels = 32.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE);
	int idx = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float t = (BAYER[idx] + 0.5) / 16.0 - 0.5;
	float steps = color_levels - 1.0;
	c.rgb = clamp(floor(c.rgb * steps + 0.5 + t * dither_strength) / steps, 0.0, 1.0);
	COLOR = c;
}
