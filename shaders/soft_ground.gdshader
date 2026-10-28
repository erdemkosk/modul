shader_type spatial;
render_mode cull_disabled;

// Deformable ground: the depth grid (one texel per vertex) pushes vertices down.
// In the open world the patch is a 32 m tile and the soft-ground map says where in it
// the ground is really soft: outside that it isn't drawn (the terrain is), and inside
// it looks the same as the terrain's own mud or snow.
//
// Mud is thick and wet, not a painted sheet: the surface is heaped into soft lumps, glossy
// where it's fresh, dried to a paler matte crust on the tops of old heaps in dry weather,
// dark and slick in the creases and the ruts. Normals are worked out from the same height
// function the vertices use (smooth, not faceted), and a fine layer of blobs on top catches
// the light the way churned mud does.
//
// Water stands in it. A rut or a footprint dug below the water line fills with muddy water
// over the next minute or so (SoftPatch.water_rule: the wheels feel the same water), faster
// in rain; in the deepest, wettest mud the hollows between the heaps hold pools that spread
// as it rains. The water is drawn level (its normal flat, whatever the mud under it does):
// brown and murky, a mirror at a glancing angle, with a dark wet margin round it,
// rings from the rain and from whatever goes into it (SoftPatch.stirs).
uniform sampler2D depth_tex : filter_nearest;
uniform sampler2D age_tex : filter_nearest; // when each cell was dug into dry ground (SoftPatch.now)
uniform vec3 top_color : source_color = vec3(0.32, 0.25, 0.17);
uniform vec3 deep_color : source_color = vec3(0.17, 0.12, 0.08);
uniform float max_depth = 0.4;
uniform float wetness = 0.8;
uniform float ground_wet = 0.44; // SoftPatch.wet_level in dry weather
uniform float now = 0.0; // SoftPatch.now
uniform float snowfall = 0.0; // Weather.snow_now: how hard it is snowing (fills fresh tracks back in)
uniform vec4 stirs[8]; // x, z, strength, time (SoftPatch.add_stir)
uniform bool use_mask = false;
uniform bool is_snow = false;
uniform sampler2D soft_map : filter_linear, repeat_disable;
uniform float map_half = 1024.0;
uniform float map_size = 2049.0;

global uniform float weather_wetness;
global uniform float weather_rain;
global uniform float weather_snow; // snow lying on the ground
global uniform float weather_ice; // how much of the wet ground has frozen

varying float v_depth;
varying float v_berm;
varying vec2 v_xz;
varying float v_water; // depth of water over the ground here, m (below 0: how far the ground stands above it)
varying float v_fresh; // 1 just dug, fading as it settles
varying float v_age; // seconds since this cell was dug into dry ground

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

float fbm(vec2 p, int oct) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return s;
}

// Rounded heaps: the noise pushed through a soft max so the tops bulge and the gaps between
// them crease, like mud that has been churned and left to slump.
float gloop(vec2 p) {
	float n = fbm(p, 3);
	return smoothstep(0.25, 0.8, n) * smoothstep(0.25, 0.8, n);
}

float depth_at(ivec2 cell, ivec2 size) {
	return texelFetch(depth_tex, clamp(cell, ivec2(0), size - ivec2(1)), 0).r;
}

// The rut as drawn: the 20 cm grid softened over its neighbours so the walls slump round
// like mud instead of stepping like a staircase (the bottom keeps most of its depth).
float soft_depth(ivec2 cell, ivec2 size) {
	float c = depth_at(cell, size);
	if (cell.x <= 0 || cell.y <= 0 || cell.x >= size.x - 1 || cell.y >= size.y - 1) {
		return c; // shared with the next tile: both must land on the same height
	}
	float s = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int x = -1; x <= 1; x++) {
			float w = (x == 0 ? 2.0 : 1.0) * (z == 0 ? 2.0 : 1.0);
			s += depth_at(cell + ivec2(x, z), size) * w;
		}
	}
	return mix(s / 16.0, c, 0.55);
}

// How soft the ground is here (the open world's mud map; 1 on the test map).
float softness(vec2 xz) {
	if (!use_mask) {
		return 1.0;
	}
	vec2 sm = textureLod(soft_map, (xz + map_half) / (map_size - 1.0), 0.0).rg;
	return max(sm.r, sm.g);
}

