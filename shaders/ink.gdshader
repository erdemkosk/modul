// The HUD's drawings (tools/ink_icons.gd): a thing drawn in ink on paper, the way a town clerk would
// sketch it in the margin of the ledger. Light comes in a few flat steps, its shadows hatched with
// fine diagonal lines (finer where it's darker), its own colour washed thin over the paper. The
// outline is ink_outline.gdshader, drawn behind it.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 wash : source_color = vec3(0.6, 0.45, 0.3); // its own colour, a thin wash
uniform vec3 paper : source_color = vec3(0.93, 0.89, 0.8);
uniform vec3 ink : source_color = vec3(0.16, 0.12, 0.09);
uniform vec3 light_dir = vec3(-0.5, 0.8, 0.45);
uniform float hatch_scale = 34.0; // lines across the picture's height (few: it's shown small)

varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hatch(vec2 p, float angle, float width) {
	float c = cos(angle), s = sin(angle);
	float v = fract(dot(p, vec2(c, s)) * hatch_scale);
	return smoothstep(width, width + 0.08, abs(v - 0.5) * 2.0);
}

void fragment() {
	float lit = clamp(dot(normalize(wn), normalize(light_dir)), 0.0, 1.0);
	float step_lit = floor(lit * 3.0 + 0.5) / 3.0; // (three tones, flat)
	vec3 c = mix(paper, wash, 0.8) * mix(0.9, 1.08, step_lit);
	vec2 sp = SCREEN_UV * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	float shade = 1.0;
	if (step_lit < 0.5) shade *= mix(0.62, 1.0, hatch(sp, 0.785, 0.7)); // (one way, in the shade)
	if (step_lit < 0.2) shade *= mix(0.55, 1.0, hatch(sp, -0.785, 0.7)); // (crossed, in the dark)
	c = mix(ink, c, shade);
	ALBEDO = c;
}
