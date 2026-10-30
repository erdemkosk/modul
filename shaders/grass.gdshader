shader_type spatial;
render_mode cull_disabled;

// Grass round the camera (scripts/world_decor.gd). One MultiMesh of blade clumps whose instances
// are never moved on the CPU: the node sits on the camera snapped to the grid, and each instance
// works out its own cell from INSTANCE_ID, jitters inside it by a hash of the world cell (so
// clumps stay put as the grid follows the camera), stands on the heightmap and only grows where
// the meadow splat says so.
//
// A meadow, not stubble: blades rise out of the ground's own colour (no black stumps), catch the
// light on rounded normals and glow when the sun is behind them, vary in height and tone in
// patches, and bend in gusts that roll across the field on the global wind.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D splat2 : filter_linear, repeat_disable;
uniform sampler2D soft_mask : filter_nearest, repeat_disable;
uniform sampler2D soft_map : filter_linear, repeat_disable; // RG mud, deep snow: the same outline the ground draws
uniform float map_half = 1024.0;
uniform float map_size = 2049.0;
uniform float lake_level = 18.0;
uniform int grid = 180;
uniform float spacing = 0.5;
// Two of these (scripts/world_decor.gd): the fine field round you, and a sparse one of broader
// clumps from `inner_radius` out (0: the fine one). Where they meet neither grows or shrinks:
// the fine field thins out clump by clump as the sparse one comes in, each clump whole or not
// there at all, so nothing is seen springing up as you walk.
uniform float inner_radius = 0.0;
uniform float clump_scale = 1.0;
uniform vec3 color_a : source_color = vec3(0.11, 0.25, 0.05);
uniform vec3 color_b : source_color = vec3(0.3, 0.44, 0.1);

global uniform vec3 weather_wind;
global uniform vec4 grass_press; // xyz your machine, w how far round it the grass is pressed down
uniform float height_k = 0.55; // (a meadow you can see a log lying in, a wheel turning in)
global uniform vec4 campfire_clear_a; // xyz the fire, w the radius cleared round it (Campfire)
global uniform vec4 campfire_clear_b;
global uniform float weather_wetness;
global uniform float weather_snow;
global uniform float weather_ice;

varying float v_h;
varying vec3 v_col;
varying vec3 v_root;

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

// The meadow colour the ground paints under this clump (world_terrain.gdshader, its large-scale
// terms): the blades take it, so near grass and the far field are one green, not two.
vec3 ground_grass(vec2 xz) {
	float big = fbm(xz * 0.012, 3); // an octave or two fewer than the ground: per vertex, and the fine ones don't show on a blade
	float mid = fbm(xz * 0.09, 2);
	vec3 c = mix(mix(vec3(0.12, 0.23, 0.05), vec3(0.26, 0.36, 0.09), big), vec3(0.31, 0.28, 0.16), smoothstep(0.55, 0.85, mid) * 0.6);
	c *= mix(0.78, 1.12, fbm(xz * 0.025 + 31.0, 2));
	c = mix(c, vec3(0.08, 0.13, 0.05), smoothstep(0.62, 0.8, fbm(xz * 0.045 + 5.0, 2)) * 0.45);
	return c;
}

