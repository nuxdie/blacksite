shader_type canvas_item;
// Full-screen stress effects: suppression blurs and drains the edges, damage tints them red, and
// the frame itself warms when someone is interested in you (amber) or sure of you (red).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float suppression : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform float alert : hint_range(0.0, 1.0) = 0.0;
uniform float alert_red : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float edge = smoothstep(0.25, 0.75, length(c));
	float rim = smoothstep(0.45, 0.95, length(c));
	float blur = suppression * edge * 3.5;
	vec3 col = textureLod(screen_tex, uv, blur).rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), suppression * edge * 0.8);
	col *= 1.0 - suppression * edge * 0.45;
	vec3 warm = mix(vec3(0.62, 0.40, 0.10), vec3(0.65, 0.10, 0.06), alert_red);
	float breathe = 0.85 + 0.15 * sin(TIME * (2.0 + 3.0 * alert_red));
	col = mix(col, warm, alert * rim * 0.32 * breathe);
	float red = clamp(damage + low_health * (0.6 + 0.4 * sin(TIME * 5.0)), 0.0, 1.0) * edge;
	col = mix(col, vec3(0.45, 0.0, 0.0), red * 0.75);
	COLOR = vec4(col, 1.0);
}
