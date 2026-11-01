shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled;

// A flame (FireFx.flames, embers): each particle a tongue of fire, wide and white-hot at the foot,
// licking up to a ragged tip, boiling with noise that streams upward; it burns away from its edges
// as it ages (the colour ramp cools it meanwhile). Brighter than white, so the glow catches it.

#include "res://shaders/particle_common.gdshaderinc"

uniform float energy = 1.5;
uniform float tongue = 1.0; // 1 a tongue of flame; 0 a round spark
uniform float soft = 0.5;

varying float v_life;
varying float v_seed;

void vertex() {
	p_billboard(MODELVIEW_MATRIX, MODEL_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, 0.0);
	v_life = INSTANCE_CUSTOM.y;
	v_seed = p_hash(vec2(float(INSTANCE_ID), 3.1));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float h = 1.0 - UV.y; // 0 the foot, 1 the tip
	float n = p_fbm(vec2(uv.x * 1.8 + v_seed * 13.0, h * 1.6 - TIME * 2.6 - v_seed * 5.0));
	float x = uv.x + (n - 0.5) * 0.55 * h; // the tongue flickers more toward its tip
	float width = mix(0.85, 0.08, pow(h, 0.8));
	float flame = (1.0 - smoothstep(width * 0.2, width, abs(x))) * smoothstep(0.0, 0.25, h) * (1.0 - smoothstep(0.35, 0.9, h + (n - 0.5) * 0.5));
	flame *= 1.0 - smoothstep(0.7, 1.0, length(uv * vec2(1.0, 0.8))); // (never out to the quad's edge)
	float spark = 1.0 - smoothstep(0.0, 1.0, length(uv));
	float shape = mix(spark, flame, tongue);
	float heat = clamp((shape * (0.35 + 1.0 * n) - v_life * 0.55) * 1.8, 0.0, 1.0);
	vec3 hot = mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.36, 0.04), smoothstep(0.0, 0.45, heat));
	hot = mix(hot, vec3(1.0, 0.78, 0.4), smoothstep(0.7, 1.0, heat));
	float fade = heat * COLOR.a * p_soft(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX, soft);
	ALBEDO = hot * COLOR.rgb * fade * energy;
}
