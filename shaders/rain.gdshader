shader_type spatial;
// Rain streaks for scripts/weather.gd. Each GPU particle is a quad that is
// stretched along the particle's velocity (ParticleProcessMaterial
// particle_flag_align_y puts velocity in the Y axis) and turned to face the
// camera around that axis. Streaks widen with distance instead of shrinking
// below a pixel, and fade out near the camera and toward the box edge.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float streak_length = 0.9;
uniform float streak_width = 0.013;
uniform vec3 tint : source_color = vec3(0.78, 0.82, 0.88);
uniform float brightness = 1.0; // scene light level, set by Weather
uniform float opacity = 0.32;
uniform float far_fade = 24.0;

varying float v_fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 yaxis = MODEL_MATRIX[1].xyz;
	float sc = max(length(yaxis), 0.001);
	vec3 axis = yaxis / sc;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float dist = max(length(to_cam), 0.001);
	vec3 side = cross(axis, to_cam / dist);
	side /= max(length(side), 0.001);
	float w = max(streak_width, dist * 0.0011);
	vec3 world = center + side * VERTEX.x * w + axis * VERTEX.y * streak_length * sc;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	v_fade = (streak_width / w) * smoothstep(0.5, 2.0, dist) * (1.0 - smoothstep(far_fade * 0.7, far_fade, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = mix(1.0, 0.25, UV.y);
	ALBEDO = tint * brightness;
	ALPHA = clamp(opacity * across * across * along * v_fade * COLOR.a, 0.0, 1.0);
}
