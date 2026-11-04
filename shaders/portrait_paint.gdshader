shader_type canvas_item;

// A villager's portrait, the little studio's picture made a painted one: brushed flat in patches (a
// Kuwahara filter: each pixel takes the calmest of the four squares round it), warmed, laid on a
// brown ground that darkens to the corners, a canvas weave over it.

uniform sampler2D src : filter_linear, repeat_disable;
uniform int radius = 3;
uniform vec3 ground_lit = vec3(0.56, 0.45, 0.31);
uniform vec3 ground_dark = vec3(0.19, 0.14, 0.1);

vec4 square(vec2 uv, vec2 px, int x0, int x1, int y0, int y1, out float spread) {
	vec4 sum = vec4(0.0);
	vec3 sq = vec3(0.0);
	float n = 0.0;
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			vec4 c = texture(src, uv + vec2(float(x), float(y)) * px);
			sum += c;
			sq += c.rgb * c.rgb;
			n += 1.0;
		}
	}
	vec3 mean = sum.rgb / n;
	vec3 v = sq / n - mean * mean;
	spread = v.r + v.g + v.b;
	return sum / n;
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(src, 0));
	float best = 1e9;
	vec4 col = vec4(0.0);
	for (int q = 0; q < 4; q++) {
		int x0 = q % 2 == 0 ? -radius : 0;
		int y0 = q < 2 ? -radius : 0;
		float s;
		vec4 c = square(UV, px, x0, x0 + radius, y0, y0 + radius, s);
		if (s < best) {
			best = s;
			col = c;
		}
	}
	vec3 paint = col.a > 0.001 ? col.rgb / col.a : vec3(0.0);
	float grey = dot(paint, vec3(0.3, 0.59, 0.11));
	paint = mix(vec3(grey), paint, 0.82) * vec3(1.06, 0.99, 0.88);
	paint = smoothstep(vec3(0.03), vec3(0.95), paint);
	// the ground: lit from the upper left behind the head, brushed unevenly
	float d = length((UV - vec2(0.42, 0.34)) * vec2(1.0, 0.9));
	float brush = sin(UV.x * 31.0 + UV.y * 17.0 + 2.0 * sin(UV.y * 11.0)) * 0.5 + sin(UV.x * 7.0 - UV.y * 13.0) * 0.5;
	vec3 ground = mix(ground_lit, ground_dark, smoothstep(0.1, 0.72, d + brush * 0.035));
	vec3 c = mix(ground, paint, smoothstep(0.1, 0.9, col.a));
	// the corners darker, the canvas's weave
	float edge = length((UV - 0.5) * vec2(1.05, 0.95));
	c *= 1.0 - smoothstep(0.42, 0.78, edge) * 0.5;
	vec2 w = fract(UV * vec2(textureSize(src, 0)) / 2.5);
	c *= 0.97 + 0.03 * step(0.5, w.x) * step(0.5, w.y) + 0.015 * step(0.5, w.x);
	COLOR = vec4(c, 1.0);
}
