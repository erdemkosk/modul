shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Mud on a gun (GunCondition), drawn over its own worn finish as a material overlay.
// Gravity decides where it is: caked on the underside, the magazine, the bottom of the receiver
// and the stock, round the muzzle and the butt plate, with drips run down from it; elsewhere at
// most a thin smeared film, wiped along the gun by the hands. Most of the metal and wood stays
// as it was: seen from the side, at dirt 1 under two fifths of it is caked, at 0.4 a tenth (the
// coverage measured on each gun's meshes: thr_a, thr_b). The pattern is in the gun's own space (to_gun: where this mesh sits
// in it), so the bolt and the magazine carry the same mud as the body. Fresh it is the dark
// brown of wet soil and glossy; dried, a lighter grey-brown, matte and cracked, still only where
// it was caked. (Colours are linear: wet soil #3a2a1c..#4f3a26.)

uniform float dirt = 0.0; // 0 clean .. 1 caked
uniform float wet = 1.0; // 1 fresh .. 0 dried
uniform float low_y = -0.17; // the gun's bottom and top, its muzzle and butt (its own space)
uniform float high_y = 0.06;
uniform float front_z = -0.9;
uniform float back_z = 0.35;
// The threshold at dirt 0.4 and at 1, per gun (GunCondition.MUD_THRESHOLD, measured so that seen
// from the side a tenth of it is caked at 0.4 and under two fifths at 1).
uniform float thr_a = 0.77;
uniform float thr_b = 0.43;
instance uniform vec3 to_gun = vec3(0.0);

varying vec3 gp;
varying vec3 gn;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// How far into the cake a point is before the threshold: soft warped noise, plus gravity (low
// down, facing down, at the ends), plus drips.
float mud_level(vec3 p, vec3 n) {
	vec3 q = p + (vec3(noise(p * 9.0), noise(p * 9.0 + 5.2), noise(p * 9.0 + 11.7)) - 0.5) * 0.04;
	float body = noise(q * 13.0) * 0.55 + noise(q * 31.0) * 0.3 + noise(q * 75.0) * 0.15;
	float h = clamp((p.y - low_y) / max(high_y - low_y, 0.01), 0.0, 1.0);
	float zf = clamp((p.z - front_z) / max(back_z - front_z, 0.01), 0.0, 1.0);
	float ends = max(1.0 - smoothstep(0.0, 0.07, zf), smoothstep(0.93, 1.0, zf));
	float under = clamp(-n.y, 0.0, 1.0);
	float up = clamp(n.y, 0.0, 1.0);
	float grav = pow(1.0 - h, 1.5) * 0.75 + under * 0.2 + ends * 0.3 - up * 0.35 - h * 0.1;
	float drip = smoothstep(0.55, 0.85, noise(vec3(p.x * 70.0, p.y * 7.0, p.z * 70.0))) * (1.0 - h) * 0.25;
	return body * 0.6 + grav + drip;
}

void vertex() {
	gp = VERTEX + to_gun;
	gn = NORMAL;
}

void fragment() {
	if (dirt < 0.005) {
		discard;
	}
	vec3 n = normalize(gn);
	float thr = thr_a + (dirt - 0.4) / 0.6 * (thr_b - thr_a);
	float level = mud_level(gp, n) - thr;
	float caked = smoothstep(0.0, 0.08, level) * smoothstep(0.05, 0.2, dirt);
	float thick = smoothstep(0.04, 0.3, level);
	// A thin film smeared along the gun (wiped by the hands), near the cake and patchy.
	float smear = noise(vec3(gp.x * 45.0, gp.y * 45.0, gp.z * 5.0));
	float film = smoothstep(-0.14, 0.0, level) * smoothstep(0.4, 0.8, smear) * 0.3 * smoothstep(0.1, 0.5, dirt);
	float a = max(caked * 0.98, film);
	float k = caked * 0.98 / max(a, 0.001); // 1: cake, 0: film
	float grain = 0.85 + 0.3 * noise(gp * 140.0);
	vec3 wet_c = mix(vec3(0.19, 0.11, 0.055), vec3(0.13, 0.075, 0.037), thick); // (lit, it shows as wet soil: #4f3a26 .. #3a2a1c)
	vec3 dry_c = mix(vec3(0.23, 0.19, 0.14), vec3(0.19, 0.155, 0.115), thick); // grey-brown
	// Dried cake cracks into plates.
	float cell = abs(noise(gp * 120.0) - 0.5) * 2.0;
	float crack = (1.0 - smoothstep(0.0, 0.08, cell)) * (1.0 - wet) * thick;
	vec3 cake = mix(dry_c, wet_c, wet) * grain * (1.0 - crack * 0.6);
	vec3 film_c = mix(vec3(0.17, 0.14, 0.1), vec3(0.12, 0.075, 0.04), wet);
	ALBEDO = mix(film_c, cake, k);
	ROUGHNESS = mix(mix(0.8, 0.3, wet), mix(0.95, 0.12, wet), k);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.6, wet);
	ALPHA = a;
}
