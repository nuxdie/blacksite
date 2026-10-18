shader_type spatial;
// Uniform fabric: a two-tone blotch camouflage in object space, with a fine weave so surfaces
// catch light like cloth instead of flat plastic.

uniform vec3 base : source_color = vec3(0.42, 0.41, 0.32);
uniform vec3 blotch : source_color = vec3(0.28, 0.29, 0.22);
uniform float scale = 5.0;
uniform float amount : hint_range(0.0, 1.0) = 0.5;

varying vec3 obj;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
}

void fragment() {
	float n = noise(obj * scale) * 0.65 + noise(obj * scale * 2.3) * 0.35;
	float m = smoothstep(0.52, 0.56, n) * amount;
	vec3 c = mix(base, blotch, m);
	float weave = noise(obj * 160.0) * 0.12;
	ALBEDO = c * (0.94 + weave);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
