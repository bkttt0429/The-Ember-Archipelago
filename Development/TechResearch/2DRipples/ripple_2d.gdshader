shader_type canvas_item;

// Maximum number of concurrent ripples
const int MAX_RIPPLES = 100;

// Ripple Data: x=u, y=v, z=start_time, w=padding
uniform vec4 ripples[MAX_RIPPLES];
uniform int ripple_count = 0;

uniform float time_scale = 1.0;
uniform float game_time = 0.0; // Driven by script
uniform float frequency = 20.0;     // How tightly packed the waves are
uniform float wave_speed = 5.0;     // Propagation speed
uniform float decay_factor = 3.0;   // How fast the amplitude drops over distance
uniform float duration = 2.0;       // Hard cutoff or fadeout time
uniform float amplitude_strength = 0.05; // Distortion strength

void fragment() {
    vec2 uv = UV;
    vec2 offset = vec2(0.0);
    
    float current_time = game_time * time_scale;
    
    // Iterate through active ripples
    for (int i = 0; i < MAX_RIPPLES; i++) {
        if (i >= ripple_count) break;
        
        vec3 ripple = ripples[i].xyz;
        vec2 center = ripple.xy;
        float start_t = ripple.z;
        
        float t = current_time - start_t;
        
        // Ignore future or expired ripples
        if (t < 0.0 || t > duration) continue;
        
        // Correct aspect ratio for circular ripples if texture is not square
        // Assuming square UV for simplicity, calculating distance in UV space
        // For non-square, multiply uv.x by aspect ratio
        vec2 dir = uv - center;
        float dist = length(dir);
        
        // Ripple Function:
        // 1. Expansion: sin(dist * freq - t * speed)
        // 2. Decay pattern: exp(-dist * decay) * (1.0 - t/duration)
        
        // Calculate wave phase
        // Waves move OUT, so phase = dist - t * speed
        float phase = dist * frequency - t * wave_speed;
        
        // Generic Ripple Shape: Sin wave
        float sine_wave = sin(phase);
        
        // Distance Decay: Amplitude drops as 1 / (1 + dist*k)
        float dist_decay = 1.0 / (1.0 + dist * decay_factor);
        
        // Time Decay: Linear fade out at the end of duration
        float time_decay = smoothstep(duration, duration * 0.5, t); 
        
        // Combined Amplitude
        // We only want ripples BEHIND the wavefront? 
        // Typically ripple shader is sin(freq * (dist - time))
        // This generates rings everywhere. 
        // To make it look like a "pulse" moving out, we can limit it.
        // But continuous sine is fine for "ripples".
        
        float amp = sine_wave * dist_decay * time_decay;
        
        // Directional displacement
        // Normalize direction but avoid div by zero
        vec2 norm_dir = (dist > 0.001) ? dir / dist : vec2(0.0);
        
        // Accumulate offset
        offset += norm_dir * amp * amplitude_strength;
    }
    
    // Apply distortion to texture lookup
    COLOR = texture(TEXTURE, uv + offset);
}
