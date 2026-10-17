shader_type canvas_item;
// Security camera look: monochrome with a cold tint, sensor noise, scanlines and a soft vignette.

uniform float signal : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = texture(TEXTURE, uv).rgb;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	g = clamp(pow(g * 1.4, 0.5) * 1.5, 0.0, 1.0);
	float n = hash(uv * vec2(640.0, 360.0) + fract(TIME) * 91.7) - 0.5;
	g += n * 0.08;
	g *= 0.92 + 0.08 * sin(uv.y * 720.0);
	vec2 c = uv - 0.5;
	g *= 1.0 - dot(c, c) * 1.2;
	vec3 tint = vec3(0.78, 0.92, 0.95) * g;
	float snow = hash(uv * vec2(320.0, 180.0) + fract(TIME * 13.0));
	COLOR = vec4(mix(vec3(snow * 0.5), tint, signal), 1.0);
}
