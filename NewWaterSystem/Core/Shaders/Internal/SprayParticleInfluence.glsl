#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform writeonly image2D spray_out;

layout(set = 0, binding = 1, std430) readonly buffer ParticleBuffer {
	vec4 particle_data[];
} particles;

layout(push_constant) uniform PushConstants {
	int width;
	int height;
	int particle_count;
	int pad0;
	float sea_size_x;
	float sea_size_y;
	float manager_x;
	float manager_z;
	float base_y;
	float mist_strength;
	float core_strength;
	float pad1;
} pc;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= pc.width || gid.y >= pc.height) {
		return;
	}

	vec2 uv = (vec2(gid) + vec2(0.5)) / vec2(float(pc.width), float(pc.height));
	vec2 world = (uv - vec2(0.5)) * vec2(pc.sea_size_x, pc.sea_size_y) + vec2(pc.manager_x, pc.manager_z);

	float core = 0.0;
	float mist = 0.0;
	for (int i = 0; i < pc.particle_count; i++) {
		vec4 p0 = particles.particle_data[i * 2];
		vec4 p1 = particles.particle_data[i * 2 + 1];
		float age = p0.w;
		float lifetime = max(p1.w, 0.001);
		if (age <= 0.0 || age >= lifetime) {
			continue;
		}
		vec2 center = vec2(p0.x, p0.z);
		vec2 off = world - center;
		float speed = length(p1.xyz);
		float life_t = clamp(age / lifetime, 0.0, 1.0);
		float radius = mix(0.4, 1.6, 1.0 - life_t) + speed * 0.06;
		float dist2 = dot(off, off);
		float sigma = max(radius, 0.001);
		float g = exp(-dist2 / (2.0 * sigma * sigma));
		float height_mask = clamp((p0.y - pc.base_y) * 0.35, 0.0, 1.0);
		core = max(core, g * (1.0 - life_t) * height_mask * pc.core_strength);
		mist += g * (1.0 - life_t * 0.8) * height_mask * pc.mist_strength;
	}
	core = clamp(core, 0.0, 1.0);
	mist = clamp(mist, 0.0, 1.0);
	imageStore(spray_out, gid, vec4(core, mist, 0.0, max(core, mist)));
}
