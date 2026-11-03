// A building piece built in Blender (scripts/building.gd, tools/blender/build_buildings.py): its own
// colours in its vertices, darkened and glossed by the wet, and snow lying on whatever faces up
// (roofs, the tops of logs, a woodpile, the ground stones) as it lies on the ground.
shader_type spatial;
render_mode diffuse_burley;

global uniform float weather_snow;
global uniform float weather_wetness;

uniform float roughness_base = 0.92;
uniform vec3 daub = vec3(0.78, 0.69, 0.53); // a house's mud plaster over its logs
uniform float daub_k = 0.0;
instance uniform float weathering = 0.0; // the years on it (Building.age): greyed, streaked, mossed low down

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
	// Grain and weathering: broad streaks and fine flecks, so no face is one flat colour.
	float grain = vnoise(wp * vec3(5.0, 1.2, 5.0)) * 0.55 + vnoise(wp * 22.0) * 0.45;
	float up = clamp(wn.y, 0.0, 1.0);
	float snow = smoothstep(0.4, 0.8, up) * smoothstep(0.05, 0.55, weather_snow);
	vec3 c = COLOR.rgb * (0.86 + 0.26 * grain);
	// (the plaster's own patchiness: thicker here, worn thin there so the log shows through)
	float worn = vnoise(wp * vec3(1.6, 3.5, 1.6)) * 0.6 + vnoise(wp * 9.0) * 0.4;
	c = mix(c, daub * (0.86 + 0.28 * grain), daub_k * mix(0.6, 1.0, smoothstep(0.25, 0.6, worn)));
	// The years: the wood silvered grey, rain streaks down the faces, moss low down and on the tops.
	if (weathering > 0.01) {
		float lum = dot(c, vec3(0.3, 0.55, 0.15));
		c = mix(c, vec3(lum) * vec3(0.92, 0.9, 0.86), weathering * 0.5);
		float streak = smoothstep(0.55, 0.9, vnoise(wp * vec3(7.0, 0.35, 7.0)));
		c *= 1.0 - weathering * 0.28 * streak * (1.0 - up);
		float low = 1.0 - smoothstep(0.0, 1.4, wp.y - NODE_POSITION_WORLD.y);
		float moss = smoothstep(0.5, 0.78, vnoise(wp * 1.4) * 0.7 + grain * 0.3) * clamp(low * 0.8 + up * 0.5, 0.0, 1.0) * weathering;
		c = mix(c, vec3(0.2, 0.26, 0.11) * (0.8 + 0.4 * grain), moss * 0.65);
	}
	c *= mix(1.0, 0.7, weather_wetness * (1.0 - snow));
	ALBEDO = mix(c, vec3(0.92, 0.94, 0.97), snow);
	ROUGHNESS = mix(roughness_base * mix(1.0, 0.55, weather_wetness), 0.75, snow);
}
