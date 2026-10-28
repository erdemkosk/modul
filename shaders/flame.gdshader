shader_type spatial;
// Fire (Campfire, GrassFire, Burning, the molotov, the lighter): tongues of flame on quads that
// turn about their upright axis to face the camera, all in one mesh (one draw call). Each quad's
// COLOR carries its own seed (r) and how tall it is next to the others (g).
//
// The flame is a field of fuel burning off as it rises: a round, solid foot that narrows upward,
// eaten by turbulent noise flowing up through it (faster the higher it goes, the flow itself
// warped so the tongues curl and lick), so it tears into tongues and loose wisps at the top.
// Coloured by temperature like a real flame: a hot white-yellow heart low in the middle, an
// orange body, a deep red at the ragged edges, sooty and a little dark at the tips. Soft against
// whatever it stands in (the depth buffer: no hard line where the quad meets the ground or the
// wood), leaning and torn by the wind (weather_wind). Far off it gathers into a soft glowing
// shape that holds up at a few pixels instead of shimmering apart.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

global uniform vec3 weather_wind;

instance uniform float heat : hint_range(0.0, 1.0) = 1.0; // how big and hot it burns now
instance uniform float seed = 0.0;
uniform float brightness = 2.2; // the whole of it (2.2: a wood fire's)
uniform float lean = 0.35; // how far the tips go with a full wind (fraction of the height)
uniform float speed = 1.0;
// A MultiMesh of flames (GrassFire: a tongue of fire per burning patch of ground, all in one draw
// call): each one's heat and seed come from its INSTANCE_CUSTOM (r, g) instead.
uniform bool from_custom = false;
// A wick's flame (the lighter): one smooth teardrop, not torn into tongues, blue at its root.
uniform float wick = 0.0;
uniform vec2 push = vec2(0.0); // world xz the tip is pushed by (the hand moving: Lighter)
uniform vec3 tint : source_color = vec3(1.0); // the cooler parts of it coloured (a road flare: red), the white core kept
// Drawn this far toward the camera from where it stands (a body on fire: in front of the body's
// own surface, not hidden inside it).
uniform float nudge = 0.0;
uniform float soft_depth = 0.2; // m: it fades out this close to what's behind it
uniform float base_fade = 0.1; // fraction of its height it fades in over from its foot (on a body: no flat bottom)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < octaves; i++) {
		s += vnoise(p) * a;
		n += a;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s / n;
}

// Temperature to colour (linear HDR), a flame's: dull red, orange, yellow, white.
vec3 fire_ramp(float k) {
	vec3 c = mix(vec3(0.25, 0.025, 0.004), vec3(0.85, 0.16, 0.015), smoothstep(0.0, 0.22, k));
	c = mix(c, vec3(1.0, 0.36, 0.035), smoothstep(0.18, 0.42, k));
	c = mix(c, vec3(1.0, 0.62, 0.16), smoothstep(0.4, 0.66, k));
	c = mix(c, vec3(1.0, 0.82, 0.48), smoothstep(0.64, 0.92, k));
	return c;
}

varying float v_seed;
varying float v_tall;
varying float v_heat;
varying float v_far;

