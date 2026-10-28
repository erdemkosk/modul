shader_type spatial;
render_mode cull_disabled;

// The open world's ground (scripts/world_terrain.gd). Every chunk is a flat grid: the vertex
// stage lifts it to the heightmap; the fragment stage lights it with normals from the heightmap
// (so coarse far chunks keep full lighting detail) and paints it from the splat maps with
// procedural detail: meadow grass, bare dirt, forest floor, rock with strata, snow, gravel roads,
// wet ground and shore gravel. Global weather uniforms darken it when wet, add puddles and rain
// ripples in hollows and lay snow on flat ground.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splat : filter_linear_mipmap, repeat_disable;
uniform sampler2D splat2 : filter_linear_mipmap, repeat_disable;
uniform sampler2D soft_map : filter_linear, repeat_disable; // RG: mud, deep snow (WorldTerrain._build_soft)
uniform sampler2D patch_flags : filter_nearest, repeat_disable; // 1 where a rut patch draws the ground
uniform sampler2D burn_mask : filter_linear, repeat_disable; // 1 m cells burnt black (GrassFire)
uniform float tile_size = 32.0;
uniform float map_half = 1024.0;
uniform float map_size = 2049.0;

global uniform float weather_wetness;
global uniform float weather_snow;
global uniform float weather_rain;
global uniform float weather_ice;

varying vec3 world_pos;
varying float skirt;

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

// Voronoi-ish pebbles: distance to nearest jittered point.
float pebbles(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + vec2(hash12(i + o), hash12(i + o + 17.0)) - f;
			d = min(d, dot(r, r));
		}
	}
	return sqrt(d);
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

// Noise projected from three sides and blended by the normal, so steep faces get detail of
// their own instead of the top-down pattern stretched into streaks.
float tri_fbm(vec3 p, vec3 w, float s, int oct) {
	return fbm(p.zy * s, oct) * w.x + fbm(p.xz * s, oct) * w.y + fbm(p.xy * s, oct) * w.z;
}

float tri_pebbles(vec3 p, vec3 w, float s) {
	return pebbles(p.zy * s) * w.x + pebbles(p.xz * s) * w.y + pebbles(p.xy * s) * w.z;
}

float height_tex(vec2 xz) {
	return texture(heightmap, (xz + map_half + 0.5) / map_size).r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	ivec2 t = clamp(ivec2(round(world_pos.xz)) + ivec2(int(map_half)), ivec2(0), ivec2(int(map_size) - 1));
	float h = texelFetch(heightmap, t, 0).r;
	skirt = VERTEX.y < -0.5 ? 1.0 : 0.0;
	VERTEX.y = h - skirt * 4.0;
	world_pos.y = VERTEX.y;
}

