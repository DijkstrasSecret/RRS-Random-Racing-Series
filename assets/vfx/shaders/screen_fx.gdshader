shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Full-screen atmosphere pass (drawn by every camera that sees the track):
//  - cloud shadows drifting over the ground (same cloud field as the puffs)
//  - god rays streaming from the sun when it peeks past things
//  - sun glare and a retro lens flare when looking towards the sun
// It reads the finished opaque image and the depth buffer.

#include "res://assets/vfx/shaders/cloud_field.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float shadow_strength = 0.35;
uniform float cloud_height = 260.0;
uniform float cloud_threshold = 0.3;
uniform vec2 wind = vec2(4.0, 1.5);
uniform float field_size = 3000.0;
uniform float ray_strength = 0.5;
uniform float flare_strength = 0.4;
uniform float glare_strength = 0.25;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float is_sky(vec2 uv) {
	return texture(depth_tex, clamp(uv, vec2(0.001), vec2(0.999))).r < 0.000001 ? 1.0 : 0.0;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	float depth = texture(depth_tex, uv).r;
	vec3 s = normalize(sun_dir);

	// --- Cloud shadows on everything that isn't sky.
	if (depth > 0.000001 && shadow_strength > 0.0) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth, 1.0);
		view.xyz /= view.w;
		vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
		float t = (cloud_height - world.y) / max(s.y, 0.08);
		vec2 above = world.xz + s.xz * t - wind * TIME;
		float shade = cloud_density(above, field_size, cloud_threshold);
		col *= 1.0 - shade * shadow_strength;
	}

	// --- Where is the sun on screen?
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(cam + s * 1000.0, 1.0);
	vec3 fwd = -normalize(INV_VIEW_MATRIX[2].xyz);
	float facing = clamp(dot(fwd, s), 0.0, 1.0);
	if (clip.w > 0.0 && facing > 0.0) {
		vec2 sun_uv = clip.xy / clip.w * 0.5 + 0.5;
		float on_screen = 1.0 - smoothstep(0.45, 0.85, length(sun_uv - 0.5));
		// God rays: march towards the sun, counting open sky along the way.
		if (ray_strength > 0.0) {
			vec2 delta = (sun_uv - uv) / 28.0;
			vec2 p = uv;
			float acc = 0.0;
			float decay = 1.0;
			for (int i = 0; i < 28; i++) {
				p += delta;
				acc += is_sky(p) * decay;
				decay *= 0.94;
			}
			// Strongest right around the sun, fading out over a third of the screen.
			float near_sun = pow(1.0 - clamp(length((sun_uv - uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0)) * 1.6, 0.0, 1.0), 3.0);
			col += sun_color * acc / 16.0 * near_sun * ray_strength * on_screen * facing;
		}
		// Flare and glare only when the sun itself is visible.
		float visible = 0.0;
		for (int i = 0; i < 5; i++) {
			vec2 o = vec2(float(i % 3) - 1.0, float(i / 3) - 0.5) * 0.006;
			visible += is_sky(sun_uv + o);
		}
		visible = visible / 5.0 * on_screen;
		if (visible > 0.0) {
			vec2 axis = vec2(0.5) - sun_uv;
			float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
			vec3 ghosts = vec3(0.0);
			vec4 G[5] = vec4[5](vec4(0.35, 0.025, 1.0, 0.6), vec4(0.7, 0.015, 0.6, 1.0),
				vec4(1.1, 0.04, 0.9, 0.5), vec4(1.45, 0.02, 0.5, 0.9), vec4(1.8, 0.055, 1.0, 0.8));
			for (int i = 0; i < 5; i++) {
				vec2 gp = sun_uv + axis * G[i].x;
				vec2 dd = (uv - gp) * vec2(aspect, 1.0);
				float ring = smoothstep(G[i].y, G[i].y * 0.7, length(dd));
				ghosts += ring * vec3(G[i].z, G[i].w, mix(G[i].z, G[i].w, 0.5)) * 0.18;
			}
			col += ghosts * sun_color * flare_strength * visible * facing;
			col += sun_color * glare_strength * visible * pow(facing, 24.0);
		}
	}
	ALBEDO = col;
}
