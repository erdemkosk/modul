shader_type spatial;
render_mode cull_disabled;

// Trees, bushes, ferns, rocks and logs (scripts/world_props.gd). One shader for all of them,
// swaying in the global wind (trunks bend from the base, leaves and needles flutter),
// darkening when wet and catching snow on upward faces.
//
// The look is a painted miniature. A crown is one mass of colour, not thousands of leaves:
// each tree takes a single colour from a small palette (conifers in deep greens; broadleaves
// through the autumn: green-gold, gold, orange, red), lit as one rounded shape (the normals
// are bent out from the crown's middle), light at the top and dark underneath, glowing where
// the sun comes through. Bark, rock and wood keep the model's colours, softened.

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.85;
uniform float sway = 1.0;          // 0 = rigid (rocks), 1 = a tree's full bend
uniform float leaf = 0.0;          // 1 = foliage: flutter, translucency
uniform float broadleaf = 0.0;     // 1 = leaves (autumn palette), 0 = needles and fronds
uniform float model_height = 15.0; // bend reaches its full amount at this height
// Level of detail, crossfaded instead of popping (scripts/world_props.gd). The detailed mesh
// (lod_role 0) dissolves out, pixel by pixel, over the band lod_near - LOD_BAND .. lod_near
// as the simple one (lod_role 1) dissolves in over the same band with the complementary
// pattern, so a tree is always exactly one whole tree. lod_near <= 0: no fading.
uniform float stone = 0.0;          // 1 = rock and cliff: weathered stone detail (below)
uniform float lod_role = 0.0;
uniform float lod_near = 0.0;
const float LOD_BAND = 28.0; // wide, so the two shapes trade places gradually rather than visibly re-drawing

global uniform vec3 weather_wind;
global uniform float weather_wetness;
global uniform float weather_snow;
global uniform float season_autumn; // 0 green .. 1 the autumn's colours (Seasons)
global uniform vec3 props_lod_center;
global uniform vec4 view_focus; // xyz: what the view is on (your machine); w: 1 when there is one

varying vec3 w_normal;
varying float v_tint;
varying float v_hf;
varying float v_pick;
varying float v_lod; // 0..1 across the crossfade band: 0 = detailed, 1 = simple
varying vec3 w_pos;
varying float v_base_y;

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

float fbm3(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.25 + vnoise(p * 4.1 + 3.3) * 0.125;
}

// Noise from three sides, blended by the normal (no streaks down the faces).
float tri(vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	return fbm3(p.zy * s) * w.x + fbm3(p.xz * s) * w.y + fbm3(p.xy * s) * w.z;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.37, 0.23));
	float strength = length(weather_wind.xz);
	vec2 dir = strength > 0.001 ? weather_wind.xz / strength : vec2(1.0, 0.0);
	float gust = weather_wind.y;
	float hf = clamp(VERTEX.y / model_height, 0.0, 1.0);
	v_hf = hf;
	// The live camera, set each frame by WorldProps (the shader's own camera is the light in the
	// shadow pass); its near set reaches far enough past lod_near to always cover the band.
	vec3 cam = props_lod_center;
	v_lod = lod_near > 0.0 ? smoothstep(lod_near - LOD_BAND, lod_near, length(origin.xz - cam.xz)) : 0.0;
	v_pick = hash12(floor(origin.xz * 0.5) + 0.37);
	float t = TIME;
	float bend = (0.6 + 0.4 * sin(t * (0.7 + gust * 0.8) + phase)) * (0.25 + strength) + sin(t * 1.9 + phase * 1.3) * 0.15 * gust;
	vec3 world_off = vec3(dir.x, 0.0, dir.y) * bend * hf * hf * sway * 0.55;
	vec3 n = NORMAL;
	if (leaf > 0.5) {
		float f = sin(t * 7.0 + dot(VERTEX, vec3(3.1, 2.3, 4.7)) + phase) * (0.02 + 0.05 * strength + 0.04 * gust);
		world_off += vec3(f, f * 0.5, f * 0.7) * hf;
		// Shade the crown as one rounded mass: the normal points out from the crown's axis,
		// a little upward, with only a trace of the leaf's own facing.
		vec3 axis = vec3(0.0, VERTEX.y * 0.85 + model_height * 0.08, 0.0);
		vec3 out_n = VERTEX - axis;
		out_n.y *= 0.6;
		out_n = length(out_n) > 1e-3 ? normalize(out_n) : vec3(0.0, 1.0, 0.0);
		n = normalize(mix(out_n + vec3(0.0, 0.35, 0.0), NORMAL, 0.18));
	}
	// The offset is in world space; take it back into the instance's local space.
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * world_off);
	NORMAL = n;
	w_normal = normalize(mat3(MODEL_MATRIX) * n);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_base_y = MODEL_MATRIX[3].y;
	v_tint = INSTANCE_CUSTOM.r;
}

vec3 crown_colour(float pick) {
	if (broadleaf > 0.5) {
		// Green in spring and summer (a fresh birch green, a darker one), turning in the autumn
		// (season_autumn, Seasons): mostly gold and orange, some still green, a few red; each tree
		// turns on its own day (pick), not all at once.
		vec3 green = mix(vec3(0.3, 0.48, 0.12), vec3(0.45, 0.6, 0.16), fract(pick * 7.13));
		vec3 turned = pick < 0.22 ? vec3(0.42, 0.55, 0.14) : (pick < 0.52 ? vec3(0.9, 0.62, 0.12) : (pick < 0.8 ? vec3(0.92, 0.4, 0.09) : vec3(0.78, 0.17, 0.08)));
		float t = smoothstep(fract(pick * 3.71) * 0.7, fract(pick * 3.71) * 0.7 + 0.3, season_autumn);
		return mix(green, turned, t);
	}
	// Conifers: deep, slightly blue greens, a few brighter.
	return mix(vec3(0.05, 0.16, 0.11), vec3(0.15, 0.29, 0.12), pick);
}

