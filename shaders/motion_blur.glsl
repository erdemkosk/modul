#[compute]
#version 450
// ScreenFx's pass over the frame (MotionBlurEffect), before tone mapping. Run twice: first it
// copies the frame aside (p.sz.w < 0: the colour buffer can't be copied from), then it blurs from
// the copy back into the frame.
//   motion blur  each pixel smeared along the way it moved on the screen since the last frame as
//                the view moved: worked out from its depth and the two frames' cameras (the
//                engine's own motion vectors are wrong on the terrain's and grass's own vertex
//                shaders, so the world isn't trusted to them). What's within arm's reach (your
//                gun, your hands) moves with the view: it takes the engine's vectors instead (its
//                own sway and kick, nothing of the turn) and stays sharp. A share of a frame's
//                motion (the shutter), never past a cap; near and far never smear into each other.
//   radial blur  outward from the middle (sprinting flat out, a blast, a hard landing), never on
//                what's within reach.
//   vignette     the edges darkened (sprinting, if wanted).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;
layout(set = 0, binding = 2) uniform sampler2D velocity_tex;
layout(set = 0, binding = 3) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
	vec4 rot0; // xyz: rows of (last frame's view)^T * (this frame's view); w: where this frame's eye
	vec4 rot1; //   is in the last frame's view (a point now -> then: rot * p + w)
	vec4 rot2;
	vec4 proj; // this frame's P[0][0], P[1][1], the last frame's
	vec4 fx; // shutter (of a frame's motion), cap (uv), radial strength, vignette
	vec4 sz; // width, height, depth nearer than this is within reach (reverse z), samples (< 0: copy)
	vec4 cam; // near, far
} p;

float ign(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// How far this pixel moved on the screen (uv) since the last frame, the world standing still and
// the view moving: from its depth (0: the sky, as far as can be: the turn alone).
vec2 view_velocity(vec2 uv, float depth) {
	vec2 ndc = uv * 2.0 - 1.0;
	vec3 d = vec3(ndc.x / p.proj.x, -ndc.y / p.proj.y, -1.0);
	vec3 q;
	if (depth <= 1e-7) {
		q = vec3(dot(p.rot0.xyz, d), dot(p.rot1.xyz, d), dot(p.rot2.xyz, d));
	} else {
		float z = p.cam.x * p.cam.y / (depth * (p.cam.y - p.cam.x) + p.cam.x);
		vec3 v = d * z;
		q = vec3(dot(p.rot0.xyz, v), dot(p.rot1.xyz, v), dot(p.rot2.xyz, v)) + vec3(p.rot0.w, p.rot1.w, p.rot2.w);
	}
	if (q.z > -1e-3) {
		return vec2(0.0);
	}
	vec2 prev_ndc = vec2(p.proj.z * q.x / -q.z, -(p.proj.w * q.y / -q.z));
	return (ndc - prev_ndc) * 0.5;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(p.sz.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}
	if (p.sz.w < 0.0) {
		imageStore(dst_image, px, imageLoad(src_image, px)); // (the first pass: the frame copied aside)
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / vec2(size);
	float depth = textureLod(depth_tex, uv, 0.0).r;
	bool near = depth > p.sz.z;
	vec2 vel = near ? textureLod(velocity_tex, uv, 0.0).xy : view_velocity(uv, depth);
	if (any(isnan(vel)) || any(isinf(vel))) {
		vel = vec2(0.0);
	}
	vec2 blur = vel * p.fx.x;
	float len = length(blur);
	if (len > p.fx.y) {
		blur *= p.fx.y / len;
	}
	vec2 from_mid = uv - 0.5;
	if (!near) {
		blur += from_mid * p.fx.z * smoothstep(0.1, 0.6, length(from_mid));
	}
	float vig = p.fx.w * smoothstep(0.35, 0.95, length(from_mid * vec2(size.x / float(size.y), 1.0)) * 1.05);
	vec2 blur_px = blur * vec2(size);
	if (dot(blur_px, blur_px) < 0.36 && vig < 0.002) {
		return; // (still: left as it was)
	}
	vec4 centre = imageLoad(src_image, px);
	vec4 acc = centre;
	float wsum = 1.0;
	if (dot(blur_px, blur_px) >= 0.36) {
		int n = int(p.sz.w);
		float jit = ign(vec2(px)) - 0.5;
		for (int i = 0; i < n; i++) {
			float t = (float(i) + 0.5 + jit) / float(n) - 0.5;
			vec2 suv = clamp(uv + blur * t, vec2(0.0), vec2(1.0));
			ivec2 sp = clamp(ivec2(suv * vec2(size)), ivec2(0), size - 1);
			float sd = textureLod(depth_tex, suv, 0.0).r;
			if ((sd > p.sz.z) != near) {
				continue; // (the gun doesn't smear over the world, nor the world over the gun)
			}
			vec4 s = imageLoad(src_image, sp);
			if (any(isnan(s)) || any(isinf(s))) {
				continue;
			}
			acc += s;
			wsum += 1.0;
		}
	}
	vec4 col = acc / wsum;
	col.rgb *= 1.0 - vig;
	imageStore(dst_image, px, vec4(max(col.rgb, vec3(0.0)), centre.a));
}
