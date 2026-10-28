shader_type spatial;
render_mode cull_disabled;
// A strip of gauze wound round a limb (BandageWrap): off-white cotton with its weave, the edges a
// little frayed and darker, and blood come through it round the wound, darker where it's soaked.
// UV.x runs along the strip (0 where it starts, 1 at its end), UV.y across it.

instance uniform float reveal = 1.0; // how much of the strip is on (0..1)
instance uniform float blood = 0.4; // how much has come through (0..1)
instance uniform float wound_angle = 0.0; // where round the limb the wound is (rad, local)
instance uniform float strip_len = 1.0; // the strip's length in metres
instance uniform float dirt = 0.0; // grime on it (0..1)

varying vec3 lpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	if (UV.x > reveal) {
		discard;
	}
	float m = UV.x * strip_len;
	// The weave: fine crossing threads, and the loose open gauze between them.
	float tx = abs(sin(m * 700.0));
	float ty = abs(sin(UV.y * 55.0));
	float weave = 0.86 + 0.14 * smoothstep(0.2, 0.9, max(tx, ty));
	float mottle = 0.9 + 0.1 * vnoise(vec2(m * 30.0, UV.y * 5.0));
	vec3 gauze = vec3(0.80, 0.78, 0.71) * weave * mottle;
	float edge = smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.9, UV.y);
	gauze *= mix(0.78, 1.0, edge);
	gauze = mix(gauze, vec3(0.30, 0.25, 0.18), dirt * (0.4 + 0.4 * vnoise(vec2(m * 12.0, UV.y * 3.0))));
	// Blood: a patch round the wound, ragged at its edge, the middle darker and soaked.
	float ang = atan(lpos.z, lpos.x);
	float da = acos(clamp(cos(ang - wound_angle), -1.0, 1.0));
	float d = length(vec2(lpos.y * 9.0, da * 0.85));
	float n = vnoise(vec2(ang * 3.0, lpos.y * 40.0) + wound_angle * 7.0) * 0.6 + vnoise(vec2(ang * 9.0, lpos.y * 120.0)) * 0.3;
	float b = smoothstep(0.95, 0.35, d + n * 0.55 - blood * 0.55) * blood;
	float soaked = smoothstep(0.35, 0.9, b);
	vec3 red = mix(vec3(0.30, 0.025, 0.02), vec3(0.11, 0.008, 0.006), soaked);
	float k = clamp(b * 1.5, 0.0, 0.92);
	ALBEDO = mix(gauze, red, k);
	ROUGHNESS = mix(0.95, 0.55, soaked * k);
	SPECULAR = 0.3;
}
