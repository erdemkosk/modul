shader_type spatial;
// Soft round camera-facing snow flakes for scripts/weather.gd. Flakes keep at
// least ~1.5 px on screen far away and trade size for opacity there, so they
// don't sparkle.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float size = 0.055;
uniform vec3 tint : source_color = vec3(0.95, 0.97, 1.0);
uniform float brightness = 1.0; // scene light level, set by Weather
uniform float opacity = 0.85;
uniform float far_fade = 30.0;
uniform float near_fade = 0.7;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	float dist = distance(CAMERA_POSITION_WORLD, center);
	float want = size * sc;
	float s = max(want, dist * 0.0016);
	vec3 world = center + INV_VIEW_MATRIX[0].xyz * VERTEX.x * s + INV_VIEW_MATRIX[1].xyz * VERTEX.y * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	float shrink = want / s;
	v_fade = shrink * shrink * smoothstep(near_fade, near_fade * 3.0, dist) * (1.0 - smoothstep(far_fade * 0.7, far_fade, dist));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = tint * brightness * COLOR.rgb;
	ALPHA = clamp(opacity * smoothstep(1.0, 0.15, r) * v_fade * COLOR.a, 0.0, 1.0);
}