// How wet the ground is for standing water (SoftPatch.wet_level).
float wet_level() {
	if (is_snow) {
		return clamp(weather_wetness * 0.7, 0.0, 1.0);
	}
	return clamp(max(ground_wet, weather_wetness), 0.0, 1.0);
}

// 0..1: how much the hollows between the heaps hold water here (SoftPatch.pool_amount).
float pool_amount(vec2 xz, float soft) {
	if (!use_mask || is_snow) {
		return 0.0;
	}
	return smoothstep(0.8, 0.95, soft + (fbm(xz * 0.2 + 11.0, 3) - 0.5) * 0.5 + weather_wetness * 0.08);
}

// Ground height offset at a grid cell: lumps of churned mud (gone where it has been
// driven flat, and smaller in a rut's bottom), minus the rut, plus a bulge on the lips.
// Towards the edge of the mud the lumps die away and it sits a little low, in its hollow,
// so it meets the grass without a step.
float height_at(ivec2 cell, ivec2 size, vec2 xz) {
	float d = soft_depth(cell, size);
	float mask = use_mask ? smoothstep(0.5, 0.7, softness(xz)) : 0.0;
	float driven = clamp(abs(d) * 10.0, 0.0, 1.0);
	float lumps = (gloop(xz * 0.9) - 0.45) * 0.15 + (fbm(xz * 3.2, 2) - 0.5) * 0.035 - 0.02;
	lumps *= mix(1.0, 0.3, driven) * mask;
	if (is_snow) {
		lumps *= 0.5;
	}
	return lumps - d;
}

void vertex() {
	ivec2 size = textureSize(depth_tex, 0);
	ivec2 cell = ivec2(round(UV * vec2(size - ivec2(1))));
	float d = soft_depth(cell, size);
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float cell_m = 0.2; // SoftPatch.CELL
	float h = height_at(cell, size, v_xz);

	// Water: in a rut dug below the line, rising as the wet ground seeps into it; in the
	// hollows of the wettest mud, a pool.
	float wet = wet_level();
	float line = mix(0.16, 0.025, wet);
	float tau = mix(90.0, 12.0, wet);
	float age = max(now - texelFetch(age_tex, clamp(cell, ivec2(0), size - ivec2(1)), 0).r, 0.0);
	// Water runs between neighbouring cells: the fill is evened out over them, so a rut dug
	// over a few seconds fills as one, not cell by cell.
	float fill = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int x = -1; x <= 1; x++) {
			float a = max(now - texelFetch(age_tex, clamp(cell + ivec2(x, z), ivec2(0), size - ivec2(1)), 0).r, 0.0);
			fill += 1.0 - exp(-a / tau);
		}
	}
	fill /= 9.0;
	// (kept continuous across the grid, so the water's edge is a smooth line through the
	// triangles, not their stepped outline: below the line it goes negative as fast as it
	// would have risen)
	v_water = d > line ? fill * (d - line) : d - line;
	float pa = pool_amount(v_xz, softness(v_xz));
	if (pa > 0.0) {
		v_water = max(v_water, -0.1 + 0.05 * pa - h);
	}
	v_fresh = d > 0.005 ? exp(-age / (tau * 4.0)) : 0.0;
	v_age = age;
	VERTEX.y += h;
	v_depth = d;
	v_berm = clamp(-d / 0.08, 0.0, 1.0);
	// Smooth normal from the neighbours, bent onto the ground's own slope (SoftPatch puts
	// that in NORMAL).
	// On the tile's edge there is no neighbour on one side: take the slope from the side that
	// is there (one-sided), so the shading matches the next tile's across the seam.
	vec3 ground = NORMAL / max(NORMAL.y, 0.2);
	{
		int x0 = max(cell.x - 1, 0);
		int x1 = min(cell.x + 1, size.x - 1);
		int z0 = max(cell.y - 1, 0);
		int z1 = min(cell.y + 1, size.y - 1);
		float hx0 = height_at(ivec2(x0, cell.y), size, v_xz + vec2(float(x0 - cell.x) * cell_m, 0.0));
		float hx1 = height_at(ivec2(x1, cell.y), size, v_xz + vec2(float(x1 - cell.x) * cell_m, 0.0));
		float hz0 = height_at(ivec2(cell.x, z0), size, v_xz + vec2(0.0, float(z0 - cell.y) * cell_m));
		float hz1 = height_at(ivec2(cell.x, z1), size, v_xz + vec2(0.0, float(z1 - cell.y) * cell_m));
		float sx = max(float(x1 - x0), 1.0) * cell_m;
		float sz = max(float(z1 - z0), 1.0) * cell_m;
		NORMAL = normalize(ground + vec3(-(hx1 - hx0) / sx, 0.0, -(hz1 - hz0) / sz));
	}
}

