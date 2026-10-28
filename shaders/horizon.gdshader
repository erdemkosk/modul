shader_type spatial;
render_mode cull_disabled;

// The mountains beyond the map's edge (scripts/world_decor.gd, _build_horizon): kilometres
// away, so they are all colour and light. Dark forest climbs the lower slopes and thins out
// above the treeline; bare rock above it, scored by gullies running down the fall line; a
// snowline that is ragged, not a contour, with snow lying on ledges and filling the gullies
// higher up. Normals get broad detail so the faces catch the sun in ridges, not flat panels.

global uniform float weather_snow;

varying vec3 w_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (n.y < 0.0) {
		n = -n;
	}
	vec2 xz = w_pos.xz;
	float h = w_pos.y;
	// Ridges: bend the normal with noise at the scale of spurs and gullies (~100 m).
	float e = 25.0;
	float b0 = fbm(xz * 0.004);
	float bx = fbm((xz + vec2(e, 0.0)) * 0.004);
	float bz = fbm((xz + vec2(0.0, e)) * 0.004);
	n = normalize(n + vec3(b0 - bx, 0.0, b0 - bz) * 6.0);
	float slope = 1.0 - n.y;

	float mottle = fbm(xz * 0.002);
	float gully = smoothstep(0.5, 0.8, fbm(vec2(xz.x * 0.004 + n.x * 2.0, xz.y * 0.004 + n.z * 2.0) + h * 0.002));

	vec3 rock = mix(vec3(0.16, 0.155, 0.15), vec3(0.27, 0.25, 0.22), mottle);
	rock = mix(rock, vec3(0.2, 0.15, 0.11), smoothstep(0.55, 0.8, fbm(xz * 0.0013 + 9.0)) * 0.5);
	rock *= mix(1.0, 0.65, gully);
	// Forest below the treeline (which wanders), only where the slope lets trees stand.
	float treeline = 330.0 + (fbm(xz * 0.0011) - 0.5) * 160.0;
	float forest = (1.0 - smoothstep(treeline - 40.0, treeline + 40.0, h)) * (1.0 - smoothstep(0.3, 0.55, slope));
	forest *= smoothstep(0.2, 0.42, fbm(xz * 0.006 + 3.0) + 0.2);
	vec3 trees = mix(vec3(0.05, 0.085, 0.045), vec3(0.09, 0.12, 0.06), mottle);
	vec3 meadow = mix(vec3(0.17, 0.19, 0.09), vec3(0.24, 0.23, 0.12), mottle);
	vec3 low = mix(meadow, trees, forest);
	float bare = smoothstep(0.25, 0.5, slope) + smoothstep(treeline + 60.0, treeline + 160.0, h);
	vec3 c = mix(low, rock, clamp(bare, 0.0, 1.0));
	// Snow: a ragged line, lying on gentler ground and filling gullies above it.
	float line = 470.0 + (fbm(xz * 0.0016 + 5.0) - 0.5) * 180.0 - weather_snow * 250.0;
	float snow = smoothstep(line - 30.0, line + 50.0, h + gully * 60.0);
	snow *= smoothstep(0.75, 0.35, slope + (fbm(xz * 0.01) - 0.5) * 0.3);
	snow = max(snow, smoothstep(line + 150.0, line + 260.0, h) * 0.85);
	c = mix(c, vec3(0.78, 0.81, 0.86) * mix(0.9, 1.02, mottle), clamp(snow, 0.0, 1.0));

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.7, snow);
	SPECULAR = 0.3;
}
