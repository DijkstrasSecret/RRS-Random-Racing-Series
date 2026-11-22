shader_type sky;
// Showroom backdrop: dark at the top, a coloured glow along the horizon.

uniform vec3 top_color : source_color = vec3(0.02, 0.025, 0.05);
uniform vec3 glow_color : source_color = vec3(0.2, 0.35, 0.6);

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(glow_color, top_color, smoothstep(-0.02, 0.45, y));
	c = mix(c, top_color * 0.5, smoothstep(0.0, -0.3, y));
	COLOR = c;
}