void vertex() {
	vec3 node = MODEL_MATRIX[3].xyz;
	int ix = INSTANCE_ID % grid;
	int iz = INSTANCE_ID / grid;
	// round, not floor: the node sits on a multiple of spacing, and floor of e.g. 27.9999 would
	// shift the whole grid one cell and reshuffle every clump (flicker while walking).
	vec2 cell = round(node.xz / spacing) + vec2(float(ix - grid / 2), float(iz - grid / 2));
	vec2 jitter = vec2(hash12(cell), hash12(cell + 17.3));
	vec2 xz = (cell + jitter) * spacing;
	vec2 uv = (xz + map_half + 0.5) / map_size;
	float ground = texture(heightmap, uv).r;
	vec4 s1 = texture(splat, uv);
	vec4 s2 = texture(splat2, uv);
	float density = s1.a * (1.0 - s1.r) * (1.0 - s1.g) * (1.0 - s1.b * 1.5) * (1.0 - s2.b) * (1.0 - s2.r * 0.6);
	density = max(density * (1.0 - s2.a * 0.8), s2.a * 0.22); // steppe: sparse tussocks
	// Patches: some of the meadow grows tall and thick, some is grazed short and thin.
	float patchy = vnoise(xz * 0.11) * 0.7 + vnoise(xz * 0.5) * 0.3;
	density *= mix(0.55, 1.35, patchy);
	float h3 = hash12(cell + 5.1);
	float dist = length(xz - node.xz);
	float radius = float(grid / 2) * spacing;
	float keep;
	if (inner_radius > 0.0) {
		keep = smoothstep(inner_radius - 6.0, inner_radius + 6.0, dist); // comes in as the fine one goes
	} else {
		keep = 1.0 - smoothstep(radius * 0.62, radius * 0.9, dist) * 0.85; // thins out to a sixth
	}
	keep *= 1.0 - smoothstep(radius * 0.8, radius * 0.98, dist) * (inner_radius > 0.0 ? 1.0 : 0.0);
	// A clump's own number against how many are kept here: as you come nearer it grows up out of
	// the ground over a few metres rather than popping in whole (and shrinks away as you go).
	float fade = smoothstep(-0.2, 0.0, keep - hash12(cell + 41.7));
	if (inner_radius <= 0.0) {
		fade *= 1.0 - smoothstep(radius * 0.92, radius * 0.99, dist);
	}
	ivec2 sc = clamp(ivec2(floor(xz + map_half)), ivec2(0), textureSize(soft_mask, 0) - ivec2(1));
	vec2 sm = textureLod(soft_map, (xz + map_half) / (map_size - 1.0), 0.0).rg;
	bool soft = texelFetch(soft_mask, sc, 0).r > 0.5 || max(sm.r, sm.g) > 0.4; // nothing grows in mud or churned ground
	float tall = mix(0.75, 1.5, patchy) * (0.75 + 0.55 * hash12(cell + 9.7));
	float scale = (h3 < density * 1.8 && !soft && ground > lake_level + 0.3) ? fade * tall : 0.0;
	scale *= 1.0 - weather_snow * 0.7;
	// Cleared round a fire someone built (Campfire): trodden flat and burnt off.
	scale *= smoothstep(campfire_clear_a.w, campfire_clear_a.w + 0.8, distance(xz, campfire_clear_a.xz));
	scale *= smoothstep(campfire_clear_b.w, campfire_clear_b.w + 0.8, distance(xz, campfire_clear_b.xz));
	// Rotate the clump round Y by a hash.
	float a = hash12(cell + 2.2) * 6.2831;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec3 v = VERTEX * scale * vec3(clump_scale, height_k, clump_scale);
	// Pressed down under your machine and laid over away from it (what it drives over it flattens).
	vec2 off = xz - grass_press.xz;
	float press = (1.0 - smoothstep(grass_press.w * 0.6, grass_press.w, length(off))) * step(abs(ground - grass_press.y), 4.0);
	v.y *= 1.0 - 0.85 * press;
	v.xz += normalize(off + vec2(0.001)) * press * 0.25 * scale;
	// Far off, a blade a couple of centimetres wide is thinner than a pixel and sparkles in and
	// out as the camera moves: the blades get broader with distance so each stays a few
	// pixels wide (the clump reads the same, it just stops crawling).
	v.xz *= 1.0 + smoothstep(6.0, 40.0, dist) * 1.8;
	v.xz = rot * v.xz;
	float hf = clamp(VERTEX.y / 0.8, 0.0, 1.0);
	// Wind: a steady lean, a quick flutter per clump, and gusts that roll across the field.
	float strength = length(weather_wind.xz);
	vec2 dir = strength > 0.001 ? weather_wind.xz / strength : vec2(1.0, 0.0);
	float along = dot(xz, dir);
	float gust = smoothstep(0.35, 0.9, vnoise(vec2(along * 0.06 - TIME * (0.25 + strength * 0.05), dot(xz, vec2(-dir.y, dir.x)) * 0.04)));
	float flutter = sin(TIME * (2.2 + weather_wind.y) + along * 0.5 + hash12(cell) * 6.0);
	float bend = (0.06 + strength * 0.18) * (0.5 + 0.5 * flutter * 0.4) + gust * (0.12 + strength * 0.2);
	v.xz += dir * bend * hf * hf * scale;
	v.y -= bend * 0.35 * hf * hf * scale; // a bent blade is shorter
	v.y *= 1.0 - weather_wetness * 0.15;
	vec3 world = vec3(xz.x, ground, xz.y) + v;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	v_h = hf;
	float tone = hash12(cell + 3.3);
	// The ground's own green (skipped for clumps that don't grow), a touch of tone per clump.
	vec3 ground_c = scale > 0.0 ? ground_grass(xz) : color_a;
	v_col = ground_c * mix(0.92, 1.12, tone) * mix(1.0, 0.85, s2.g); // wetter ground, deeper green
	// Straw on the steppe, where the ground turns dry (its own edge: world_terrain.gdshader).
	float dry = scale > 0.0 ? smoothstep(0.15, 0.75, s2.a + (fbm(xz * 0.09, 2) - 0.5) * 0.4) : s2.a;
	v_col = mix(v_col, vec3(0.4, 0.34, 0.19) * (0.85 + 0.3 * tone), dry);
	v_col = mix(v_col, vec3(0.4, 0.37, 0.18), smoothstep(0.72, 1.0, vnoise(xz * 0.07)) * 0.55); // going to seed
	v_col *= 1.0 + gust * 0.12; // the gust turns the paler underside to the light
	// The ground colour round the root, so the blades grow out of it (the terrain's meadow tones).
	v_root = ground_c * 0.85; // the ground itself round the root: blades grow out of it
	v_root = mix(v_root, vec3(0.3, 0.25, 0.17), dry);
	// Rounded normals: each blade leans its normal out from the clump's centre and up, so the
	// clump shades like a tuft, not a sheet.
	vec3 out_dir = vec3(v.x, 0.0, v.z);
	out_dir = length(out_dir) > 1e-4 ? normalize(out_dir) : vec3(0.0, 0.0, 1.0);
	vec3 n = normalize(out_dir * 0.3 + vec3(0.0, 1.0, 0.0) + vec3(dir.x, 0.0, dir.y) * gust * 0.3);
	NORMAL = (inverse(MODEL_MATRIX) * vec4(n, 0.0)).xyz;
}

void fragment() {
	vec3 c = mix(v_root, v_col, smoothstep(0.0, 0.6, v_h)) * mix(0.95, 1.12, v_h);
	c *= mix(1.0, 0.65, weather_wetness * (1.0 - weather_ice));
	c = mix(c, vec3(0.68, 0.72, 0.76), weather_ice * 0.6 * smoothstep(0.2, 1.0, v_h)); // hoarfrost on the blades
	ALBEDO = c;
	ROUGHNESS = mix(0.75, 0.4, weather_wetness);
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.7;
	AO = mix(0.82, 1.0, v_h); // lit near enough as the ground is, or a field of it reads darker than the field beyond
	AO_LIGHT_AFFECT = 0.6;
}
