shader_type sky;
// Physically based sky for scripts/weather.gd.
//
// Single-scattering atmosphere (Rayleigh + Mie + ozone, short ray march with a
// planet-shadow test, so twilight keeps a blue zenith and sunsets go orange/red
// on their own), a sun disc with limb darkening, a phased moon, stars with a
// faint milky way, and two animated cloud layers (fbm cumulus on a curved
// shell at ~1.8 km and stretched cirrus at ~8 km) lit by the actual sunlight
// colour. Every input is a uniform driven by Weather each frame; the sky does
// not use TIME, so it stays in step with paused/frozen time.

// Light directions point TOWARD the sun / moon.
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 moon_dir = vec3(0.0, -0.7, -0.7);
uniform float sun_power = 22.0;
uniform float moon_power = 0.0;            // 0..1 visibility of moonlight
uniform vec3 sun_tint = vec3(1.0);          // sunlight colour at cloud height (transmittance)
uniform vec3 ambient_color = vec3(0.3, 0.45, 0.7); // light reaching the clouds from the sky dome
uniform float cloud_cover = 0.2;
uniform float cloud_dark = 0.0;             // overcast/storm greyness
uniform vec2 cloud_offset = vec2(0.0);
uniform vec2 cirrus_offset = vec2(0.0);
uniform float haze = 1.0;                   // Mie (aerosol) multiplier
uniform float night = 0.0;                  // 0 day .. 1 full night (stars)
uniform float star_rotation = 0.0;
uniform float moon_phase = 0.7;             // 0 new .. 0.5 half .. 1 full
uniform float flash = 0.0;                  // lightning
uniform float twinkle_time = 0.0;
uniform float sky_grey = 0.0;               // fog/precipitation greying of the dome

const float PR = 6360e3;
const float AR = 6420e3;
const float HR = 8000.0;
const float HM = 1200.0;
const vec3 BR = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const vec3 BO = vec3(0.65e-6, 1.881e-6, 0.085e-6);
const float BM = 3.996e-6;
const float EYE_H = 250.0;
const float CLOUD_H = 1800.0;
const float CIRRUS_H = 8000.0;

float exit_dist(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	return -b + sqrt(max(b * b - c, 0.0));
}

// Single scattering toward the eye along dir, lit from ldir. trans = transmittance along the view ray.
vec3 atmosphere(vec3 dir, vec3 ldir, float power, out vec3 trans, int steps) {
	vec3 o = vec3(0.0, PR + EYE_H, 0.0);
	float tmax = exit_dist(o, dir, AR);
	float mu = dot(dir, ldir);
	float pr = 0.0596831 * (1.0 + mu * mu);
	const float g = 0.76;
	float pm = 0.1193662 * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	vec3 sr = vec3(0.0);
	vec3 sm = vec3(0.0);
	float odr = 0.0;
	float odm = 0.0;
	float fs = float(steps);
	for (int i = 0; i < steps; i++) {
		float u0 = float(i) / fs;
		float u1 = float(i + 1) / fs;
		float t0 = tmax * u0 * u0;
		float t1 = tmax * u1 * u1;
		float ds = t1 - t0;
		vec3 p = o + dir * (0.5 * (t0 + t1));
		float h = length(p) - PR;
		float dr = exp(-h / HR) * ds;
		float dm = exp(-h / HM) * ds;
		odr += dr * 0.5;
		odm += dm * 0.5;
		float lb = dot(p, ldir);
		float lc = dot(p, p) - PR * PR;
		if (!(lb < 0.0 && lb * lb - lc > 0.0)) {
			float lt = exit_dist(p, ldir, AR);
			float lodr = 0.0;
			float lodm = 0.0;
			for (int j = 0; j < 4; j++) {
				float v0 = float(j) * 0.25;
				float v1 = float(j + 1) * 0.25;
				float s0 = lt * v0 * v0;
				float s1 = lt * v1 * v1;
				float hq = length(p + ldir * (0.5 * (s0 + s1))) - PR;
				lodr += exp(-hq / HR) * (s1 - s0);
				lodm += exp(-hq / HM) * (s1 - s0);
			}
			vec3 tau = (BR + BO) * (odr + lodr) + BM * 1.11 * haze * (odm + lodm);
			vec3 att = exp(-tau);
			sr += att * dr;
			sm += att * dm;
		}
		odr += dr * 0.5;
		odm += dm * 0.5;
	}
	trans = exp(-((BR + BO) * odr + BM * 1.11 * haze * odm));
	return power * (sr * BR * pr + sm * BM * haze * pm);
}