void vertex() {
	v_heat = from_custom ? INSTANCE_CUSTOM.r : heat;
	v_seed = COLOR.r * 17.0 + (from_custom ? INSTANCE_CUSTOM.g * 40.0 : seed);
	v_tall = COLOR.g;
	// Upright, turned about Y to face the camera (as StandardMaterial3D's Y-billboard).
	vec3 cam_z = INV_VIEW_MATRIX[2].xyz;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), cam_z));
	vec3 fwd = normalize(cross(right, vec3(0.0, 1.0, 0.0)));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = length(CAMERA_POSITION_WORLD - origin);
	// Far off (past ~45 m) a little bigger and simpler, so it still reads at a few pixels.
	v_far = smoothstep(45.0, 160.0, dist);
	float grow = 1.0 + v_far * 0.7;
	// The wind pushes the upper part over (the part of it across the view), and gusts shake it.
	float h = clamp(VERTEX.y, 0.0, 2.5);
	float gust = 0.75 + 0.25 * sin(TIME * 1.9 + v_seed) * sin(TIME * 0.7 + v_seed * 0.3);
	float wind_push = dot(weather_wind.xz, right.xz) * lean * (0.4 + 0.6 * v_heat) * gust + dot(push, right.xz);
	VERTEX.x += wind_push * h * h;
	VERTEX.y *= mix(0.22, 1.0, v_heat);
	VERTEX.xy *= grow;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// (z: the quads' spread in depth, kept along the camera's line so the tongues overlap)
	vec3 world = origin + right * (VERTEX.x * sc.x) + vec3(0.0, VERTEX.y * sc.y, 0.0) + fwd * (VERTEX.z * sc.z);
	world += normalize(CAMERA_POSITION_WORLD - world) * nudge;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float y = 1.0 - UV.y; // 0 at the base, 1 at the top
	float x = UV.x * 2.0 - 1.0;
	float t = mod(TIME, 400.0) * speed; // (kept small: the noise hash loses precision on big inputs)
	float heat_k = clamp(v_heat, 0.0, 1.0);
	float detail = 1.0 - v_far * 0.8; // (far off: no fine noise to shimmer)
	float k; // temperature 0..1
	float a; // coverage 0..1
	if (wick > 0.5) {
		// A wick's flame: one teardrop, its tip trembling, blue at the root.
		float tremble = (vnoise(vec2(v_seed, t * 6.0)) - 0.5) * 0.18 * y * y;
		float px = x + tremble;
		float w = 0.62 * pow(clamp(y / 0.28, 0.0, 1.0), 0.5) * pow(1.0 - y, 1.1) + 0.015;
		float edge = 1.0 - smoothstep(w * 0.35, w, abs(px));
		edge *= smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.86, 1.0, y));
		k = edge * (1.0 - y * 0.55) * (0.85 + 0.15 * vnoise(vec2(px * 4.0, y * 3.0 - t * 5.0)));
		a = edge;
		vec3 col = fire_ramp(k * 0.75 + 0.2);
		col = mix(col, vec3(0.18, 0.35, 1.0) * 0.8, 1.0 - smoothstep(0.05, 0.22, y));
		float flick = 0.9 + 0.1 * sin(t * 23.0 + v_seed);
		ALBEDO = col * a * (0.8 + 1.6 * k) * brightness * flick;
		ALPHA = a * 0.35;
	} else {
		float rise = t * (1.25 + 0.35 * v_tall);
		// The flow, warped: big slow swirls that bend the tongues sideways and make them curl.
		vec2 q = vec2(x * 1.1 + v_seed, y * 1.3 - rise * 0.8);
		float wx = fbm(q, 2) - 0.5;
		float wy = fbm(q * 1.3 + vec2(4.1, 7.3), 2) - 0.5;
		float swing = sin(t * 1.7 + v_seed * 2.1 + y * 2.5) * 0.07;
		vec2 p = vec2(x + (wx * 0.75 + swing) * y * (0.4 + 0.6 * y), y + wy * 0.18 * y);
		// Fine turbulence streaming up (stretched upward: flames streak), faster near the top.
		float climb = rise * 1.6;
		float n = fbm(vec2(p.x * 1.7 + v_seed * 1.7, p.y * 1.25 - climb), 3);
		float n2 = vnoise(vec2(p.x * 4.0 - v_seed, p.y * 2.6 - climb * 1.6));
		n = mix(0.5, n, detail);
		n2 = mix(0.5, n2, detail);
		// The envelope: a broad round foot, drawn up and in.
		float halfw = mix(0.78, 0.2, pow(clamp(p.y, 0.0, 1.0), 0.85));
		float across = clamp(1.0 - abs(p.x) / halfw, 0.0, 1.0);
		float fuel = pow(across, 0.5) * (1.15 - p.y * 0.92) * mix(0.7, 1.0, heat_k);
		// Two or three tongues: the top splits between them, the splits wandering with the flow.
		float split = 0.5 - 0.5 * cos(p.x * 8.0 + (n - 0.5) * 5.0 + v_seed * 3.0 + sin(rise * 0.7 + v_seed) * 1.5);
		// Eaten by the noise, more the higher it is: solid low, tongues and wisps up top.
		float eat = (n * 0.85 + n2 * 0.2) * (0.08 + p.y * (1.0 + 0.2 * v_tall)) + split * p.y * p.y * 0.3 * detail;
		float f = fuel - eat + 0.1;
		// Rooted: no flat cut at the bottom edge of the quad.
		float root = smoothstep(0.0, base_fade, y);
		f *= root;
		// Far off: a soft glowing shape (a fire seen from a distance), not torn noise.
		float blob = (1.0 - length(vec2(x / 0.62, (y - 0.32) / 0.5))) * 0.85;
		f = mix(f, blob, v_far * 0.75);
		a = smoothstep(0.0, 0.24, f) * (1.0 - smoothstep(0.82, 1.0, abs(x))) * (1.0 - smoothstep(0.88, 1.0, y)) * root; // (never a quad edge)
		k = clamp(f / 0.8, 0.0, 1.0);
		k *= mix(0.55, 1.0, heat_k);
		// The core: hottest low and in the middle.
		k = clamp(k + (1.0 - p.y) * across * 0.12 - 0.04, 0.0, 1.0);
		vec3 col = fire_ramp(k);
		col = mix(col * tint, col, smoothstep(0.55, 0.95, k));
		float flick = 0.86 + 0.14 * vnoise(vec2(t * 7.0, v_seed));
		float glow = (0.55 + 1.7 * k * k) * flick * (brightness / 2.2);
		// Premultiplied: the hot heart adds light (barely covers what's behind it), the cool edges
		// and tips are sooty, a little dark, as a real flame's are against the sky.
		float cover = mix(0.42, 0.26, smoothstep(0.1, 0.8, k)) + 0.3 * smoothstep(0.45, 0.95, y) * (1.0 - smoothstep(0.0, 0.4, k));
		a *= clamp(heat_k * 1.6, 0.0, 1.0);
		ALBEDO = col * glow * a;
		ALPHA = a * cover;
	}
	// Soft where it meets the ground and the wood (soft particles).
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -sv.z / sv.w;
	float soft = clamp((scene_z + VERTEX.z) / max(soft_depth, 0.001), 0.0, 1.0);
	ALBEDO *= soft;
	ALPHA *= soft;
}
