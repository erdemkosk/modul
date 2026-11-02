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
	c = mix(c, daub * (0.9 + 0.2 * grain), daub_k);
	c *= mix(1.0, 0.7, weather_wetness * (1.0 - snow));
	ALBEDO = mix(c, vec3(0.92, 0.94, 0.97), snow);
	ROUGHNESS = mix(roughness_base * mix(1.0, 0.55, weather_wetness), 0.75, snow);
}
