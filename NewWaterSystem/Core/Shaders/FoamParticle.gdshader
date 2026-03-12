shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
render_mode billboard_enabled;

uniform sampler2D particle_texture : hint_default_white;
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
    // 從 INSTANCE_CUSTOM 讀取數據
    float life_factor = INSTANCE_CUSTOM.r;
    float velocity = INSTANCE_CUSTOM.g;
    
    // 紋理採樣（使用圓形遮罩）
    vec2 centered_uv = UV - vec2(0.5);
    float dist = length(centered_uv);
    float circle_mask = smoothstep(0.5, 0.3, dist);
    
    // 添加噪聲變化
    float noise = texture(particle_texture, UV * 2.0).r;
    circle_mask *= mix(0.7, 1.0, noise);
    
    // 根據速度拉伸（快速移動的粒子）
    float stretch = mix(1.0, 0.5, velocity);
    circle_mask *= mix(1.0, stretch, step(0.5, UV.y));
    
    ALBEDO = foam_color;
    ALPHA = circle_mask * life_factor * 0.8;
    
    // 添加微弱的發光
    EMISSION = foam_color * 0.2 * life_factor;
}
