#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer ParticleBuffer {
	vec4 particle_data[];
} particles;

layout(set = 0, binding = 1, std430) readonly buffer EmitterBuffer {
	vec4 emitter_data[];
} emitters;

layout(push_constant) uniform PushConstants {
	float dt;
	float time;
	float base_y;
	int emitter_count;
	float sea_size_x;
	float sea_size_y;
	float manager_x;
	float manager_z;
	int particle_count;
	float gravity;
	float drag;
	float pad0;
} pc;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 hash21(float p) {
	return vec2(hash11(p), hash11(p + 17.0));
}

void main() {
	uint id = gl_GlobalInvocationID.x;
	if (id >= uint(pc.particle_count)) {
		return;
	}

	uint base = id * 2u;
	vec4 p0 = particles.particle_data[base + 0u];
	vec4 p1 = particles.particle_data[base + 1u];

	float age = p0.w;
	float lifetime = max(p1.w, 0.001);
	bool respawn = age <= 0.0 || age >= lifetime || p0.y < (pc.base_y - 6.0);

	if (respawn && pc.emitter_count > 0) {
		int emitter_index = int(id % uint(pc.emitter_count));
		vec4 e0 = emitters.emitter_data[emitter_index * 2];
		vec4 e1 = emitters.emitter_data[emitter_index * 2 + 1];
		vec2 rand2 = hash21(float(id) + floor(pc.time * 60.0));
		vec2 dir = normalize(e1.zw);
		if (length(dir) < 0.001) {
			dir = vec2(1.0, 0.0);
		}
		vec2 tangent = vec2(-dir.y, dir.x);
		float width = max(e0.w, 0.001);
		float height = e0.z;
		float curl = max(e1.x, 0.2);
		float base_t = clamp(e1.y, 0.0, 1.0);
		float crest_offset = mix(-width * 0.4, width * 0.4, rand2.x);
		float forward_offset = mix(-width * 0.05, width * 0.22, rand2.y);
		vec2 spawn_xz = e0.xy + tangent * crest_offset + dir * forward_offset;
		float spawn_y = pc.base_y + height * (0.15 + base_t * 0.2);
		vec2 side_rand = hash21(float(id) * 1.37 + 11.0) * 2.0 - 1.0;
		vec3 vel = vec3(
			tangent.x * side_rand.x * 2.0 + dir.x * (1.5 + rand2.x * 3.0),
			(3.0 + rand2.y * 5.0) * curl,
			tangent.y * side_rand.y * 2.0 + dir.y * (1.5 + rand2.x * 3.0)
		);
		particles.particle_data[base + 0u] = vec4(spawn_xz.x, spawn_y, spawn_xz.y, 0.001);
		particles.particle_data[base + 1u] = vec4(vel, 0.8 + hash11(float(id) + 9.0) * 1.3);
		return;
	}

	vec3 pos = vec3(p0.xyz);
	vec3 vel = vec3(p1.xyz);
	vel.y -= pc.gravity * pc.dt;
	vel *= max(1.0 - pc.drag * pc.dt, 0.0);
	pos += vel * pc.dt;
	if (pos.y < pc.base_y) {
		pos.y = pc.base_y;
		vel *= 0.35;
		vel.y = abs(vel.y) * 0.15;
	}
	particles.particle_data[base + 0u] = vec4(pos, age + pc.dt);
	particles.particle_data[base + 1u] = vec4(vel, lifetime);
}
