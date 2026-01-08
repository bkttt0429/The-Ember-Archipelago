shader_type spatial;
render_mode cull_disabled;

uniform sampler2D swe_simulation_map;
uniform vec4 water_color : source_color = vec4(0.0, 0.4, 0.8, 1.0);
uniform float height_scale = 1.0;

varying float v_height;

vec3 try_normal_from_derivative(vec3 pos) {
	vec3 dx = dFdx(pos);
	vec3 dy = dFdy(pos);
	return normalize(cross(dx, dy));
}

void vertex() {
	// Sample height from the texture
	// UV is 0..1 across the mesh plane
	float h = texture(swe_simulation_map, UV).r;
	v_height = h;
	
	VERTEX.y += h * height_scale;
}

void fragment() {
	ALBEDO = water_color.rgb;
	
	// Visualize height as color brightness
	ALBEDO += vec3(v_height * 0.1);
	
	// Grid Visualization
	float grid_density = 64.0;
	vec2 grid = abs(fract(UV * grid_density - 0.5) - 0.5) / fwidth(UV * grid_density);
	float line = min(grid.x, grid.y);
	float grid_val = 1.0 - min(line, 1.0);
	
	ALBEDO = mix(ALBEDO, vec3(1.0), grid_val * 0.5); // Add white grid lines
	
	// Dynamic Normal (Low Poly Style)
	vec3 normal = try_normal_from_derivative(VERTEX);
	NORMAL = normal;
	
	ROUGHNESS = 0.2;
}
