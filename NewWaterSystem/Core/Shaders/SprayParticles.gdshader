shader_type particles;

// 複製自 SimpleBarrelTest.gdshader 的波浪參數
uniform float time_scale = 1.0;
uniform float wave_height = 2.0;
uniform float steepness = 0.8;
uniform vec2 wave_direction = vec2(1.0, 0.5);
uniform float breaking_threshold = 0.6; // 必須與水面一致
uniform float curl_force = 1.5;

// 粒子物理參數
uniform float initial_speed = 5.0;
uniform float spread = 0.5;
uniform float gravity = 9.8;

// 隨機數生成
float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0)
	s = 305420679;
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0)
		s += 2147483647;
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

// 貝茲曲線 (用於計算發射位置)
vec3 cubic_bezier(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
    float u = 1.0 - t;
    float tt = t * t;
    float uu = u * u;
    float uuu = uu * u;
    float ttt = tt * t;
    
    vec3 p = uuu * p0; 
    p += 3.0 * uu * t * p1; 
    p += 3.0 * u * t * t * p2; 
    p += ttt * p3; 
    return p;
}

void start() {
	uint seed = NUMBER + uint(TIME * 1000.0) + uint(INDEX);
	
	// 1. 隨機分佈在海面上 (假設網格大小 50x50，與 PlaneMesh 一致)
	vec2 pos_xz = vec2(rand_from_seed(seed) * 50.0 - 25.0, rand_from_seed(seed) * 50.0 - 25.0);
	
	// 2. 計算該位置的波浪高度 (複製自 Vertex Shader)
	float time = TIME * time_scale;
	vec2 d = normalize(wave_direction);
	float f = dot(d, pos_xz) - time;
	
	float sin_f = sin(f);
	float cos_f = cos(f);
	float sharp_factor = exp(sin_f - 1.0);
	
	vec3 displacement = vec3(0.0);
	float current_height = wave_height * sharp_factor;
	
	displacement.y = current_height;
	vec2 hor_disp = d * -sin_f * steepness * sharp_factor * wave_height * 0.5;
	displacement.x += hor_disp.x;
	displacement.z += hor_disp.y;
	
	float asymmetry = max(0.0, displacement.y - wave_height * 0.2);
    vec2 push = d * asymmetry * 1.0;
    displacement.x -= push.x;
    displacement.z -= push.y;
	
	// 基礎位置
	vec3 P_base = vec3(pos_xz.x, 0.0, pos_xz.y) + displacement;
	
	// 3. 判斷是否在浪尖 (Breaking condition)
	float t_curl = smoothstep(breaking_threshold, wave_height * 1.5, displacement.y);
	
	// 嚴格過濾：只在捲曲最劇烈的地方發射 (接近 t=1.0)
	// 這樣粒子只會從浪唇飛出
	if (t_curl > 0.6) {
		// 計算捲曲後的準確發射點
		vec3 p0 = displacement;
        vec3 p1 = displacement + vec3(0.0, 1.8, 0.0) * curl_force; 
        vec3 p2 = displacement + vec3(d.x, 1.2, d.y) * curl_force * 1.2; 
        vec3 p3 = displacement + vec3(d.x * 0.5, -2.0, d.y * 0.5) * curl_force; 
		
		vec3 disp_curled = mix(displacement, cubic_bezier(p0, p1, p2, p3, t_curl), t_curl * t_curl);
		
		// 設定粒子位置：加上原始 XZ 座標
		TRANSFORM[3].xyz = vec3(pos_xz.x, 0.0, pos_xz.y) + disp_curled;
		
		// 設定速度：沿著波浪方向向前拋出 + 隨機擴散
		vec3 vel_dir = normalize(vec3(d.x, 0.5, d.y)); // 向前上方
		// 加入隨機性
		vel_dir.x += (rand_from_seed(seed) - 0.5) * spread;
		vel_dir.y += (rand_from_seed(seed) - 0.5) * spread;
		vel_dir.z += (rand_from_seed(seed) - 0.5) * spread;
		
		VELOCITY = normalize(vel_dir) * initial_speed;
		
		// 設定生命週期 (讓它有時間落下)
		// 注意：如果不在浪尖，我們會在下面殺死它
		COLOR = vec4(1.0); // 可見
	} else {
		// 不在浪尖，隱藏並停止
		TRANSFORM[3].xyz = vec3(0.0, -1000.0, 0.0); // 移到地底
		VELOCITY = vec3(0.0);
		COLOR = vec4(0.0); // 隱形
		// 也可以將 scale 設為 0
	}
}

void process() {
	// 簡單重力模擬
	VELOCITY.y -= gravity * DELTA;
	
	// 更新位置
	TRANSFORM[3].xyz += VELOCITY * DELTA;
	
	// 碰撞地面(海面)簡單處理：如果掉太低就消失
	if (TRANSFORM[3].y < -2.0) {
		COLOR.a = max(0.0, COLOR.a - DELTA * 2.0);
	}
}
