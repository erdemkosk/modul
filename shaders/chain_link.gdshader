shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// The catch fence over the arena wall: galvanised chain-link drawn from its UVs (u round the ring,
// v up it), the wires anti-aliased and, far off where they'd shimmer, a faint grey haze instead.

uniform float around = 580.0; // m round the ring
uniform float height = 3.2; // m
uniform float mesh_size = 0.07; // m between wires
uniform vec3 wire : source_color = vec3(0.6, 0.62, 0.62);

void fragment() {
	vec2 p = vec2(UV.x * around, UV.y * height) / mesh_size;
	// diamonds: two sets of diagonals
	vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	vec2 g = abs(fract(d) - 0.5);
	vec2 w = fwidth(d) * 1.2;
	float a = max(1.0 - smoothstep(0.42 - w.x, 0.5, 0.5 - g.x) , 1.0 - smoothstep(0.42 - w.y, 0.5, 0.5 - g.y));
	float far = clamp(max(w.x, w.y) * 3.0, 0.0, 1.0);
	ALPHA = mix(a, 0.28, far);
	ALBEDO = wire;
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
}
