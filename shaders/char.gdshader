// A burnt piece (scripts/building.gd material "char"): charcoal, not one flat black. Deep black where
// it burnt through, crazed into the blocks wood chars into; grey-white ash lying on what faces up and
// in drifts; a few cracks still holding a dull red glow. Wet darkens it, snow lies on it.
shader_type spatial;
render_mode diffuse_burley;

global uniform float weather_snow;
global uniform float weather_wetness;

uniform float glow = 0.25; // the embers' brightness in the cracks

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = clamp(wn.y, 0.0, 1.0);
	// the alligator cracking: cells of char with dark seams between them
	vec3 q = wp * vec3(9.0, 4.5, 9.0);
	float cell = vnoise(q);
	float seam = 1.0 - smoothstep(0.04, 0.12, abs(fract(cell * 3.0) - 0.5));
	float broad = vnoise(wp * 1.3) * 0.6 + vnoise(wp * 5.0) * 0.4;
	vec3 c = mix(vec3(0.055, 0.05, 0.045), vec3(0.12, 0.11, 0.1), broad);
	c *= 1.0 - seam * 0.6;
	// ash: on the tops, and in pale drifts
	float ash = clamp(up * 0.7 + smoothstep(0.62, 0.85, broad) * 0.6, 0.0, 1.0) * smoothstep(0.3, 0.7, vnoise(wp * 3.1 + 7.0));
	c = mix(c, vec3(0.5, 0.48, 0.45), ash * 0.7);
	// the embers: in the seams, here and there
	float hot = seam * smoothstep(0.6, 0.85, vnoise(wp * 2.2 + 3.0)) * (1.0 - ash);
	float snow = smoothstep(0.4, 0.8, up) * smoothstep(0.05, 0.55, weather_snow);
	c *= mix(1.0, 0.65, weather_wetness * (1.0 - snow));
	ALBEDO = mix(c, vec3(0.9, 0.92, 0.95), snow);
	ROUGHNESS = 1.0;
	EMISSION = vec3(1.0, 0.3, 0.06) * hot * glow * 4.0 * (1.0 - weather_wetness * 0.7) * (1.0 - snow);
}