void fragment() {
	vec2 sm = texture(soft_map, (world_pos.xz + map_half) / (map_size - 1.0)).rg;
	ivec2 tile = clamp(ivec2(floor((world_pos.xz + map_half) / tile_size)), ivec2(0), textureSize(patch_flags, 0) - ivec2(1));
	if (max(sm.r, sm.g) > 0.5 && texelFetch(patch_flags, tile, 0).r > 0.5) {
		discard; // a rut patch draws this bit
	}
	vec2 xz = world_pos.xz;
	vec2 uv = (xz + map_half + 0.5) / map_size;
	float dist = length(VERTEX);

	// Heightmap normal (central differences at 1 m).
	float e = 1.0;
	float hl = height_tex(xz - vec2(e, 0.0));
	float hr = height_tex(xz + vec2(e, 0.0));
	float hd = height_tex(xz - vec2(0.0, e));
	float hu = height_tex(xz + vec2(0.0, e));
	vec3 n = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	float slope = 1.0 - n.y;

	vec4 s1 = texture(splat, uv);
	vec4 s2 = texture(splat2, uv);
	float rock = s1.r;
	float snow = s1.g;
	float road = s1.b;
	float meadow = s1.a;
	float forest = s2.r;
	float wet = s2.g;
	float shore = s2.b;
	float dry = smoothstep(0.15, 0.75, s2.a + (fbm(xz * 0.09, 4) - 0.5) * 0.4); // the eastern steppe

	// Break up splat edges with noise so nothing looks like a texture border.
	float big = fbm(xz * 0.012, 4);
	float mid = fbm(xz * 0.09, 4);
	float fine = fbm(xz * 0.8, 3);
	float edge_n = (mid - 0.5) * 0.5 + (fine - 0.5) * 0.15;
	rock = smoothstep(0.35, 0.65, rock + edge_n);
	snow = smoothstep(0.3, 0.7, snow + edge_n * 0.8);
	// Snow doesn't hold on a cliff: past ~45 degrees it slides off and the rock shows through,
	// streaked with what lodges on the ledges.
	float steep = smoothstep(0.28, 0.5, slope + (mid - 0.5) * 0.2);
	rock = max(rock, snow * steep);
	snow *= 1.0 - steep * 0.85;
	road = smoothstep(0.25, 0.75, road + (fine - 0.5) * 0.35);
	meadow = smoothstep(0.2, 0.8, meadow + edge_n);

	// --- Layers ---
	vec3 grass_a = vec3(0.12, 0.23, 0.05);
	vec3 grass_b = vec3(0.26, 0.36, 0.09);
	vec3 grass_dry = vec3(0.31, 0.28, 0.16);
	vec3 grass_c = mix(mix(grass_a, grass_b, big), grass_dry, smoothstep(0.55, 0.85, mid) * 0.6);
	grass_c *= 0.94 + 0.12 * fine; // painted: broad patches carry the variety, not speckle
	// Seen from afar a meadow is never one flat colour: lusher hollows, paler sun-dried
	// rises, clover-dark patches and flowering ones, all at the scale of tens of metres.
	float swale = fbm(xz * 0.025 + 31.0, 3);
	grass_c *= mix(0.78, 1.12, swale);
	grass_c = mix(grass_c, vec3(0.08, 0.13, 0.05), smoothstep(0.62, 0.8, fbm(xz * 0.045 + 5.0, 3)) * 0.45);
	grass_c = mix(grass_c, vec3(0.3, 0.29, 0.13), smoothstep(0.66, 0.85, fbm(xz * 0.06 + 77.0, 3)) * 0.35);
	grass_c *= mix(1.0, 0.82, smoothstep(0.02, 0.2, slope)); // steeper banks: thinner, earthier

	vec3 dirt_c = mix(vec3(0.16, 0.125, 0.09), vec3(0.23, 0.19, 0.14), mid) * (0.94 + 0.12 * fine);
	vec3 floor_c = mix(vec3(0.17, 0.13, 0.08), vec3(0.24, 0.2, 0.12), fine);
	floor_c = mix(floor_c, vec3(0.16, 0.2, 0.09), smoothstep(0.5, 0.8, mid) * 0.7); // moss
	// Layered rock bands; faded out with distance, where they would alias into moire.
	float strata = mix(0.5, sin(world_pos.y * 1.7 + fbm(xz * 0.05, 3) * 9.0) * 0.5 + 0.5, 1.0 - smoothstep(40.0, 160.0, dist));
	// Rock detail from three sides (not stretched down cliffs): broken into blocks close up,
	// with mottling at two scales.
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	float rock_fine = fine;
	float blocks = 0.5;
	if (rock > 0.01 && dist < 220.0) {
		float near_k = 1.0 - smoothstep(90.0, 220.0, dist);
		rock_fine = mix(fine, tri_fbm(world_pos, tw, 0.8, 3), near_k);
		blocks = mix(0.5, smoothstep(0.05, 0.6, tri_pebbles(world_pos, tw, 0.45)), near_k * (1.0 - smoothstep(30.0, 90.0, dist)));
	}
	// (darker and more broken than it was: in full sun a mountain face read as pale plaster)
	vec3 rock_c = mix(vec3(0.15, 0.148, 0.142), vec3(0.34, 0.325, 0.3), strata * 0.35 + rock_fine * 0.3 + big * 0.35);
	// Big buttresses and slabs, each a little different in tone, so a face reads at a distance.
	float slab = tri_fbm(world_pos, tw, 0.035, 3);
	rock_c *= mix(0.72, 1.12, smoothstep(0.3, 0.7, slab));
	// Bedding that survives into the distance (broad bands, not the fine strata).
	rock_c *= mix(0.88, 1.06, sin(world_pos.y * 0.21 + slab * 5.0) * 0.5 + 0.5);
	rock_c *= mix(0.86, 1.05, blocks); // the joints between blocks hold shadow and grime
	rock_c = mix(rock_c, vec3(0.24, 0.2, 0.15), smoothstep(0.6, 0.9, mid) * 0.55); // iron-stained
	rock_c = mix(rock_c, vec3(0.13, 0.14, 0.15), smoothstep(0.55, 0.8, big) * 0.4); // cold, blue-grey faces
	// Gullies and steep faces in shadow-dark streaks running down the slope (they survive into
	// the distance, where strata fade), so a mountain reads as rock, not as grey paint.
	float gully = smoothstep(0.55, 0.85, fbm(vec2(xz.x * 0.05 + n.x * 3.0, world_pos.y * 0.02 + xz.y * 0.01), 3));
	rock_c *= mix(1.0, 0.62, gully * smoothstep(0.25, 0.6, slope));
	rock_c = mix(rock_c, vec3(0.25, 0.3, 0.17), smoothstep(0.55, 0.8, n.y + mid * 0.3) * 0.5); // lichen on ledges
	// Snow: wind-packed and drifted, never one flat white: blue-grey in the hollows and the lee
	// of drifts, bright crust on the rises, old grey snow in patches; the tracks of the wind.
	float drift = fbm(xz * 0.06 + 23.0, 3);
	// (a little under true snow's albedo: in full sun the old values burned out to one flat white)
	vec3 snow_c = mix(vec3(0.58, 0.63, 0.72), vec3(0.76, 0.78, 0.81), smoothstep(0.3, 0.75, drift));
	snow_c = mix(snow_c, vec3(0.7, 0.71, 0.72), smoothstep(0.6, 0.85, fbm(xz * 0.03 + 41.0, 3)) * 0.35);
	snow_c *= 0.94 + 0.08 * fine;
	float peb = pebbles(xz * 9.0);
	vec3 road_c = mix(vec3(0.24, 0.22, 0.18), vec3(0.3, 0.28, 0.24), smoothstep(0.15, 0.5, peb) * 0.2 + mid * 0.5 + 0.15); // gravel as a tone, not a pattern
	road_c *= 0.94 + 0.1 * fine;
	vec3 wet_c = mix(vec3(0.16, 0.13, 0.09), vec3(0.2, 0.22, 0.12), mid);
	vec3 shore_c = mix(vec3(0.3, 0.28, 0.25), vec3(0.2, 0.18, 0.15), smoothstep(0.1, 0.45, pebbles(xz * 4.0)));

	vec3 base = mix(dirt_c, grass_c, meadow);
	base = mix(base, floor_c, forest * (1.0 - meadow * 0.5));
	// Steppe: sun-baked ochre earth, cracked into plates, dusty, with dry tussocks.
	if (dry > 0.01) {
		vec3 dry_c = mix(vec3(0.22, 0.18, 0.12), vec3(0.33, 0.28, 0.19), smoothstep(0.3, 0.75, mid));
		dry_c *= mix(0.8, 1.1, fbm(xz * 0.03 + 13.0, 3)); // darker swales, bleached rises
		float plates = abs(fbm(xz * 0.55, 3) - 0.5);
		float crack = smoothstep(0.035, 0.0, plates) * (1.0 - smoothstep(25.0, 70.0, dist));
		dry_c = mix(dry_c, dry_c * 0.55, crack);
		float tuft = smoothstep(0.62, 0.8, fbm(xz * 1.3 + 7.0, 3));
		dry_c = mix(dry_c, vec3(0.38, 0.33, 0.17), tuft * 0.7);
		dry_c *= 0.88 + 0.24 * fine;
		base = mix(base, dry_c, dry);
	}
	base = mix(base, wet_c, wet * 0.85);
	base = mix(base, shore_c, shore);
	base = mix(base, road_c, road);
	base = mix(base, rock_c, rock);
	float rough = mix(0.92, 0.85, rock);

	// --- Soft ground: mud with a damp fringe, standing water in the deepest, deep snow ---
	// The fringe is soaked and smeared: dark, damp earth and mud carried out onto the road and
	// the grass by wheels and boots, fading over a few metres.
	float mud_f = smoothstep(0.2, 0.5, sm.r + (fine - 0.5) * 0.08);
	float mud_in = smoothstep(0.49, 0.53, sm.r);
	vec3 mud_c = mix(vec3(0.095, 0.068, 0.046), vec3(0.15, 0.108, 0.07), fbm(xz * 0.35, 3)) * (0.85 + 0.3 * fine);
	mud_c = mix(mud_c, vec3(0.058, 0.043, 0.03), smoothstep(0.62, 0.9, sm.r));
	mud_c *= mix(1.0, 0.85, weather_wetness);
	float fringe = mud_f * (1.0 - mud_in);
	base = mix(base, base * 0.6 + vec3(0.02, 0.015, 0.01), fringe);
	base = mix(base, vec3(0.13, 0.095, 0.06), fringe * smoothstep(0.35, 0.5, sm.r) * (0.4 + 0.4 * road));
	rough = mix(rough, mix(0.6, 0.3, smoothstep(0.3, 0.5, sm.r)), mud_f);
	base = mix(base, mud_c, mud_in);
	rough = mix(rough, mix(0.42, 0.18, smoothstep(0.6, 0.9, sm.r)) * mix(1.0, 0.6, weather_wetness), mud_in);
	// Pools in the hollows between the heaps of the wettest mud (the rut patches draw the same
	// water close up: soft_ground.gdshader pool_amount).
	float pool_amt = smoothstep(0.8, 0.95, sm.r + (fbm(xz * 0.2 + 11.0, 3) - 0.5) * 0.5 + weather_wetness * 0.08);
	float heaps = fbm(xz * 0.9, 3);
	heaps = smoothstep(0.25, 0.8, heaps) * smoothstep(0.25, 0.8, heaps);
	float pool = mud_in * step(0.01, pool_amt) * smoothstep(0.0, 0.03, 0.333 * pool_amt - 0.083 - heaps);
	float mud_water = pool;
	// (deep snow too slides off the cliffs: the rock face shows, painted as rock above)
	float snow_f = smoothstep(0.28, 0.5, sm.g) * (1.0 - steep * 0.85);
	float snow_in = smoothstep(0.47, 0.53, sm.g) * (1.0 - steep * 0.85);
	if (sm.g > 0.3) {
		base = mix(base, rock_c, steep * smoothstep(0.3, 0.5, sm.g));
	}
	base = mix(base, mix(base, vec3(0.74, 0.77, 0.81), 0.55), snow_f * (1.0 - snow_in));
	base = mix(base, snow_c, snow_in);
	rough = mix(rough, 0.75, max(snow_in, snow_f * 0.5));

	// --- Weather ---
	// Wet weather: everything darkens and takes a sheen, the bare earth and the roads most
	// (grass blades shed it, so the meadow keeps more of its roughness).
	float wet_amt = clamp(weather_wetness * (1.0 - rock * 0.4) + wet * 0.35, 0.0, 1.0) * (1.0 - weather_ice); // frozen, it is ice, not wet
	base *= mix(1.0, mix(0.55, 0.7, meadow), wet_amt);
	rough = mix(rough, mix(0.22, 0.5, meadow * (1.0 - road)), wet_amt * 0.85);
	// Puddles: standing water in the dips of roads and flat ground (and in marshy ground even
	// in dry weather), spreading as the rain goes on and shrinking back as it dries
	// (WorldTerrain.puddle_at: the tyres meet the same water). A soaked dark margin round each.
	float flat_k = smoothstep(0.07, 0.015, slope) * (1.0 - rock) * (1.0 - mud_in) * (1.0 - dry);
	float pud_n = fbm(xz * 0.07 + 3.1, 3) + (fbm(xz * 0.6 + 1.7, 2) - 0.5) * 0.16;
	float pud_thr = mix(0.86, 0.67, weather_wetness) - s1.b * 0.12 - s2.g * 0.14;
	float puddle = smoothstep(pud_thr, pud_thr + 0.012, pud_n) * flat_k;
	float pud_rim = smoothstep(pud_thr - 0.06, pud_thr, pud_n) * flat_k * (1.0 - puddle);
	base *= mix(1.0, 0.62, pud_rim);
	rough = mix(rough, 0.12, pud_rim);
	float water_all = max(puddle, mud_water);
	float freeze = clamp(weather_ice * 1.4, 0.0, 1.0); // frozen hard (Weather.ice)
	// Frozen mud has set: paler, dull, no wet sheen.
	base = mix(base, mix(base, vec3(dot(base, vec3(0.33))), 0.4) * 1.1 + vec3(0.015, 0.016, 0.02), mud_in * freeze * 0.7);
	rough = mix(rough, 0.8, mud_in * freeze);
	vec3 detail_n = vec3(0.0);
	if (water_all > 0.01) {
		// Rain ripples: expanding rings in jittered cells, two sizes overlapping.
		for (int layer = 0; layer < 2; layer++) {
			vec2 p = xz * (layer == 0 ? 2.6 : 4.1) + float(layer) * 13.0;
			vec2 ci = floor(p);
			float t = TIME * (1.2 + 0.3 * float(layer)) + hash12(ci) * 7.0;
			vec2 dv = fract(p) - 0.5 - (vec2(hash12(ci + 3.0), hash12(ci + 9.0)) - 0.5) * 0.4;
			float r = length(dv);
			float ring = sin((r - fract(t) * 0.5) * 42.0) * smoothstep(0.5, 0.0, r) * (1.0 - fract(t));
			detail_n.xz += dv / max(r, 0.001) * ring * 0.2 * weather_rain * (1.0 - freeze);
		}
		// Brown, murky water (the road's own dirt in it), a mirror at a glancing angle.
		vec3 water_c = mix(vec3(0.09, 0.075, 0.055), vec3(0.075, 0.058, 0.04), max(mud_water, wet));
		water_c = mix(water_c, vec3(0.15, 0.115, 0.075), smoothstep(0.55, 0.85, fbm(xz * 1.1 + 4.0, 3)) * 0.35);
		if (freeze > 0.0) {
			// Frozen over: dark water under clear ice, white cracks and bubbles, a frosted rim.
			float crack = smoothstep(0.035, 0.0, cell_edge(xz * 2.2)) * 0.8 + smoothstep(0.02, 0.0, cell_edge(xz * 6.0 + 3.0)) * 0.35;
			float bubbles = step(0.9, hash12(floor(xz * 40.0))) * smoothstep(0.4, 0.7, fbm(xz * 1.5, 2));
			float rim_i = puddle * (1.0 - smoothstep(pud_thr + 0.012, pud_thr + 0.04, pud_n));
			float white = clamp(crack + bubbles * 0.6 + rim_i * 0.8, 0.0, 1.0);
			vec3 ice_c = mix(water_c * 0.7 + vec3(0.02, 0.028, 0.035), vec3(0.72, 0.76, 0.8), white * 0.8);
			water_c = mix(water_c, ice_c, freeze);
		}
		base = mix(base, water_c, water_all);
		rough = mix(rough, 0.02, water_all);
	}
	float puddle_flat = water_all;
	float snow_cover = smoothstep(0.25, 0.6, weather_snow * 1.2 * n.y + (fine - 0.5) * 0.3 - road * 0.25 * weather_snow);
	float snow_total = max(snow, snow_cover * smoothstep(0.55, 0.85, n.y));
	base = mix(base, snow_c, snow_total);
	rough = mix(rough, 0.7, snow_total);

	// Frost and black ice (Weather.ice). Hoarfrost greys every meadow and bank with white rime.
	// Where water lay (roads, wet ground, hollows: the same pattern WorldTerrain.ice_patch
	// gives the tyres) it has frozen to a glassy, dark sheet that mirrors the sky, with a white
	// frosted rim round each patch.
	float glaze = 0.0;
	if (weather_ice > 0.01) {
		vec3 bare_c = base;
		float rime = weather_ice * smoothstep(0.3, 0.7, fine + 0.25) * (1.0 - rock * 0.6);
		base = mix(base, vec3(0.6, 0.63, 0.66), rime * 0.28);
		rough = mix(rough, 0.6, rime * 0.5);
		// Only on roads and wet ground, as WorldTerrain.surface_at freezes them.
		float lies_on = clamp(road + wet, 0.0, 1.0);
		float n_ice = vnoise(xz * 0.045) * 0.7 + vnoise(xz * 0.19 + 3.0) * 0.3;
		float level = weather_ice * (smoothstep(0.42, 0.7, n_ice) + lies_on * 0.12);
		glaze = smoothstep(0.46, 0.54, level) * smoothstep(0.35, 0.6, lies_on) * (1.0 - rock) * (1.0 - snow_total * 0.7);
		float rim = smoothstep(0.3, 0.45, level) * (1.0 - smoothstep(0.45, 0.58, level)) * smoothstep(0.35, 0.6, lies_on);
		base = mix(base, vec3(0.72, 0.76, 0.8), rim * 0.4 * (1.0 - rock));
		vec3 ice_c = bare_c * 0.3 + vec3(0.015, 0.025, 0.035); // clear ice: the dark road under glass
		ice_c *= 0.9 + 0.2 * vnoise(xz * 3.0); // trapped bubbles and cracks
		base = mix(base, ice_c, glaze);
		rough = mix(rough, 0.03, glaze);
	}

	// Close-up bump from the detail noise (fades out with distance).
	float bump_fade = 1.0 - smoothstep(30.0, 120.0, dist);
	if (bump_fade > 0.0) {
		// Broad, gentle relief (lumps, ledges): sampled 15 cm apart on wrapped coordinates, so
		// neither noise steps nor float precision turn into dark scratches.
		vec2 q = mod(xz, 1024.0);
		float b0 = fbm(q * 0.7, 3);
		float bx = fbm((q + vec2(0.15, 0.0)) * 0.7, 3);
		float bz = fbm((q + vec2(0.0, 0.15)) * 0.7, 3);
		float k = mix(0.25, 0.7, rock) * (1.0 - snow_total * 0.7) * (1.0 - puddle_flat) * (1.0 - glaze);
		if (max(snow_total, snow_in) > 0.01) {
			// Wind ripples in the snow (sastrugi): long low ridges across the wind, wavering.
			vec2 wdir = normalize(vec2(0.8, 0.6));
			float ph = dot(q, wdir) * 2.4 + fbm(q * 0.15, 2) * 6.0;
			float rip = sin(ph) * smoothstep(0.35, 0.7, fbm(q * 0.08 + 9.0, 2));
			// and the broad drifts and scoops the ripples ride on
			float d0 = fbm(q * 0.12 + 5.0, 2);
			float dx = fbm((q + vec2(0.6, 0.0)) * 0.12 + 5.0, 2);
			float dz = fbm((q + vec2(0.0, 0.6)) * 0.12 + 5.0, 2);
			float sk = max(snow_total, snow_in) * bump_fade;
			detail_n.xz += wdir * rip * 0.16 * sk + vec2(d0 - dx, d0 - dz) * 2.2 * sk;
		}
		float top = mix(1.0, tw.y, rock); // on rock faces the top-down relief would only streak
		detail_n.x += (b0 - bx) * 2.0 * k * bump_fade * top;
		detail_n.z += (b0 - bz) * 2.0 * k * bump_fade * top;
		if (rock > 0.01 && tw.y < 0.98) {
			// The faces' own relief, seen from the side: ledges, bulges and the edges of blocks.
			vec3 q3 = mod(world_pos, vec3(1024.0));
			float kr = 0.3 * rock * (1.0 - snow_total * 0.7) * bump_fade;
			float s0 = fbm(q3.zy * 0.7, 3) + blocks * 0.3;
			float sz = fbm((q3.zy + vec2(0.15, 0.0)) * 0.7, 3) + blocks * 0.3;
			float sy = fbm((q3.zy + vec2(0.0, 0.15)) * 0.7, 3) + blocks * 0.3;
			detail_n.z += (s0 - sz) * 4.5 * kr * tw.x;
			detail_n.y += (s0 - sy) * 4.5 * kr * tw.x;
			float t0 = fbm(q3.xy * 0.7, 3);
			float tx = fbm((q3.xy + vec2(0.15, 0.0)) * 0.7, 3);
			float ty = fbm((q3.xy + vec2(0.0, 0.15)) * 0.7, 3);
			detail_n.x += (t0 - tx) * 4.5 * kr * tw.z;
			detail_n.y += (t0 - ty) * 4.5 * kr * tw.z;
		}
	}
	n = normalize(n + detail_n);
	// Ambient occlusion in creases and under the forest canopy.
	float ao = mix(1.0, 0.72, forest) * mix(1.0, 0.85, smoothstep(0.5, 0.2, fine) * (1.0 - snow_total));

	// Glints: a few ice crystals in the snow catch the light, close up.
	float glint = step(0.985, hash12(floor(xz * 55.0))) * max(snow_total, snow_in) * (1.0 - smoothstep(6.0, 25.0, dist));
	rough = mix(rough, 0.05, glint);
	// Burnt ground (GrassFire): black char, grey-white ash in drifts, soft-edged.
	float burnt = texture(burn_mask, (xz + map_half) / (map_size - 1.0)).r;
	if (burnt > 0.01) {
		float drift = fbm(xz * 1.4 + 7.0, 2);
		vec3 coal = mix(vec3(0.03, 0.027, 0.024), vec3(0.36, 0.34, 0.31), smoothstep(0.58, 0.82, drift));
		base = mix(base, coal, smoothstep(0.05, 0.7, burnt) * 0.93);
		rough = mix(rough, 0.96, burnt);
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = mix(0.4, 0.9, glaze);
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