// Cheap view transmittance for when the full march is skipped (deep night).
vec3 trans_approx(float y) {
	float m = 1.0 / (max(y, 0.0) + 0.025);
	return exp(-((BR + BO) * HR + BM * 1.11 * haze * HM) * min(m, 38.0));
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float s = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		s += a * vnoise(p);
		norm += a;
		p = rot * p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s / norm;
}

vec2 cloud_density(vec2 uv, int octaves) {
	// x = opacity, y = optical thickness (how deep inside the cloud this is).
	vec2 warp = vec2(vnoise(uv * 0.35 + 3.1), vnoise(uv * 0.35 + 7.7)) - 0.5;
	float n = fbm(uv + warp * 0.9, octaves);
	float base = mix(0.6, 0.27, cloud_cover);
	float d = smoothstep(base, base + 0.1, n);
	float thick = clamp((n - base) * 3.0, 0.0, 1.0);
	float sheet = smoothstep(0.72, 1.0, cloud_cover);
	float sheet_d = sheet * (0.82 + 0.18 * smoothstep(0.25, 0.7, n));
	return vec2(max(d, sheet_d), max(thick, sheet * (0.5 + 0.5 * n)));
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 adir = normalize(vec3(dir.x, max(dir.y, 0.0), dir.z));
	bool cube = AT_CUBEMAP_PASS;

	// --- Atmosphere ---
	vec3 col = vec3(0.0);
	vec3 trans;
	if (sun_dir.y > -0.3) {
		col = atmosphere(adir, sun_dir, sun_power, trans, cube ? 8 : 12);
	} else {
		trans = trans_approx(adir.y);
	}
	// Moonlit sky and airglow: a dim blue dome, brightest low down and around the moon.
	float mmu = max(dot(adir, moon_dir), 0.0);
	vec3 night_dome = vec3(0.010, 0.017, 0.040) * (1.25 - 0.55 * adir.y)
		+ vec3(0.03, 0.035, 0.045) * pow(mmu, 24.0);
	col += night_dome * moon_power * night * smoothstep(-0.15, 0.1, moon_dir.y);
	col += vec3(0.0012, 0.0018, 0.0035) * night;

	// Grey the dome under heavy cloud / fog so the horizon matches the cloud deck.
	float grey = clamp(smoothstep(0.55, 1.0, cloud_cover) * 0.85 + sky_grey, 0.0, 1.0);
	vec3 deck = mix(ambient_color, vec3(luma(ambient_color)), 0.5) * 0.62 * (1.0 - 0.6 * cloud_dark);
	col = mix(col, mix(vec3(luma(col)) * vec3(0.92, 0.96, 1.0), deck, smoothstep(0.6, 1.0, cloud_cover)), grey);

	// --- Stars and milky way ---
	if (!cube && night > 0.01) {
		float cr = cos(star_rotation);
		float sr = sin(star_rotation);
		vec3 sd = vec3(dir.x, dir.y * cr - dir.z * sr, dir.y * sr + dir.z * cr);
		vec3 g = sd * 230.0;
		vec3 cell = floor(g);
		float h = hash3(cell);
		vec3 jitter = vec3(hash3(cell + 11.3), hash3(cell + 27.1), hash3(cell + 41.9)) - 0.5;
		float star = 0.0;
		if (h > 0.985) {
			float dd = length(fract(g) - 0.5 - jitter * 0.6);
			float bright = pow((h - 0.985) / 0.015, 3.0) * 3.0 + 0.15;
			float tw = 0.75 + 0.25 * sin(twinkle_time * (3.0 + h * 9.0) + h * 300.0);
			star = bright * tw * pow(max(1.0 - dd * 3.2, 0.0), 3.0);
		}
		vec3 star_col = mix(vec3(1.0, 0.82, 0.65), vec3(0.75, 0.85, 1.0), hash3(cell + 5.0));
		float band = dot(sd, normalize(vec3(0.3, 0.2, 0.93)));
		float mw = exp(-band * band * 18.0) * fbm(sd.xy * 9.0 + sd.z * 3.0, 4);
		vec3 stars = star_col * star * 1.4 + vec3(0.016, 0.017, 0.022) * mw * mw * 2.5;
		col += stars * night * (1.0 - grey) * (1.0 - smoothstep(0.5, 0.9, cloud_cover)) * trans * smoothstep(-0.02, 0.15, dir.y);
	}

	// --- Moon disc ---
	float mcos = dot(dir, moon_dir);
	const float MOON_R = 0.022;
	if (night > 0.001 && mcos > cos(MOON_R * 1.2)) {
		vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		vec3 up = cross(right, moon_dir);
		vec3 rel = dir - moon_dir;
		vec2 q = vec2(dot(rel, right), dot(rel, up)) / MOON_R;
		float rr = dot(q, q);
		float disc = smoothstep(1.0, 0.94, rr);
		vec3 n = vec3(q, sqrt(max(1.0 - rr, 0.0)));
		float ang = (1.0 - moon_phase) * PI;
		vec3 l = vec3(sin(ang), 0.15, cos(ang));
		float lit = smoothstep(-0.06, 0.12, dot(n, normalize(l)));
		float maria = 0.72 + 0.28 * smoothstep(0.35, 0.65, fbm(q * 2.3 + 4.0, 4));
		vec3 mcol = vec3(1.0, 0.97, 0.9) * maria * (lit * 1.5 + 0.015);
		col = mix(col, mcol * trans * mix(1.0, 0.3, smoothstep(0.1, -0.05, moon_dir.y)), disc * night);
	}
	col += vec3(0.6, 0.7, 0.9) * pow(max(mcos, 0.0), 900.0) * 0.12 * night * (1.0 - grey);

	// --- Sun disc ---
	float mu = dot(dir, sun_dir);
	const float SUN_R = 0.0085;
	if (!cube && mu > cos(SUN_R * 1.5)) {
		float r = acos(clamp(mu, -1.0, 1.0)) / SUN_R;
		float disc = smoothstep(1.0, 0.9, r);
		float limb = 0.55 + 0.45 * sqrt(max(1.0 - r * r, 0.0));
		col += sun_power * 70.0 * trans * disc * limb * (1.0 - grey * 0.9);
	}

	// --- Clouds ---
	float cloud_a = 0.0;
	if (dir.y > 0.0) {
		vec3 o = vec3(0.0, PR + EYE_H, 0.0);
		float tc = exit_dist(o, dir, PR + CLOUD_H);
		vec2 cuv = (o + dir * tc).xz * 0.0006 + cloud_offset;
		int oct = cube ? 4 : 6;
		vec2 dt = cloud_density(cuv, oct);
		float d = dt.x;
		float dist_fade = exp(-tc * 1.2e-5);
		vec3 light_dir = sun_dir.y > -0.05 ? sun_dir : moon_dir;
		vec2 to_l = normalize(light_dir.xz + vec2(1e-4)) * 0.1;
		float t2l = cloud_density(cuv + to_l, cube ? 3 : 4).y;
		// Sun-facing flanks bright, the deep middle and the bases grey.
		float shade = exp(-max(t2l - dt.y * 0.4, 0.0) * 3.0);
		float body = mix(1.0, 0.35, dt.y);
		float lmu = dot(dir, light_dir);
		float silver = pow(max(lmu, 0.0), 12.0) * (1.0 - dt.y) * 5.0 + pow(max(lmu, 0.0), 3.0) * 0.5;
		vec3 sunlight = sun_tint * sun_power * 0.06 * smoothstep(-0.1, 0.05, sun_dir.y);
		vec3 moonlight = vec3(0.45, 0.55, 0.8) * 0.015 * moon_power * night;
		vec3 direct = (sunlight + moonlight) * (shade * body + silver);
		vec3 amb = ambient_color * mix(0.95, 0.5, dt.y);
		vec3 ccol = (direct * (1.0 - cloud_dark * 0.85) + amb) * mix(1.0, 0.4, cloud_dark);
		ccol = mix(col, ccol, dist_fade);
		cloud_a = d * smoothstep(0.0, 0.05, dir.y) * mix(dist_fade, 1.0, smoothstep(0.6, 1.0, cloud_cover));

		// Cirrus: thin, high, streaky; fades out under a thick deck.
		float t2 = exit_dist(o, dir, PR + CIRRUS_H);
		vec2 uv2 = (o + dir * t2).xz * 0.00009 + cirrus_offset;
		float cn = fbm(vec2(uv2.x * 0.6, uv2.y * 2.4), cube ? 3 : 5);
		float ca = smoothstep(0.55, 0.85, cn) * 0.3 * (1.0 - smoothstep(0.4, 0.9, cloud_cover)) * smoothstep(0.0, 0.12, dir.y);
		vec3 cirrus_col = (sunlight * (0.7 + silver * 0.5) + ambient_color * 1.1);
		col = mix(col, cirrus_col, ca);

		col = mix(col, ccol, cloud_a);
	}

	// --- Below the horizon: dim ground-ish bounce (mostly hidden by terrain) ---
	if (dir.y < 0.0) {
		vec3 ground = col * vec3(0.32, 0.34, 0.28);
		col = mix(col, ground, smoothstep(0.0, 0.2, -dir.y));
	}

	// --- Lightning lights up the cloud deck ---
	col += flash * vec3(0.75, 0.8, 1.0) * (0.25 + 2.5 * cloud_a);

	COLOR = max(col, vec3(0.0));
}