// Rings on the water: raindrops landing all over it, and the waves running out from a boot
// or a tyre that went in (stirs). Returns the slope of the surface.
vec2 ripples(vec2 xz) {
	vec2 slope = vec2(0.0);
	if (weather_rain > 0.01) {
		for (int layer = 0; layer < 2; layer++) {
			vec2 p = xz * (layer == 0 ? 3.0 : 4.7) + float(layer) * 17.0;
			vec2 ci = floor(p);
			float t = TIME * (1.1 + 0.3 * float(layer)) + hash12(ci) * 7.0;
			vec2 o = (vec2(hash12(ci + 3.0), hash12(ci + 9.0)) - 0.5) * 0.5;
			vec2 dv = fract(p) - 0.5 - o;
			float r = length(dv);
			float ph = fract(t);
			float ring = sin((r - ph * 0.45) * 45.0) * smoothstep(0.45, 0.0, r) * (1.0 - ph) * step(hash12(ci + floor(t)), weather_rain);
			slope += dv / max(r, 0.001) * ring * 0.22;
		}
	}
	for (int i = 0; i < 8; i++) {
		vec4 s = stirs[i];
		float age = now - s.w;
		if (s.z <= 0.0 || age < 0.0 || age > 4.0) {
			continue;
		}
		vec2 dv = xz - s.xy;
		float r = length(dv);
		float front = 0.12 + age * 0.75;
		float band = exp(-abs(r - front) * 5.0) * smoothstep(0.0, 0.25, front + 0.2 - r);
		float wave = sin((r - front) * 22.0) * band * exp(-age * 1.1) * s.z;
		slope += dv / max(r, 0.001) * wave * 0.5;
	}
	return slope;
}

