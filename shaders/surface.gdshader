shader_type spatial;
// Procedural world-space surfaces: no textures, no UVs. Each material picks a pattern.
// 0 plain  1 blocks  2 corrugated  3 planks  4 grating  5 asphalt  6 slabs

uniform vec3 albedo : source_color = vec3(0.5);
uniform int pattern = 0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform float bump = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.07; a *= 0.5; }
	return s;
}

// height field in metres-space uv; x = height 0..1, y = albedo multiplier
vec2 pattern_at(vec2 uv) {
	if (pattern == 1) {
		float row = floor(uv.y / 0.2);
		float x = uv.x / 0.4 + 0.5 * mod(row, 2.0);
		float fx = fract(x), fy = fract(uv.y / 0.2);
		float mortar = step(fx, 0.025) + step(0.975, fx) + step(fy, 0.05) + step(0.95, fy);
		float tint = 0.9 + 0.2 * hash12(vec2(floor(x), row));
		return mortar > 0.0 ? vec2(0.0, 0.62) : vec2(0.8 + 0.2 * vnoise(uv * 30.0), tint);
	}
	if (pattern == 2) {
		float r = 0.5 + 0.5 * sin(uv.x * 6.2832 / 0.15);
		return vec2(r, 0.82 + 0.18 * r);
	}
	if (pattern == 3) {
		float fy = fract(uv.y / 0.2);
		float seam = step(fy, 0.04);
		float grain = vnoise(vec2(uv.x * 2.0, uv.y * 60.0));
		float tint = 0.85 + 0.25 * hash12(vec2(floor(uv.y / 0.2), 3.0));
		return seam > 0.0 ? vec2(0.0, 0.5) : vec2(0.7 + 0.3 * grain, tint * (0.85 + 0.2 * grain));
	}
	if (pattern == 4) {
		vec2 f = fract(uv / 0.05);
		float bar = max(step(f.x, 0.22), step(f.y, 0.22));
		return bar > 0.0 ? vec2(1.0, 1.0) : vec2(0.0, 0.18);
	}
	if (pattern == 5) {
		float n = vnoise(uv * 45.0);
		float crack = smoothstep(0.012, 0.0, abs(fbm(uv * 0.7) - 0.5));
		return vec2(n * 0.4 - crack, (0.82 + 0.35 * (n - 0.5)) * (1.0 - crack * 0.6));
	}
	if (pattern == 6) {
		vec2 f = fract(uv / 2.0);
		float joint = step(f.x, 0.006) + step(f.y, 0.006);
		return joint > 0.0 ? vec2(0.0, 0.6) : vec2(0.5 + 0.2 * vnoise(uv * 12.0), 0.95 + 0.1 * hash12(floor(uv / 2.0)));
	}
	return vec2(0.5 + 0.3 * vnoise(uv * 14.0), 0.95 + 0.1 * vnoise(uv * 3.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 uv;
	vec3 T;
	vec3 B;
	if (an.y > 0.6) { uv = wpos.xz; T = vec3(1.0, 0.0, 0.0); B = vec3(0.0, 0.0, 1.0); }
	else if (an.x > an.z) { uv = wpos.zy; T = vec3(0.0, 0.0, 1.0); B = vec3(0.0, 1.0, 0.0); }
	else { uv = wpos.xy; T = vec3(1.0, 0.0, 0.0); B = vec3(0.0, 1.0, 0.0); }

	vec2 p = pattern_at(uv);
	float e = 0.004;
	float hx = pattern_at(uv + vec2(e, 0.0)).x;
	float hy = pattern_at(uv + vec2(0.0, e)).x;
	vec3 n = normalize(wnrm - bump * 0.015 * ((hx - p.x) / e * T + (hy - p.x) / e * B));

	float g = fbm(uv * 0.35 + wnrm.xz * 3.0);
	float dirt = grime * smoothstep(0.35, 0.85, g);
	if (an.y < 0.5) {
		dirt += grime * 0.6 * smoothstep(0.55, 1.0, fbm(vec2(uv.x * 2.5, uv.y * 0.15)));
		dirt += grime * 0.4 * smoothstep(1.2, 0.0, uv.y - floor(uv.y / 40.0) * 40.0) * step(0.0, uv.y);
	}
	vec3 col = albedo * p.y * (1.0 - clamp(dirt, 0.0, 0.8));
	col *= 0.92 + 0.16 * vnoise(uv * 90.0);

	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base + dirt * 0.1 - p.x * 0.05, 0.0, 1.0);
	METALLIC = metallic_base * (1.0 - dirt);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