void fragment() {
	// The simple mesh casts every shadow, near or far, whole: its detailed twin casts none
	// (WorldProps), which halves the shadow work round the camera. An orthographic projection
	// here is the sun's shadow pass.
	bool shadow_pass = PROJECTION_MATRIX[2][3] == 0.0;
	if (lod_near > 0.0 && !(shadow_pass && lod_role > 0.5)) {
		// Interleaved gradient noise: a fine, even dither that reads as a soft dissolve.
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (lod_role < 0.5 ? n < v_lod : n >= v_lod) {
			discard;
		}
	}
	// Between the camera and what it's on (view_focus: your machine, the town under the view from
	// above): a tree in the line of sight dissolved round it, trunk and all, wider the further off
	// the view stands (from above a whole crown fills the middle of the screen); the trees either
	// side of the line, and every shadow, as they are.
	if (view_focus.w > 0.5 && !shadow_pass) {
		vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 eye = CAMERA_POSITION_WORLD;
		vec3 d = view_focus.xyz - eye;
		float t = dot(p - eye, d) / max(dot(d, d), 0.001);
		if (t > 0.0 && t < 0.92) {
			float r = max(1.3, length(d) * 0.14);
			float clear = smoothstep(r, r * 1.25, length(p - (eye + d * t))); // (a narrow dissolving rim: a wide one reads as noise)
			float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy + vec2(5.0, 11.0), vec2(0.06711056, 0.00583715))));
			if (n >= clear) {
				discard;
			}
		}
	}
	if ((leaf > 0.5 || sway > 0.5) && !shadow_pass) {
		// A crown the camera's come into (leaves and branches have nothing to stop it; the trunk does):
		// dissolved round the lens, gone within 1.5 m, whole again by 4.5, not a wall of leaf and
		// branch across the view.
		float keep = smoothstep(1.5, 4.5, length(VERTEX));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy + vec2(17.0, 31.0), vec2(0.06711056, 0.00583715))));
		if (n >= keep) {
			discard;
		}
	}
	vec3 c = albedo * COLOR.rgb;
	if (leaf > 0.5) {
		c = crown_colour(v_pick) * mix(0.92, 1.08, v_tint);
		c *= mix(0.5, 1.12, smoothstep(0.1, 0.95, v_hf)); // dark under the crown, light at the top
	} else {
		// Bark, rock, wood: the model's own colour, a touch warmer and cleaner.
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(l), c, 1.2) * vec3(1.06, 1.0, 0.94);
		c *= mix(0.86, 1.14, v_tint);
		if (stone > 0.5) {
			// Weathered stone, not plaster: bedding planes running across the face, darker
			// cracks and the grime that runs down from them, mottling at two scales, lichen and
			// moss on what faces up, earth at the foot. Fades into plain colour far off.
			float dist = length(VERTEX);
			float k = 1.0 - smoothstep(150.0, 400.0, dist);
			float big = tri(w_pos, w_normal, 0.08);
			float mid = tri(w_pos, w_normal, 0.45);
			float bed = sin(w_pos.y * 2.2 + big * 7.0) * 0.5 + 0.5;
			float crack = smoothstep(0.08, 0.0, abs(tri(w_pos, w_normal, 0.9) - 0.5)) * (1.0 - smoothstep(20.0, 80.0, dist));
			float streak = smoothstep(0.55, 0.85, fbm3(vec2(dot(w_pos.xz, vec2(0.7, 0.7)) * 0.6, w_pos.y * 0.05)));
			c *= mix(1.0, mix(0.72, 1.08, mid) * mix(0.9, 1.04, bed), k);
			c = mix(c, c * vec3(0.55, 0.52, 0.5), max(crack * 0.7, streak * 0.35 * (1.0 - w_normal.y)) * k);
			c = mix(c, c * vec3(0.78, 0.72, 0.62), smoothstep(0.55, 0.8, big) * 0.5); // iron and dust
			float up = smoothstep(0.45, 0.85, w_normal.y + (mid - 0.5) * 0.5);
			c = mix(c, vec3(0.22, 0.26, 0.13), up * smoothstep(0.45, 0.7, big + mid * 0.3) * 0.55); // moss, lichen
			float foot = 1.0 - smoothstep(0.0, 1.2, w_pos.y - (v_base_y + 0.3));
			c = mix(c, vec3(0.16, 0.13, 0.09), foot * 0.5); // earth splashed up the foot
		}
	}
	float wet = weather_wetness * (leaf > 0.5 ? 0.35 : 0.8);
	c *= mix(1.0, 0.6, wet);
	float rough = mix(roughness, 0.4, wet);
	float up = w_normal.y;
	float snow = smoothstep(0.25, 0.7, up * weather_snow * 1.3 - (1.0 - weather_snow) * 0.2);
	c = mix(c, vec3(0.88, 0.9, 0.95), snow);
	ALBEDO = c;
	ROUGHNESS = mix(leaf > 0.5 ? 0.9 : rough, 0.75, snow);
	SPECULAR = leaf > 0.5 ? 0.15 : 0.3;
	if (leaf > 0.5) {
		BACKLIGHT = c * 0.9; // the sun through the crown
		AO = 0.9;
	}
}
