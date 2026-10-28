shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The dead, as they would look (ZombieLook): skin gone grey-green and waxy, mottled where the
// blood has settled and bruised, the veins showing dark through it, filth working up from the
// feet and in from the hands; old blood dried brown-black in runs down from the mouth, over the
// hands and soaked into the clothes; the clothes worn, grimy and creased; wounds and torn flesh
// dark and wet, clotting. All of it from the rest pose (two UV maps written by
// tools/blender/build_zombie.py rest_uvs: UV = (x, height), UV2 = (depth, gore weight)), so it
// stays on the body as it moves, and shifted per zombie (`seed`) so no two look alike.

uniform int part = 1; // 0 cloth, 1 skin, 2 wet (blood, flesh, eyes), 3 dark (the mouth)
uniform float lift = 1.0; // brightens the vertex colours
uniform vec3 tint : source_color = vec3(1.0); // the dark part's colour (it has no vertex colours)
instance uniform float seed = 0.0;
instance uniform vec3 cloth_tint : source_color = vec3(1.0); // what this one's clothes went to
instance uniform vec3 skin_tint : source_color = vec3(1.0); // and its skin
instance uniform float bloody = 1.0; // how much old blood is on it

global uniform float weather_wetness;

varying vec3 rest; // rest-pose position, metres: x across, y up from the feet, z depth
varying float gore; // 0..1 where blood gathers (mouth run, hands)

