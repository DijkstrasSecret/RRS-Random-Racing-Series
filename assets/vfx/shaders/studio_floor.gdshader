shader_type spatial;
render_mode unshaded, cull_disabled;
// Showroom floor: a glowing grid that fades into the dark around the stage.

uniform vec3 base_color : source_color = vec3(0.03, 0.035, 0.06);
uniform vec3 line_color : source_color = vec3(0.3, 0.6, 1.0);
uniform float cell = 1.6;
uniform float fade = 16.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / cell;
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.0001));
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float d = length(world_pos.xz);
	float near = 1.0 - smoothstep(3.5, fade, d);
	ALBEDO = base_color + line_color * line * near * 0.9;
}
