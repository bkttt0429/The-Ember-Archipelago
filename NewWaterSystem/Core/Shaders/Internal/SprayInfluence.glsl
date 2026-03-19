#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform writeonly image2D spray_out;

layout(set = 0, binding = 1, std430) readonly buffer SprayParams {
	vec4 waves[6];
} spray_params;

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

	float mist = 0.0;
	float core = 0.0;
	for (int i = 0; i < pc.count; i++) {
		vec4 data = spray_params.waves[i];
		vec4 params = spray_params.waves[i + 3];
		vec2 center = data.xy;
		float height = data.z;
		float width = max(data.w, 0.001);
		float curl = max(params.x, 0.0);
		float base_t = clamp(params.y, 0.0, 1.0);
		vec2 dir = params.zw;
		float dir_len = length(dir);
		if (dir_len < 0.001) {
			continue;
		}
		dir /= dir_len;
		vec2 tangent_dir = vec2(-dir.y, dir.x);
		vec2 to_wave = world - center;
		float along = dot(to_wave, dir);
		float across = dot(to_wave, tangent_dir);

		float crest_band = exp(-pow(across / max(width * 0.26, 0.001), 2.0));
		float lip_zone = smoothstep(-width * 0.18, width * 0.08, along) * (1.0 - smoothstep(width * 0.18, width * 0.82, along));
		float mist_zone = smoothstep(-width * 0.08, width * 0.25, along) * (1.0 - smoothstep(width * 0.3, width * 1.1, along));
		float fall_zone = smoothstep(0.4, 0.92, base_t);
		float energy = clamp(height * max(curl, 0.25), 0.0, 8.0);

		float wave_core = crest_band * lip_zone * fall_zone * clamp(energy / 4.0, 0.25, 1.0);
		float wave_mist = crest_band * mist_zone * fall_zone * clamp(energy / 6.0, 0.15, 1.0);

		core = max(core, wave_core);
		mist += wave_mist;
	}

	mist = clamp(mist, 0.0, 1.0);
	core = clamp(core, 0.0, 1.0);
	imageStore(spray_out, gid, vec4(core, mist, 0.0, max(core, mist)));
}
