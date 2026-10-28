shader_type spatial;
render_mode diffuse_lambert_wrap;

// People (CharacterLook.apply), as real as the guns and the dead. The clothes and gear by what
// they're made of (`fabric`): cloth woven, creased at the knees, elbows and waist where it bunches,
// faded where it's rubbed and the sun gets it, filthy from the boots up, a soft sheen at grazing
// angles; knitwear in ribs; canvas and webbing coarse; leather creased and scuffed; rubber soles;
// painted steel gritty and chipped; hi-vis glowing a little. The face is a real one's: skin with pores and a sheen on the forehead and nose, blood in the
// cheeks, nose and ears, coloured lips, darker under the eyes, a shaved beard's shadow; eyes wet,
// the iris in fibres round the pupil with a dark ring at its edge; hair and beard in strands.
// The detail sits on the rest pose (UV = (x, height), UV2.x = depth, written by
// tools/blender/build_character.py rest_uvs), so it stays put as he moves.

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform float specular = 0.12;
uniform float rim = 0.32; // how dark the edge goes
uniform bool skin = false;
uniform int eye = 0; // 1 the white, 2 the iris, 3 the pupil
uniform bool hair = false; // hair, beard, brows, lashes
// what a surface is made of: 1 cloth, 2 leather, 3 rubber, 4 metal, 5 knit, 6 canvas and webbing,
// 7 hi-vis and reflective, 8 mud, 9 painted steel (0: the plain painted look)
uniform int fabric = 0;
// printed camouflage over the cloth: 1 woodland, 2 a fleck pattern, 3 desert, 4 digital, 5 multi-tone
// (0 plain)
uniform int camo = 0;
uniform int pattern = 0; // woven into knitwear: 1 a shemagh's check
// the pattern laid on the model's own coordinates instead of the rest pose (meshes without the
// rest UVs: the first-person arms)
uniform bool object_space = false;
uniform float stubble = 0.35; // a shaved beard's shadow on the skin
uniform float age = 0.25; // 0 young .. 1 old: lines on the forehead, round the eyes, beside the mouth, spots
uniform int scar = 0; // an old scar: 1 down the left cheek, 2 through the right brow, 3 across the lips
uniform float freckles = 0.0;
uniform bool use_vertex_color = false;

global uniform float weather_wetness;

// the face's places (build_character.py: EYE_X, EYE_Z, ML)
const vec2 EYE = vec2(0.0315, 1.651);
const float IRIS = 0.0061;
const float ML = 1.5679;

varying float height; // above the feet (the model's origin), m
varying vec3 w_normal;
varying vec3 rest; // x across (left +), y up, z depth (forward -)

void vertex() {
	height = VERTEX.y;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// (glTF flips V: what was written as v arrives as 1 - v)
	rest = object_space ? VERTEX : vec3(UV.x, 1.0 - UV.y, UV2.x);
}