// Distance to the nearest edge between jittered cells (F2 - F1): the cracks in a sheet of ice.
float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + vec2(hash12(i + o), hash12(i + o + 17.0)) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	float soft = 1.0;
	if (use_mask) {
		vec2 sm = texture(soft_map, (v_xz + map_half) / (map_size - 1.0)).rg;
		soft = max(sm.r, sm.g);
		if (soft < 0.5) {
			discard; // firm ground: the terrain draws it
		}
	}
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float t = clamp(v_depth / max(max_depth, 0.001), 0.0, 1.0);
	float fine = fbm(v_xz * 0.8, 3);
	float rain_wet = clamp(weather_wetness, 0.0, 1.0);

	// The water's edge, ragged a little finer than the 20 cm grid it comes from.
	float edge_n = (fbm(v_xz * 6.0, 2) - 0.5) * 0.012;
	float water = smoothstep(0.0, 0.01, v_water + edge_n);
	if (is_snow) {
		water *= 1.0 - clamp(weather_ice * 1.4, 0.0, 1.0); // slush only in a thaw: frozen, it is packed snow
	}
	float margin = smoothstep(-0.06, 0.0, v_water + edge_n) * (1.0 - water); // soaked, just above it

	// Fine blobs and smears in the surface, there to catch highlights (not geometry).
	if (!is_snow) {
		float e = 0.03;
		vec2 p = v_xz * 7.0;
		float b0 = gloop(p);
		float bx = gloop(p + vec2(e * 7.0, 0.0));
		float bz = gloop(p + vec2(0.0, e * 7.0));
		float amp = mix(0.015, 0.006, t) * (1.0 - water);
		n_w = normalize(n_w + vec3(-(bx - b0) / e, 0.0, -(bz - b0) / e) * amp);
	}

	vec3 top;
	vec3 deep;
	if (is_snow) {
		top = vec3(0.8, 0.83, 0.88) * (0.93 + 0.07 * fine);
		// A track is packed snow: smoother, a cold blue-white in its own shade, only churned
		// down to the brown earth at the bottom of the deepest.
		deep = mix(vec3(0.62, 0.68, 0.78), vec3(0.4, 0.37, 0.33), smoothstep(0.65, 0.95, t));
		deep = mix(deep, vec3(0.3, 0.28, 0.25), rain_wet * 0.6); // thawing: grey, wet slush
	} else if (use_mask) {
		top = mix(vec3(0.095, 0.068, 0.046), vec3(0.15, 0.108, 0.07), fbm(v_xz * 0.35, 3)) * (0.85 + 0.3 * fine);
		top = mix(top, vec3(0.058, 0.043, 0.03), smoothstep(0.62, 0.9, soft));
		deep = vec3(0.05, 0.036, 0.025);
	} else {
		top = top_color;
		deep = deep_color;
	}
	vec3 col = mix(top, deep, sqrt(t));
	float rough;
	float crest = gloop(v_xz * 0.9);
	float freeze = clamp(weather_ice * 1.4, 0.0, 1.0); // the ground frozen hard (Weather.ice)
	if (is_snow) {
		rough = mix(0.75, 0.45, t);
		rough = mix(rough, 0.25, rain_wet * t); // slush in the ruts
		rough = mix(rough, 0.5, freeze * 0.6); // a frozen crust
		col = mix(col, col * 0.8, margin);
		// Snow falling into fresh tracks fills them back in with powder.
		float refill = (1.0 - exp(-v_age * snowfall / 120.0)) * smoothstep(0.0, 0.02, v_depth);
		col = mix(col, top, refill * 0.8);
		rough = mix(rough, 0.75, refill);
	} else {
		// Old heaps dry out on top in dry weather: a paler, matte, cracked-looking skin over
		// the wet mud (the creases between them stay dark and wet).
		float crust = smoothstep(0.7, 0.95, crest) * (1.0 - rain_wet) * (1.0 - v_fresh) * (1.0 - margin) * smoothstep(0.03, 0.0, v_depth);
		col = mix(col, col * 1.25 + vec3(0.012, 0.009, 0.005), crust * 0.5);
		// Wet mud: glossy on the heaps' tops and the shoved-up lips, a matte skin in the
		// creases between them, slick in the ruts and wherever it was just turned over.
		rough = mix(0.62, 0.34, crest) * mix(1.0, 0.8, wetness);
		rough = mix(rough, 0.75, crust * 0.7);
		rough = mix(rough, 0.22, v_berm * 0.8);
		rough = mix(rough, 0.15, t * wetness);
		rough = mix(rough, 0.12, max(v_fresh, margin));
		rough = mix(rough, rough * 0.8, rain_wet); // rain: it all takes a sheen
		col *= mix(0.72, 0.95, crest); // wet earth, darker than the dried crust round it
		col = mix(col, col * 0.75, max(v_berm, v_fresh)); // freshly turned over: wetter, darker
		col = mix(col, col * 0.7, margin); // soaked round the water
		col *= mix(1.0, 0.85, rain_wet);
		// Frozen: the mud sets hard, pales and dulls, and hoarfrost furs the heaps and the lips.
		float rime = freeze * smoothstep(0.55, 0.85, fbm(v_xz * 11.0 + 3.0, 2) + crest * 0.3 + v_berm * 0.3);
		col = mix(col, mix(col, vec3(dot(col, vec3(0.33))), 0.4) * 1.1 + vec3(0.015, 0.016, 0.02), freeze * 0.7);
		col = mix(col, vec3(0.62, 0.65, 0.69), rime * 0.4 * (1.0 - water));
		rough = mix(rough, 0.8, freeze);
	}

	// Standing water: muddy brown, murky, only lets the mud through where it is shallow,
	// with silt clouding it. At a glancing angle it mirrors the sky (and with SSR, the trees).
	// Frozen, it is a sheet of ice: the dark water under clear glass, white cracks and trapped
	// bubbles, a frosted rim where it froze to the bank, and no ripples.
	if (water > 0.0) {
		vec3 water_c = is_snow ? vec3(0.17, 0.17, 0.16) : vec3(0.06, 0.045, 0.03); // dark, so the sky and trees show in it
		float silt = smoothstep(0.55, 0.85, fbm(v_xz * 1.1 + vec2(TIME * 0.015, 0.0), 3));
		water_c = mix(water_c, is_snow ? vec3(0.3, 0.29, 0.27) : vec3(0.17, 0.125, 0.08), silt * 0.45);
		float shallow = 1.0 - smoothstep(0.0, 0.05, v_water);
		water_c = mix(water_c, col * 0.8, shallow * 0.55);
		float wrough = 0.02;
		if (freeze > 0.0) {
			float crack = smoothstep(0.03, 0.0, cell_edge(v_xz * 1.6)) * 0.7 + smoothstep(0.015, 0.0, cell_edge(v_xz * 5.0 + 3.0)) * 0.15;
			float bubbles = step(0.9, hash12(floor(v_xz * 40.0))) * smoothstep(0.4, 0.7, fbm(v_xz * 1.5, 2));
			float rim = 1.0 - smoothstep(0.0, 0.008, v_water);
			vec3 ice_c = water_c * 0.7 + vec3(0.02, 0.028, 0.035);
			float white = clamp(crack + bubbles * 0.6 + rim * 0.7, 0.0, 1.0);
			water_c = mix(water_c, mix(ice_c, vec3(0.72, 0.76, 0.8), white * 0.65), freeze);
			wrough = mix(0.02, mix(0.03, 0.5, white), freeze);
		}
		col = mix(col, water_c, water);
		rough = mix(rough, wrough, water);
		vec2 rip = ripples(v_xz) * (1.0 - freeze);
		n_w = normalize(mix(n_w, normalize(vec3(-rip.x, 1.0, -rip.y)), water));
	}
	// A frozen rut just driven or walked through: broken ice and brown slush, not a sheet.
	if (!is_snow && freeze > 0.0) {
		float broken = freeze * smoothstep(0.05, 0.4, v_fresh) * smoothstep(0.0, 0.03, v_depth);
		vec3 slush = mix(vec3(0.15, 0.11, 0.075), vec3(0.72, 0.74, 0.78), 0.12 + 0.4 * smoothstep(0.5, 0.75, fbm(v_xz * 9.0, 2)));
		col = mix(col, slush, broken);
		rough = mix(rough, 0.3, broken);
	}

	// Snow lies on the mud as on the ground round it. A track made since cuts down through it
	// to the mud (churned clods of white on its lips), and falling snow covers the track again.
	// Unfrozen water swallows the flakes; ice holds them.
	float cover = 0.0;
	if (!is_snow && weather_snow > 0.01) {
		float exposed = (v_depth > 0.01 && v_age < 1.0e4) ? exp(-v_age * snowfall / 120.0) : 0.0;
		cover = smoothstep(0.15, 0.5, weather_snow * 1.3 + (crest - 0.5) * 0.3 - v_depth * 1.5) * (1.0 - exposed);
		cover *= mix(1.0 - water, 1.0, freeze);
		vec3 snow_c = mix(vec3(0.8, 0.83, 0.88), vec3(0.64, 0.68, 0.76), sqrt(t)) * (0.93 + 0.07 * fine);
		float clods = smoothstep(0.62, 0.7, fbm(v_xz * 9.0, 2)) * weather_snow * (1.0 - cover) * max(v_berm, smoothstep(0.0, 0.05, v_depth));
		col = mix(col, snow_c * 0.9, clods * 0.7);
		col = mix(col, snow_c, cover);
		rough = mix(rough, 0.75, cover);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);

	if (!is_snow) {
		// A wet film over all of it: the sharp highlight that says "this is mud".
		// (only where it's freshly turned or lying wet: the untouched top has dulled over;
		// none on frozen or snowed-over mud)
		CLEARCOAT = (1.0 - water) * (1.0 - freeze) * (1.0 - cover) * wetness * max(max(0.15, 0.25 * rain_wet) * crest, 0.7 * max(max(sqrt(t), v_berm), max(v_fresh, margin)));
		CLEARCOAT_ROUGHNESS = mix(0.3, 0.08, max(t, max(margin, rain_wet)));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.75, water);
}
