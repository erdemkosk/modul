shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Smoke (FireFx.smoke: a burning building, a chimney): each particle a ragged billow that turns
// slowly and thins away from its edges as it spreads. It's lit like anything else (a rounded
// normal, so the sun picks out its top and the fire below lights it from under), grey in the day,
// dark at night; it fades where it meets the ground or a roof.

#include "res://shaders/particle_common.gdshaderinc"

uniform float soft = 1.2;
uniform float glow_below = 0.0; // the fire's light on its underside (a burning building's smoke)

varying float v_life;
varying float v_seed;

void vertex() {
	p_billboard(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, INSTANCE_CUSTOM.x);
	v_life = INSTANCE_CUSTOM.y;
	v_seed = p_hash(vec2(float(INSTANCE_ID), 7.7));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float n = p_fbm(uv * 1.7 + vec2(v_seed * 17.0, v_seed * 5.0 - TIME * 0.12));
	float body = (1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.7)) * (1.0 - smoothstep(0.7, 0.98, r)); // (never out to the quad's edge)
	float a = clamp((body * (0.6 + 0.7 * n) - v_life * 0.35) * 1.8, 0.0, 1.0);
	ALPHA = a * COLOR.a * p_soft(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, soft);
	ALBEDO = COLOR.rgb * mix(0.8, 1.1, n);
	NORMAL = normalize(vec3(uv.x, -uv.y, 1.0 - r * 0.6)); // (a ball facing the view)
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = COLOR.rgb * 0.5;
	EMISSION = vec3(1.0, 0.38, 0.1) * glow_below * smoothstep(0.2, -0.8, uv.y) * a * (1.0 - v_life);
}
