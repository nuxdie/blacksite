shader_type canvas_item;
// Full-screen stress effects: suppression blurs and drains the edges, damage tints them red.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float suppression : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float edge = smoothstep(0.25, 0.75, length(c));
	float blur = suppression * edge * 3.5;
	vec3 col = textureLod(screen_tex, uv, blur).rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), suppression * edge * 0.8);
	col *= 1.0 - suppression * edge * 0.45;
	float red = clamp(damage + low_health * (0.6 + 0.4 * sin(TIME * 5.0)), 0.0, 1.0) * edge;
	col = mix(col, vec3(0.45, 0.0, 0.0), red * 0.75);
	COLOR = vec4(col, 1.0);
}