void vertex() {
	// (glTF flips V: what was written as v arrives as 1 - v)
	rest = vec3(UV.x, 1.0 - UV.y, UV2.x);
	gore = clamp(1.0 - UV2.y, 0.0, 1.0);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

// A surface's normal tipped by a height field over it (screen-space derivatives: no tangents
// needed). `pos` view-space position, `h` the height in metres.
vec3 bumped(vec3 n, vec3 pos, float h) {
	vec3 dpx = dFdx(pos);
	vec3 dpy = dFdy(pos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

// 0..1: old blood on it, in runs downward (the pattern stretched up and down) and in blots.
float blood_mask(vec3 p, float want) {
	float run = fbm(vec3(p.x * 34.0, p.y * 3.0, p.z * 34.0) + 31.0);
	float edge = noise(p * 55.0) * 0.12;
	return smoothstep(0.0, 0.05, want - (1.0 - run) * 1.3 + edge);
}

void fragment() {
	vec3 p = rest + vec3(seed * 1.73, 0.0, seed * 0.61);
	float h = rest.y;
	vec3 c = COLOR.rgb * lift;
	float rough = 0.6;
	float spec = 0.3;
	float bump = 0.0;
	// Blood away from the mouth and hands: a few blots, more on some than others.
	float blot = smoothstep(0.6, 0.78, fbm(p * 4.0 + 41.0)) * (0.35 + 0.4 * noise(vec3(seed))) * smoothstep(1.5, 1.4, h) * bloody;
	if (part == 1) {
		// Skin: settled blood (purple-brown) low and in patches, rot going green, waxy pale spots.
		c *= skin_tint;
		float settle = fbm(p * 6.0);
		float rot = fbm(p * 2.6 + 11.0);
		c *= mix(vec3(1.0), vec3(0.74, 0.86, 0.6), smoothstep(0.4, 0.72, rot));
		c *= mix(vec3(1.0), vec3(0.5, 0.36, 0.46), smoothstep(0.45, 0.78, settle));
		c *= mix(0.88, 1.25, smoothstep(0.5, 0.75, fbm(p * 11.0 + 3.0)));
		// Blotches, small and dark: lesions, sores, dirt ground in.
		c *= 1.0 - smoothstep(0.66, 0.74, fbm(p * 20.0 + 17.0)) * 0.45;
		// Veins dark through it, in places.
		float v = noise(p * 24.0 + vec3(0.0, fbm(p * 7.0) * 2.5, 0.0));
		float vein = pow(1.0 - abs(v * 2.0 - 1.0), 16.0) * smoothstep(0.42, 0.68, fbm(p * 3.5 + 7.0));
		c = mix(c, c * vec3(0.40, 0.44, 0.60), vein * 0.8);
		// Filth from the ground up, and on the hands.
		float filth = smoothstep(0.75, 0.05, h) * 0.7 + gore * 0.35;
		c *= 1.0 - filth * smoothstep(0.3, 0.7, fbm(p * 9.0 + 20.0)) * 0.55;
		// The face: the flesh fallen in under the bone, as on a skull: dark hollows round the eyes,
		// under the cheekbones, down beside the nose, round the mouth.
		vec2 q = vec2(abs(rest.x), h);
		float face = smoothstep(-0.01, -0.05, rest.z) * smoothstep(1.52, 1.56, h);
		float hollows = 1.0 - smoothstep(0.01, 0.026, length((q - vec2(0.0315, 1.651)) * vec2(1.0, 1.35)));
		hollows += (1.0 - smoothstep(0.0, 0.024, length((q - vec2(0.046, 1.603)) * vec2(1.0, 0.7)))) * 0.6;
		hollows += (1.0 - smoothstep(0.004, 0.014, abs(q.x - 0.018 - (1.62 - h) * 0.25))) * smoothstep(1.64, 1.6, h) * smoothstep(1.56, 1.585, h) * 0.45;
		hollows += (1.0 - smoothstep(0.012, 0.03, length((q - vec2(0.0, 1.566)) * vec2(0.75, 1.4)))) * 0.5;
		c *= 1.0 - clamp(hollows, 0.0, 1.0) * face * 0.8;
		// Old blood: down from the mouth, over the hands.
		float b = blood_mask(p, max(gore * 0.62 * min(bloody, 1.2), blot));
		vec3 dried = mix(vec3(0.06, 0.022, 0.016), vec3(0.11, 0.02, 0.014), noise(p * 9.0));
		c = mix(c, dried, b * 0.9);
		rough = mix(0.5 + 0.3 * settle, 0.72, b);
		spec = mix(0.32, 0.25, b);
		// Pores, creases, the skin loose on the bone.
		bump = fbm(p * 70.0) * 0.0005 + noise(p * 14.0) * 0.0018 - vein * 0.0004;
	} else if (part == 0) {
		// Cloth: worn and faded unevenly, filthy toward the hems and up from the ground,
		// stiff with old blood where it soaked through.
		c *= cloth_tint * mix(0.82, 1.1, fbm(p * 4.5 + 5.0));
		float filth = smoothstep(0.9, 0.0, h);
		c *= 1.0 - filth * smoothstep(0.25, 0.75, fbm(p * 7.0 + 13.0)) * 0.6;
		c *= mix(1.0, 0.7, smoothstep(0.55, 0.8, fbm(p * 13.0 + 2.0)) * 0.5); // grease, sweat
		float b = blood_mask(p, max(gore * 0.85 * min(bloody, 1.2), blot * 1.15));
		c = mix(c, c * vec3(0.22, 0.08, 0.06) + vec3(0.025, 0.006, 0.004), b * 0.9);
		rough = mix(0.95, 0.7, b);
		spec = 0.12;
		bump = noise(p * 260.0) * 0.00025 + fbm(p * 9.0 + 4.0) * 0.004; // weave, creases
	} else if (part == 2) {
		// Wet: blood and torn flesh, clotting dark in places, glossy where it's still running.
		float clot = fbm(p * 28.0);
		c *= mix(0.55, 1.15, clot);
		// Torn muscle: fibres in it, light and dark.
		c *= mix(0.75, 1.15, noise(vec3(p.x * 30.0, p.y * 260.0, p.z * 30.0)));
		rough = mix(0.08, 0.55, smoothstep(0.4, 0.75, clot));
		spec = 0.5;
		bump = clot * 0.0015;
	} else {
		c = tint;
		rough = 0.5;
		spec = 0.2;
	}
	// The rain darkens and wets it all.
	c *= mix(1.0, 0.75, weather_wetness * 0.5);
	rough = mix(rough, 0.4, weather_wetness * 0.5);
	if (bump != 0.0) {
		NORMAL = bumped(NORMAL, VERTEX, bump);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