float bump_at(float x, float c, float w) {
	float t = (x - c) / w;
	return exp(-t * t);
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

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

// A printed camouflage's colour at a rest position (m). Each pattern in its own colours.
vec3 camo_colour(vec3 p, int kind) {
	if (kind == 1) {
		// Woodland: broad blobs stretched sideways, brown and dark green over light green,
		// black branches.
		// (warped and ragged-edged, as the print is: plain noise thresholds read as toy blobs)
		vec3 q = (p + (vec3(fbm(p * 8.0), fbm(p * 8.0 + 13.0), fbm(p * 8.0 + 29.0)) - 0.5) * 0.05) * vec3(7.0, 4.5, 7.0)
			+ (noise(p * 150.0) - 0.5) * 0.25;
		vec3 c = srgb(vec3(0.42, 0.45, 0.30));
		c = mix(c, srgb(vec3(0.40, 0.31, 0.21)), smoothstep(0.52, 0.55, fbm(q + 3.0)));
		c = mix(c, srgb(vec3(0.20, 0.25, 0.15)), smoothstep(0.54, 0.57, fbm(q * 1.1 + 17.0)));
		c = mix(c, srgb(vec3(0.08, 0.08, 0.07)), smoothstep(0.60, 0.63, fbm(q * 1.6 + 41.0)));
		return c;
	} else if (kind == 2) {
		// Flecks: small dots in clusters, five colours.
		vec3 c = srgb(vec3(0.50, 0.50, 0.40));
		float cl = fbm(p * 6.0);
		c = mix(c, srgb(vec3(0.42, 0.46, 0.30)), smoothstep(0.58, 0.62, noise(p * 70.0) * 0.6 + cl * 0.5));
		c = mix(c, srgb(vec3(0.21, 0.27, 0.17)), smoothstep(0.62, 0.66, noise(p * 85.0 + 9.0) * 0.6 + fbm(p * 6.0 + 5.0) * 0.5));
		c = mix(c, srgb(vec3(0.37, 0.27, 0.18)), smoothstep(0.64, 0.68, noise(p * 80.0 + 21.0) * 0.6 + fbm(p * 5.0 + 13.0) * 0.5));
		c = mix(c, srgb(vec3(0.09, 0.09, 0.08)), smoothstep(0.70, 0.73, noise(p * 95.0 + 33.0) * 0.6 + fbm(p * 7.0 + 29.0) * 0.45));
		return c;
	} else if (kind == 3) {
		// Desert: three sandy tones in soft patches.
		vec3 q = p * vec3(6.0, 4.0, 6.0);
		vec3 c = srgb(vec3(0.66, 0.59, 0.46));
		c = mix(c, srgb(vec3(0.55, 0.46, 0.34)), smoothstep(0.52, 0.56, fbm(q + 7.0)));
		c = mix(c, srgb(vec3(0.43, 0.38, 0.30)), smoothstep(0.58, 0.61, fbm(q * 1.3 + 23.0)));
		return c;
	} else if (kind == 4) {
		// Digital: square pixels in four greens and browns.
		vec3 q = floor(p / 0.011) * 0.011;
		vec3 c = srgb(vec3(0.46, 0.44, 0.34));
		c = mix(c, srgb(vec3(0.32, 0.36, 0.24)), step(0.50, fbm(q * 8.0 + 3.0)));
		c = mix(c, srgb(vec3(0.27, 0.24, 0.18)), step(0.56, fbm(q * 9.0 + 19.0)));
		c = mix(c, srgb(vec3(0.13, 0.13, 0.11)), step(0.62, fbm(q * 11.0 + 37.0)));
		return c;
	} else if (kind == 5) {
		// Multi-tone (the modern operators' kind): a soft ground running from sand to green, brushed
		// blotches of olive and brown with ragged edges, thin dark branches over them, a few pale
		// flecks. Domain-warped so nothing reads as a round blob.
		vec3 w = p + (vec3(fbm(p * 9.0), fbm(p * 9.0 + 11.0), fbm(p * 9.0 + 23.0)) - 0.5) * 0.06;
		vec3 q = w * vec3(9.0, 6.0, 9.0);
		vec3 c = mix(srgb(vec3(0.62, 0.56, 0.42)), srgb(vec3(0.47, 0.48, 0.34)), smoothstep(0.35, 0.65, fbm(q * 0.5 + 5.0)));
		c = mix(c, srgb(vec3(0.40, 0.42, 0.28)), smoothstep(0.53, 0.58, fbm(q + 3.0) + noise(w * 160.0) * 0.06));
		c = mix(c, srgb(vec3(0.44, 0.36, 0.25)), smoothstep(0.56, 0.60, fbm(q * 1.2 + 17.0) + noise(w * 180.0) * 0.06));
		float br = abs(fbm(q * 1.4 + 41.0) - 0.5);
		c = mix(c, srgb(vec3(0.25, 0.22, 0.16)), (1.0 - smoothstep(0.018, 0.03, br)) * smoothstep(0.5, 0.6, fbm(q * 0.8 + 61.0)));
		c = mix(c, srgb(vec3(0.64, 0.60, 0.48)), smoothstep(0.72, 0.76, noise(w * 110.0 + 7.0)) * 0.45);
		return c;
	}
	return vec3(0.5);
}

// Creases where cloth bunches: on the legs across them (knees, ankles over the boots, the crotch),
// on the arms across them (elbows, wrists, armpits), round the waist; a loose drape elsewhere. In
// metres of height; `r` the rest position.
float creases(vec3 r) {
	float ax = abs(r.x);
	float h = r.y;
	float f = fbm(r * 18.0) * 0.6; // drape
	if (ax > 0.2 && h > 0.9) {
		// the arm (rest A-pose: shoulder (0.178, 1.405) to wrist (0.531, 0.984))
		vec2 d = vec2(ax, h) - vec2(0.178, 1.405);
		float sa = dot(d, vec2(0.643, -0.766)); // along it
		float ac = dot(d, vec2(0.766, 0.643));
		float w = noise(vec3(sa * 140.0, ac * 18.0 + r.z * 18.0, r.z * 20.0));
		float g = 0.35 + bump_at(sa, 0.30, 0.06) + bump_at(sa, 0.50, 0.05) * 0.8 + bump_at(sa, 0.04, 0.05) * 0.6;
		f += w * g;
	} else if (h < 0.95) {
		float w = noise(vec3(r.x * 16.0, h * 120.0 + noise(r * 30.0) * 3.0, r.z * 16.0));
		float g = 0.3 + bump_at(h, 0.50, 0.07) + bump_at(h, 0.17, 0.06) * 1.2 + bump_at(h, 0.86, 0.05) * 0.7;
		f += w * g;
	} else {
		float w = noise(vec3(r.x * 20.0, h * 110.0, r.z * 20.0));
		f += w * (0.25 + bump_at(h, 1.0, 0.05) * 0.9 + bump_at(h, 1.33, 0.05) * 0.4 * smoothstep(0.1, 0.17, ax));
	}
	return f;
}

// Distance from q to the segment a-b.
float seg_dist(vec2 q, vec2 a, vec2 b) {
	vec2 d = b - a;
	float t = clamp(dot(q - a, d) / dot(d, d), 0.0, 1.0);
	return length(q - (a + d * t));
}

// 1 inside an ellipse (centre c, half sizes r) on the face, soft to 0 over `soft` of its size.
float spot(vec2 q, vec2 c, vec2 r, float soft) {
	return 1.0 - smoothstep(1.0 - soft, 1.0, length((q - c) / r));
}

void fragment() {
	vec3 c = albedo * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	float rough = roughness;
	float spec = specular;
	float bump = 0.0;
	vec2 q = vec2(abs(rest.x), rest.y);
	float front = smoothstep(-0.01, -0.05, rest.z); // the face's side of the head
	if (eye > 0) {
		// Wet: a sharp highlight on all of it.
		float r = length(q - EYE);
		if (eye == 2) {
			// Fibres running out from the pupil, a lighter ring round it, a dark ring at the edge.
			float t = r / IRIS;
			float a = atan(rest.y - EYE.y, q.x - EYE.x);
			float fib = noise(vec3(a * 38.0, t * 3.0, 0.0)) * 0.6 + noise(vec3(a * 90.0, t * 6.0, 3.0)) * 0.4;
			c *= mix(0.7, 1.25, fib);
			c = mix(c, c * vec3(1.35, 1.2, 0.9), smoothstep(0.55, 0.42, t) * smoothstep(0.3, 0.4, t) * 0.6);
			c *= mix(1.0, 0.35, smoothstep(0.78, 1.0, t));
		} else if (eye == 1) {
			// Darker and greyer toward the corners, shaded under the upper lid, a faint pink.
			c *= mix(1.0, 0.72, smoothstep(0.5, 1.0, r / 0.0115));
			c *= mix(1.0, 0.8, smoothstep(EYE.y - 0.001, EYE.y + 0.004, rest.y));
			c = mix(c, c * vec3(1.05, 0.88, 0.86), smoothstep(0.6, 1.0, r / 0.0115) * 0.5);
		}
		rough = 0.06;
		spec = 0.6;
	} else if (skin) {
		vec3 p = rest;
		// Blotchy, as skin is: a little uneven in tone, a few freckles and spots.
		c *= mix(0.93, 1.06, fbm(p * 55.0));
		c *= 1.0 - smoothstep(0.72, 0.8, noise(p * 900.0)) * 0.12;
		// Blood close under it: the cheeks, the nose, the ears, round the eyes.
		float red = spot(q, vec2(0.044, 1.618), vec2(0.020, 0.016), 0.9) * 0.8;
		red += spot(q, vec2(0.0, 1.610), vec2(0.010, 0.014), 0.9) * 0.7;
		float ears = smoothstep(0.066, 0.076, q.x) * smoothstep(1.58, 1.61, q.y) * smoothstep(1.69, 1.66, q.y);
		red = clamp(red * front + ears * 0.8, 0.0, 1.0);
		c = mix(c, c * vec3(1.08, 0.82, 0.8), clamp(red, 0.0, 1.0) * 0.45);
		// The lips.
		float lip = spot(q, vec2(0.0, 1.5738), vec2(0.0185, 0.0046), 0.5);
		lip = max(lip, spot(q, vec2(0.0, 1.5612), vec2(0.0160, 0.0058), 0.55));
		lip *= front * smoothstep(-0.07, -0.085, rest.z);
		c = mix(c, c * vec3(0.92, 0.66, 0.64), lip * 0.8);
		// Darker round the eyes: the thin skin over the socket, the shadow under them.
		float lids = spot(q, EYE + vec2(0.0, 0.0035), vec2(0.016, 0.010), 0.8);
		float bags = spot(q, EYE + vec2(0.002, -0.009), vec2(0.013, 0.0045), 0.9);
		c *= mix(vec3(1.0), vec3(0.88, 0.8, 0.82), clamp(lids * 0.6 + bags * 0.8, 0.0, 1.0) * front);
		// The beard's shadow where he shaves: the jaw, chin, upper lip and the neck under them.
		float line = 1.583 + clamp(q.x - 0.02, 0.0, 0.05) * 0.8; // from the mouth's corner up to the ear
		float beard = smoothstep(line + 0.004, line - 0.004, q.y) * smoothstep(1.47, 1.5, q.y) * smoothstep(0.08, 0.068, q.x);
		beard = max(beard, spot(q, vec2(0.0, 1.587), vec2(0.022, 0.0085), 0.6) * front); // the upper lip
		beard *= 1.0 - lip;
		beard *= 0.65 + 0.35 * noise(p * 1600.0);
		c = mix(c, c * vec3(0.72, 0.72, 0.76), beard * stubble);
		// Pores and fine lines; the forehead's creases, deeper with the years.
		float face = front * smoothstep(1.5, 1.53, q.y);
		bump = noise(p * 1500.0) * 0.00005 + fbm(p * 160.0) * 0.00012;
		float brow_lines = sin(q.y * 1250.0 + noise(p * 80.0) * 5.0) * smoothstep(1.685, 1.695, q.y) * smoothstep(1.735, 1.71, q.y) * face;
		bump += brow_lines * (0.000008 + 0.00013 * age * age);
		// Crow's feet fanning from the eyes' outer corners, the lines from the nose to the mouth's
		// corners, the bags under the eyes: shadowed and creased as the face gets older.
		vec2 corner = q - (EYE + vec2(0.0125, 0.0));
		float fan = sin(atan(corner.y, corner.x) * 26.0 + noise(p * 120.0) * 2.0) * smoothstep(0.003, 0.006, length(corner)) * smoothstep(0.016, 0.009, length(corner)) * step(0.0, corner.x);
		float fold = exp(-pow(seg_dist(q, vec2(0.0185, 1.604), vec2(0.031, 1.569)) / 0.0022, 2.0)) * front;
		bump += (fan * 0.00006 - fold * 0.0004) * age * face;
		c *= 1.0 - fold * (0.08 + 0.14 * age);
		c *= mix(vec3(1.0), vec3(0.9, 0.84, 0.86), bags * age * 0.6 * front);
		c *= 1.0 - smoothstep(0.7, 0.78, noise(p * 260.0 + 7.0)) * smoothstep(0.55, 1.0, age) * 0.18; // age spots
		c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), age * 0.12); // and paler, greyer
		// Freckles over the nose and cheeks.
		c *= 1.0 - smoothstep(0.6, 0.72, noise(p * 700.0)) * freckles * spot(q, vec2(0.025, 1.625), vec2(0.045, 0.03), 0.8) * front * 0.3;
		// An old scar: pale, a little raised, the skin pulled at its edges.
		if (scar > 0) {
			float sd = scar == 1 ? seg_dist(rest.xy, vec2(0.030, 1.628), vec2(0.056, 1.588))
				: (scar == 2 ? seg_dist(rest.xy, vec2(-0.036, 1.690), vec2(-0.029, 1.655))
				: seg_dist(rest.xy, vec2(0.009, 1.588), vec2(0.004, 1.556)));
			float sc = (1.0 - smoothstep(0.0006, 0.0018, sd + noise(p * 400.0) * 0.0004)) * front;
			c = mix(c, c * vec3(1.18, 1.0, 1.0) + vec3(0.06, 0.03, 0.03), sc * 0.7);
			bump += sc * 0.0004 - (1.0 - smoothstep(0.0018, 0.004, sd)) * front * 0.00015;
		}
		// A sheen on the forehead and nose, the cheeks duller.
		float tzone = max(smoothstep(0.03, 0.0, q.x) * smoothstep(1.6, 1.62, q.y), smoothstep(1.67, 1.69, q.y) * smoothstep(0.05, 0.03, q.x));
		rough = mix(0.62, 0.42, tzone * face);
		rough = mix(rough, 0.32, lip);
		spec = 0.32;
		// Blood under it lets light through.
		SSS_STRENGTH = 0.35;
	} else if (hair) {
		// Strands: streaks along the hair's fall, lighter and darker, some single hairs catching
		// the light.
		vec3 p = rest;
		float s = noise(vec3(p.x * 2600.0, p.y * 260.0, p.z * 2600.0)) * 0.6 + noise(vec3(p.x * 900.0, p.y * 90.0, p.z * 900.0)) * 0.4;
		c *= mix(0.62, 1.3, s);
		bump = s * 0.00025;
		rough = 0.7;
		spec = 0.25;
	}
	if (fabric > 0 && eye == 0 && !skin && !hair) {
		vec3 p = rest;
		float h = rest.y;
		// Fine detail fades out with distance, where it would only shimmer.
		float near = 1.0 - smoothstep(0.0006, 0.003, length(fwidth(p)));
		if (camo > 0 && (fabric == 1 || fabric == 6 || fabric == 11)) {
			// the print, darker on the dark parts (flaps, pads)
			c = camo_colour(p, camo) * clamp(dot(albedo, vec3(0.33)) / 0.06, 0.75, 1.0);
		}
		float tone = fbm(p * 7.0 + float(fabric) * 3.1);
		c *= mix(0.9, 1.08, tone);
		// Dyes as worn cloth has them: duller than paint (the grade lifts colour again).
		c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, fabric == 7 ? 1.0 : 0.72);
		float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float dirt = smoothstep(0.75, 0.05, h) * smoothstep(0.3, 0.7, fbm(p * 9.0 + 5.0));
		if (fabric == 1 || fabric == 5 || fabric == 6) {
			float fold = creases(p);
			if (fabric == 5 && pattern == 1) {
				// a shemagh: dark threads woven across the light in a check, a border band
				vec2 g = abs(fract(vec2(p.x + p.z, p.y) / 0.014) - 0.5);
				float check = max(step(0.38, g.x), step(0.38, g.y)) * 0.8 + step(0.47, max(g.x, g.y)) * 0.2;
				c = mix(c, c * vec3(0.18, 0.17, 0.16), check * 0.8);
			}
			float weave = fabric == 5
				? abs(sin(atan(p.x, p.z) * 140.0 + p.y * 90.0)) * 0.6 + noise(p * 2400.0) * 0.4 // knit ribs
				: (fabric == 6 ? noise(vec3(p.x, p.y * 3.0, p.z) * 1500.0) : noise(p * 2600.0)); // canvas, cloth
			bump = fold * (fabric == 1 ? 0.0032 : 0.0016) + weave * (fabric == 5 ? 0.0007 : 0.00025) * near;
			// Shade in the creases, rubbed lighter on what stands out, the sun's fading on top.
			c *= mix(0.72, 1.05, smoothstep(0.2, 0.85, fold));
			float rub = smoothstep(0.62, 0.85, fbm(p * 12.0 + 9.0)) * (bump_at(h, 0.5, 0.06) + bump_at(abs(p.x), 0.37, 0.04) * step(1.0, h) + 0.25);
			vec3 faded = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 0.7) * 1.15;
			c = mix(c, faded, clamp(rub * 0.6 + smoothstep(0.4, 0.95, w_normal.y) * 0.15, 0.0, 1.0));
			// Fabric's soft sheen at the silhouette.
			c += vec3(0.05) * pow(edge, 3.0) * (fabric == 5 ? 1.6 : 1.0);
			rough = fabric == 6 ? 0.88 : 0.95;
			spec = 0.15;
		} else if (fabric == 10 || fabric == 11) {
			// Nylon: a puffer's shell, glossy and pulled taut over the fill; a softshell's smooth,
			// faintly shiny face. Creased less, a little sheen.
			float fold = creases(p);
			bump = fold * (fabric == 10 ? 0.0016 : 0.0022) + noise(p * 3000.0) * 0.00008 * near;
			c *= mix(0.78, 1.05, smoothstep(0.2, 0.85, fold));
			rough = fabric == 10 ? 0.45 : 0.7;
			spec = fabric == 10 ? 0.4 : 0.25;
		} else if (fabric == 2) {
			// Leather: creased, darker in the creases, scuffed light on the toes and knuckles.
			float cr = noise(vec3(p.x * 300.0, p.y * 90.0, p.z * 300.0)) * 0.6 + fbm(p * 60.0) * 0.4;
			bump = cr * 0.0006 * near + fbm(p * 25.0) * 0.0008;
			c *= mix(0.78, 1.08, cr);
			float scuff = smoothstep(0.55, 0.8, fbm(p * 40.0 + 3.0)) * (smoothstep(0.2, 0.05, h) + 0.4);
			c = mix(c, c * 1.35 + vec3(0.03), scuff * 0.5);
			rough = mix(0.5, 0.82, scuff + (1.0 - cr) * 0.3);
			spec = 0.3;
		} else if (fabric == 3) {
			c *= mix(0.85, 1.05, noise(p * 400.0));
			bump = noise(p * 900.0) * 0.0002 * near;
			rough = 0.85;
			spec = 0.2;
		} else if (fabric == 7) {
			// Fluorescent: a little light of its own, dirt in the weave.
			bump = noise(p * 2600.0) * 0.00025 * near;
			EMISSION = c * 0.06;
			rough = 0.6;
			spec = 0.35;
		} else if (fabric == 8) {
			// Mud: lumpy, glossy where it's still wet.
			float lump = fbm(p * 90.0);
			bump = lump * 0.0025;
			c *= mix(0.7, 1.1, lump);
			rough = mix(0.35, 0.95, smoothstep(0.4, 0.7, fbm(p * 20.0)));
			spec = 0.35;
		} else if (fabric == 9) {
			// Painted steel: rough paint with grit in it, chipped to dark metal at the rim and bumps.
			bump = noise(p * 1200.0) * 0.00015 * near + fbm(p * 50.0) * 0.0003;
			float chip = smoothstep(0.7, 0.76, fbm(p * 70.0)) * (0.4 + pow(edge, 2.0));
			c = mix(c, vec3(0.13, 0.12, 0.11), clamp(chip, 0.0, 1.0) * 0.8);
			rough = mix(0.72, 0.45, chip);
			spec = mix(0.3, 0.5, chip);
		} else if (fabric == 12) {
			// Fur (an ushanka's): a dense pile in tufts, the hairs' tips lighter, darker down in it,
			// no sheen.
			float tuft = fbm(p * 160.0);
			float hairs = noise(vec3(p.x * 1800.0, p.y * 700.0, p.z * 1800.0));
			c *= mix(0.62, 1.22, tuft * 0.6 + hairs * 0.4);
			bump = tuft * 0.0016 + hairs * 0.0005 * near;
			c += vec3(0.04) * pow(edge, 2.0);
			rough = 1.0;
			spec = 0.08;
		} else if (fabric == 4) {
			bump = noise(p * 600.0) * 0.0001 * near;
			c *= mix(0.8, 1.05, fbm(p * 30.0));
		}
		// Dirt and dried mud from the ground up, grime everywhere a little.
		c = mix(c, vec3(0.2, 0.16, 0.12), dirt * (fabric == 4 ? 0.3 : 0.45));
		c *= mix(1.0, 0.85, smoothstep(0.55, 0.85, fbm(p * 4.0 + 17.0)));
		rough = mix(rough, 0.95, dirt * 0.5);
	} else if (!skin && eye == 0 && !hair) {
		// Zenithal: the head and shoulders catch the light, the legs sink into the ground's shade.
		c *= mix(0.8, 1.06, smoothstep(0.15, 1.65, height));
		// Faces turned to the sky a touch lighter, as the brush picks out the tops of folds.
		c *= mix(1.0, 1.08, smoothstep(0.35, 0.95, w_normal.y));
		float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		c *= 1.0 - rim * edge;
	} else if (skin) {
		// The hands and neck lower down a little in the shade, as everything else.
		c *= mix(0.86, 1.0, smoothstep(0.6, 1.5, height));
	}
	c *= mix(1.0, 0.72, weather_wetness * 0.5);
	if (bump != 0.0) {
		NORMAL = bumped(NORMAL, VERTEX, bump);
	}
	ALBEDO = c;
	ROUGHNESS = mix(rough, 0.4, weather_wetness * 0.5);
	METALLIC = metallic;
	SPECULAR = mix(spec, 0.45, weather_wetness * 0.5);
}
