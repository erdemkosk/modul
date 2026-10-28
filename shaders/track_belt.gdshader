shader_type spatial;
// A track's belt (tools/blender/build_parts.py: build_belt): UV u says which face (outer, the tread:
// 0..0.45 across; inner: 0.55..1; the edges: 0.5), v runs along it in links. `scroll` (links) moves the
// links round as the track turns; each is a steel plate with a grouser bar across it outside, the
// guide horns and the road wheels' worn path inside, pins at the edges, mud packed in by `mud`.

instance uniform float scroll = 0.0;
instance uniform float mud = 0.0;

uniform vec3 steel : source_color = vec3(0.13, 0.125, 0.12);
uniform vec3 worn : source_color = vec3(0.42, 0.4, 0.37);
uniform vec3 dirt : source_color = vec3(0.2, 0.15, 0.1);

float band(float x, float a, float b, float soft) {
	return smoothstep(a - soft, a + soft, x) * (1.0 - smoothstep(b - soft, b + soft, x));
}

// height of the link surface (0 the gap, 1 the top of a grouser or horn) at l along a link, u across
float height(float l, float u) {
	if (u < 0.47) {
		float x = u / 0.45;
		float plate = band(l, 0.07, 0.95, 0.02) * 0.45;
		float grouser = band(l, 0.38, 0.6, 0.035) * band(x, 0.03, 0.97, 0.02);
		return max(plate, grouser);
	} else if (u > 0.53) {
		float x = (u - 0.55) / 0.45;
		float plate = band(l, 0.06, 0.96, 0.02) * 0.4;
		float horn = band(l, 0.3, 0.7, 0.05) * band(x, 0.44, 0.56, 0.02);
		return max(plate, horn);
	}
	float pin = 1.0 - smoothstep(0.08, 0.14, abs(l - 0.0) < 0.5 ? abs(l) : abs(l - 1.0));
	return 0.4 + pin * 0.5;
}

void fragment() {
	float v = UV.y + scroll;
	float l = fract(v);
	float u = UV.x;
	float h = height(l, u);
	float e = 0.02;
	float dl = (height(fract(v + e), u) - height(fract(v - e), u)) / (2.0 * e);
	float du = (height(l, u + 0.01) - height(l, u - 0.01)) / 0.02;
	NORMAL_MAP = normalize(vec3(-du * 0.04, -dl * 0.12, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	// worn bright where it bears: grouser tops outside, the wheels' path inside
	float wear = 0.0;
	if (u < 0.47) {
		wear = smoothstep(0.8, 1.0, h);
	} else if (u > 0.53) {
		float x = (u - 0.55) / 0.45;
		wear = (band(x, 0.08, 0.38, 0.03) + band(x, 0.62, 0.92, 0.03)) * step(0.3, h) * 0.7;
	}
	float grain = fract(sin(dot(floor(vec2(u * 40.0, v * 6.0)), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = mix(steel, worn, wear * (0.8 + 0.2 * grain));
	col *= mix(0.35, 1.0, smoothstep(0.0, 0.3, h)); // the gaps dark
	// mud: packed in the low places first, over all of it at the worst
	float m = clamp(mud * 1.6 - h * 0.9 + grain * 0.15, 0.0, 1.0) * (u > 0.53 ? 0.6 : 1.0);
	col = mix(col, dirt * (0.8 + 0.3 * grain), m);
	ALBEDO = col;
	METALLIC = mix(0.75, 0.0, m) * mix(0.6, 1.0, wear);
	ROUGHNESS = mix(mix(0.62, 0.35, wear), 0.9, m);
}
