shader_type spatial;
render_mode unshaded, fog_disabled;
// A stadium's LED screen: what's drawn into `screen` (a SubViewport) shown as a grid of round
// diodes, each lit by the colour at its middle, the black between them; faintly lit when off.

uniform sampler2D screen : source_color, filter_linear;
uniform vec2 cells = vec2(256.0, 100.0);
uniform float energy = 2.2;

void fragment() {
	vec2 g = UV * cells;
	vec2 mid = (floor(g) + 0.5) / cells;
	vec3 c = texture(screen, mid).rgb;
	float d = length(fract(g) - 0.5);
	float dot_ = 1.0 - smoothstep(0.32, 0.46, d);
	ALBEDO = vec3(0.012, 0.014, 0.018) + c * dot_ * energy;
}
