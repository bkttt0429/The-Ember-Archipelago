#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform writeonly image2D foam_out;

layout(set = 0, binding = 1, std430) readonly buffer FoamParams {
	vec4 particles[256];
} foam_params;

layout(push_constant) uniform PushConstants {
	int width;
	int height;
	int count;
	int pad0;
	float sea_size_x;
	float sea_size_y;
	float manager_x;
	float manager_y;
} pc;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= pc.width || gid.y >= pc.height) {
		return;
	}

	vec2 uv = (vec2(gid) + vec2(0.5)) / vec2(float(pc.width), float(pc.height));
	vec2 world = (uv - vec2(0.5)) * vec2(pc.sea_size_x, pc.sea_size_y) + vec2(pc.manager_x, pc.manager_y);

	float foam = 0.0;
	for (int i = 0; i < pc.count; i++) {
		vec4 p0 = foam_params.particles[i * 2];
		vec4 p1 = foam_params.particles[i * 2 + 1];
		vec2 center = p0.xy;
		float scale = max(p0.w, 0.001);
		float life_t = clamp(p1.x, 0.0, 1.0);
		float speed = p1.y;
		float radius = mix(scale * 0.5, scale * 2.2, 1.0 - life_t) + speed * 0.03;
		vec2 off = world - center;
		float dist2 = dot(off, off);
		float sigma = max(radius, 0.001);
		float contribution = exp(-dist2 / (2.0 * sigma * sigma));
		contribution *= (1.0 - life_t);
		foam += contribution;
	}

	foam = clamp(foam, 0.0, 1.0);
	imageStore(foam_out, gid, vec4(foam, foam, foam, foam));
}
