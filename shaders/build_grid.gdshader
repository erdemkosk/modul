shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// The build screen's floor under the machine: its grid of 0.5 m cells (in the machine's own frame,
// so the lines are where parts can go), a heavier line every metre and a half, fading out round it;
// the machine's footprint lit a little.

uniform vec4 line : source_color = vec4(0.5, 0.82, 1.0, 0.55);
uniform vec4 major : source_color = vec4(1.0, 0.75, 0.35, 0.7);
uniform float cell = 0.5;
uniform float radius = 9.0;
uniform vec2 foot_lo = vec2(-1.0);
uniform vec2 foot_hi = vec2(1.0);

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float grid(vec2 p, float step, float width) {
	vec2 g = abs(fract(p / step - 0.5) - 0.5) * step;
	vec2 w = fwidth(p) * width;
	vec2 a = 1.0 - smoothstep(vec2(0.0), w, g);
	return max(a.x, a.y);
}

void fragment() {
	vec2 p = local.xz;
	float fine = grid(p, cell, 1.0);
	float big = grid(p, cell * 6.0, 1.6);
	float fade = 1.0 - smoothstep(radius * 0.45, radius, length(p));
	vec2 inside = step(foot_lo, p) * step(p, foot_hi);
	float foot = inside.x * inside.y;
	vec4 c = mix(line, major, big);
	float a = max(fine * line.a, big * major.a) * fade + foot * 0.12 * fade;
	ALBEDO = mix(c.rgb, vec3(1.0, 0.8, 0.45), foot * (1.0 - fine) * 0.6);
	ALPHA = clamp(a, 0.0, 1.0);
}
