shader_type sky;
// Overcast night: horizon glow from the city, fine stars, a cold moon.

uniform vec3 moon_dir = vec3(-0.45, 0.55, -0.7);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(vec3(0.11, 0.13, 0.18), vec3(0.015, 0.02, 0.04), smoothstep(-0.05, 0.6, h));
	c += vec3(0.3, 0.2, 0.12) * pow(1.0 - abs(h), 10.0) * 0.6;
	if (!AT_CUBEMAP_PASS) {
		vec3 q = floor(d * 420.0);
		float s = hash(q);
		c += step(0.9982, s) * smoothstep(0.05, 0.5, h) * (0.15 + 0.45 * fract(s * 97.0));
	}
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	c += vec3(0.9, 0.95, 1.0) * smoothstep(0.9993, 0.9996, md) * 1.8;
	c += vec3(0.25, 0.3, 0.4) * pow(max(md, 0.0), 120.0) * 0.6;
	COLOR = c;
}
