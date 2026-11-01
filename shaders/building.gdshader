// A building piece built in Blender (scripts/building.gd, tools/blender/build_buildings.py): its own
// colours in its vertices, darkened and glossed by the wet, and snow lying on whatever faces up
// (roofs, the tops of logs, a woodpile, the ground stones) as it lies on the ground.
shader_type spatial;
render_mode diffuse_burley;

global uniform float weather_snow;
global uniform float weather_wetness;

uniform float roughness_base = 0.92;

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = clamp(wn.y, 0.0, 1.0);
	float snow = smoothstep(0.4, 0.8, up) * smoothstep(0.05, 0.55, weather_snow);
	vec3 c = COLOR.rgb;
	c *= mix(1.0, 0.7, weather_wetness * (1.0 - snow));
	ALBEDO = mix(c, vec3(0.92, 0.94, 0.97), snow);
	ROUGHNESS = mix(roughness_base * mix(1.0, 0.55, weather_wetness), 0.75, snow);
}
