shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture;
uniform float damping = 0.99;
uniform float delta_time = 0.016;

void fragment() {
	float x_step = 1.0 / float(textureSize(screen_texture, 0).x);
	float y_step = 1.0 / float(textureSize(screen_texture, 0).y);
	
	// Sample neighbors
	float left = texture(screen_texture, SCREEN_UV + vec2(-x_step, 0.0)).r;
	float right = texture(screen_texture, SCREEN_UV + vec2(x_step, 0.0)).r;
	float up = texture(screen_texture, SCREEN_UV + vec2(0.0, -y_step)).r;
	float down = texture(screen_texture, SCREEN_UV + vec2(0.0, y_step)).r;
	
	vec2 state = texture(screen_texture, SCREEN_UV).rg;
	
	// Wave equation:
	// accel = laplacian * c^2
	// vel += accel * dt
	// height += vel * dt
	
	// Simplified Verlet integration for ripples:
	// val = (sum_neighbors / 2 - prev_val) * damping
	
	float h = (left + right + up + down) * 0.5 - state.g;
	h *= damping;
	
	// Output: R = New Height, G = Current Height (becomes prev next frame)
	COLOR = vec4(h, state.r, 0.0, 1.0);
}
