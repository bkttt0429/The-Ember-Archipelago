#[compute]
#version 450

// Constants
#define THREAD_GROUP_SIZE 64
#define PRECISION 100000.0

layout(local_size_x = THREAD_GROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

// Structures
struct Particle {
    vec3 pos;
    float padding1; // alignment
    vec3 vel;
    float padding2; // alignment
    vec4 color;
};

// Buffers
layout(set = 0, binding = 0, std430) restrict buffer ParticleBuffer {
    Particle particles[];
};

// Grid Buffer: Each cell has 4 integers: [Weight, VelX, VelY, VelZ] (Packed)
// Modeled as a flat array. Size = GridRes.x * GridRes.y * GridRes.z * 4
layout(set = 0, binding = 1, std430) restrict buffer GridBuffer {
    int grid_data[];
};

// Pressure Buffer: Size = GridCells * 2 (Ping-Pong)
layout(set = 0, binding = 2, std430) restrict buffer PressureBuffer {
    float pressure_data[];
};

// Divergence Buffer: Size = GridCells
layout(set = 0, binding = 3, std430) restrict buffer DivergenceBuffer {
    float divergence_data[];
};

// Original Grid Buffer (For FLIP Delta): Same layout as GridBuffer
layout(set = 0, binding = 4, std430) restrict buffer OrigGridBuffer {
    int orig_grid_data[];
};

// Uniforms
layout(push_constant, std430) uniform Params {
    int mode;           // 0: Reset, 1: P2G, 2: GridUpdate, 3: G2P, 4: Div, 5: Jacobi, 6: Project, 7: CopyGrid
    float dt;
    vec3 grid_res;      // Grid resolution (cells), e.g., 64.0, 64.0, 64.0
    vec3 box_size;      // Physical size of the box, e.g., 10.0, 10.0, 10.0
    float padding;      
    vec3 gravity;
    float flip_ratio;   // 0.0 - 1.0 (e.g. 0.95)
    
    // Interaction
    vec3 interact_pos;  // 64 (align 16)
    float interact_radius; // 76
    float interact_strength; // 80 
    int is_interacting; // 84 - Also used as Loop Flag for Jacobi (0 or 1)
};

// Helper to get 1D grid index from 3D coordinates
int get_grid_address(ivec3 cell) {
    if (cell.x < 0 || cell.x >= int(grid_res.x) ||
        cell.y < 0 || cell.y >= int(grid_res.y) ||
        cell.z < 0 || cell.z >= int(grid_res.z)) {
        return -1;
    }
    return (int(cell.z) * int(grid_res.x) * int(grid_res.y) + int(cell.y) * int(grid_res.x) + int(cell.x)) * 4;
}

int get_scalar_address(ivec3 cell) {
     if (cell.x < 0 || cell.x >= int(grid_res.x) ||
        cell.y < 0 || cell.y >= int(grid_res.y) ||
        cell.z < 0 || cell.z >= int(grid_res.z)) {
        return -1;
    }
    return (int(cell.z) * int(grid_res.x) * int(grid_res.y) + int(cell.y) * int(grid_res.x) + int(cell.x));
}

// ------------------------------------------------------------------
// STAGE 0: RESET GRID
// ------------------------------------------------------------------
void stage_reset_grid(uint id) {
    uint total_cells = uint(grid_res.x * grid_res.y * grid_res.z);
    if (id < total_cells) {
        uint addr = id * 4;
        grid_data[addr + 0] = 0; // Weight
        grid_data[addr + 1] = 0; // AvgVelX
        grid_data[addr + 2] = 0; // AvgVelY
        grid_data[addr + 3] = 0; // AvgVelZ
        
        // Also clear Divergence and Pressure to prevent energy buildup during diagnosis
        divergence_data[id] = 0.0;
        pressure_data[id] = 0.0;
        pressure_data[id + total_cells] = 0.0;
    }
}

// ------------------------------------------------------------------
// STAGE 1: P2G (Particle to Grid)
// ------------------------------------------------------------------
void stage_p2g(uint id) {
    if (id >= particles.length()) return; // Bounds check
    
    Particle p = particles[id];
    vec3 cell_size = box_size / grid_res;
    vec3 grid_pos = p.pos / cell_size;
    
    // 3D Kernel distribution (Trilinear)
    ivec3 base_cell = ivec3(floor(grid_pos - 0.5));
    vec3 fract_pos = grid_pos - 0.5 - vec3(base_cell);
    
    // Loop over 2x2x2 neighbor cells
    for (int k = 0; k < 2; k++) {
        for (int j = 0; j < 2; j++) {
            for (int i = 0; i < 2; i++) {
                ivec3 offset = ivec3(i, j, k);
                ivec3 current_cell = base_cell + offset;
                
                // Weight Calculation (Linear)
                vec3 dist = abs(vec3(offset) - fract_pos);
                float weight = (1.0 - dist.x) * (1.0 - dist.y) * (1.0 - dist.z);
                
                // Add to Grid (Atomic Add)
                int addr = get_grid_address(current_cell);
                if (addr != -1) {
                    // Scale values to int for atomicAdd
                    int i_weight = int(weight * PRECISION);
                    int i_vx = int(p.vel.x * weight * PRECISION);
                    int i_vy = int(p.vel.y * weight * PRECISION);
                    int i_vz = int(p.vel.z * weight * PRECISION);
                    
                    atomicAdd(grid_data[addr + 0], i_weight);
                    atomicAdd(grid_data[addr + 1], i_vx);
                    atomicAdd(grid_data[addr + 2], i_vy);
                    atomicAdd(grid_data[addr + 3], i_vz);
                }
            }
        }
    }
}

// ------------------------------------------------------------------
// STAGE 2: GRID UPDATE (Normalize + Gravity + Bounds + Interaction)
// ------------------------------------------------------------------
void stage_grid_update(uint id) {
    uint total_cells = uint(grid_res.x * grid_res.y * grid_res.z);
    if (id >= total_cells) return;

    uint addr = id * 4;
    int i_weight = grid_data[addr + 0];
    
    vec3 vel = vec3(0.0);
    
    if (i_weight > 0) {
        float weight = float(i_weight) / PRECISION;
        vel.x = float(grid_data[addr + 1]) / PRECISION;
        vel.y = float(grid_data[addr + 2]) / PRECISION;
        vel.z = float(grid_data[addr + 3]) / PRECISION;
        
        vel /= weight;
        
        // Apply External Forces (Gravity)
        vel += gravity * dt;
        
        // Damping (3% per sub-step) to help pool formation
        vel *= 0.97;
        
        // Max velocity clamp for grid stability
        float g_limit = 25.0;
        if (length(vel) > g_limit) vel = normalize(vel) * g_limit;

        // Apply Interaction Force
        if (is_interacting > 0) {
            // Cell pos calculation
            uint idx = id; uint r_x = uint(grid_res.x); uint r_y = uint(grid_res.y);
            uint cz = idx / (r_x * r_y); uint rem = idx % (r_x * r_y);
            uint cy = rem / r_x; uint cx = rem % r_x;
            
            vec3 cell_pos_world = (vec3(cx, cy, cz) + 0.5) * (box_size / grid_res);
            float dist = distance(cell_pos_world, interact_pos);
            if (dist < interact_radius) {
                vec3 dir = normalize(cell_pos_world - interact_pos);
                vel += dir * interact_strength * dt * (1.0 - dist / interact_radius);
                vel.y += interact_strength * 0.5 * dt;
            }
        }
    }
        
    // Boundary Conditions
    uint idx = id; uint res_x = uint(grid_res.x); uint res_y = uint(grid_res.y);
    uint z = idx / (res_x * res_y); uint rem = idx % (res_x * res_y);
    uint y = rem / res_x; uint x = rem % res_x;
    
    // Floor and Ceiling
    if (y <= 1) vel.y = max(vel.y, 0.0);
    if (y >= res_y - 2) vel.y = min(vel.y, 0.0);
    // Walls
    if (x <= 1 || x >= res_x - 2) vel.x = 0.0;
    if (z <= 1 || z >= uint(grid_res.z) - 2) vel.z = 0.0;

    // Write back
    grid_data[addr + 1] = int(vel.x * PRECISION);
    grid_data[addr + 2] = int(vel.y * PRECISION);
    grid_data[addr + 3] = int(vel.z * PRECISION);
}

// ------------------------------------------------------------------
// STAGE 7: COPY GRID (Backup for FLIP)
// ------------------------------------------------------------------
void stage_copy_grid(uint id) {
    uint total_ints = uint(grid_res.x * grid_res.y * grid_res.z * 4.0);
    if (id < total_ints) {
        orig_grid_data[id] = grid_data[id];
    }
}

// ------------------------------------------------------------------
// STAGE 4: DIVERGENCE
// ------------------------------------------------------------------
void stage_divergence(uint id) {
    uint total_cells = uint(grid_res.x * grid_res.y * grid_res.z);
    if (id >= total_cells) return;
    
    uint idx = id; uint res_x = uint(grid_res.x); uint res_y = uint(grid_res.y);
    uint z = idx / (res_x * res_y); uint rem = idx % (res_x * res_y);
    uint y = rem / res_x; uint x = rem % res_x;
    
    // Div = (du/dx + dv/dy + dw/dz)
    // Central difference: (v_right - v_left + v_up - v_down + v_front - v_back) / 2
    
    // Helper to safety sample velocity (return 0 if out of bounds -> Solid Wall)
    // This assumes walls have V=0 (No Slip or Normal=0 for Free Slip).
    // Actually, for Free Slip, tangential velocity is non-zero.
    // BUT, here we sample the orthogonal component.
    // e.g. for vx_r (at x+1), if x+1 is wall, grid_data[x+1].vel.x is 0.
    // My GridUpdate sets vel.x=0 at boundary x=0 and x=res-1.
    // So direct sampling of grid_data is safe provided we don't access memory out of bounds (addr -1).
    
    // Bounds handling for memory access
    int addr_c = get_grid_address(ivec3(x, y, z));
    int addr_l = get_grid_address(ivec3(x-1, y, z));
    int addr_r = get_grid_address(ivec3(x+1, y, z));
    int addr_d = get_grid_address(ivec3(x, y-1, z));
    int addr_u = get_grid_address(ivec3(x, y+1, z));
    int addr_b = get_grid_address(ivec3(x, y, z-1));
    int addr_f = get_grid_address(ivec3(x, y, z+1));
    
    float vx_r = (addr_r != -1) ? float(grid_data[addr_r + 1]) / PRECISION : 0.0;
    float vx_l = (addr_l != -1) ? float(grid_data[addr_l + 1]) / PRECISION : 0.0;
    float vy_u = (addr_u != -1) ? float(grid_data[addr_u + 2]) / PRECISION : 0.0;
    float vy_d = (addr_d != -1) ? float(grid_data[addr_d + 2]) / PRECISION : 0.0;
    float vz_f = (addr_f != -1) ? float(grid_data[addr_f + 3]) / PRECISION : 0.0;
    float vz_b = (addr_b != -1) ? float(grid_data[addr_b + 3]) / PRECISION : 0.0;
    
    float div = (vx_r - vx_l + vy_u - vy_d + vz_f - vz_b) * 0.5;
    
    // Modest Div boost (4.0) to balance gap filling vs stability
    div *= 4.0; 
    
    divergence_data[id] = div;
}

// ------------------------------------------------------------------
// STAGE 5: JACOBI (Pressure Solve)
// ------------------------------------------------------------------
void stage_jacobi(uint id) {
    uint total_cells = uint(grid_res.x * grid_res.y * grid_res.z);
    if (id >= total_cells) return;
    
    // is_interacting used as FLAG for PingPong: 0 means Read=0,Write=1. 1 means Read=1, Write=0.
    uint read_offset = (is_interacting == 0) ? 0 : total_cells;
    uint write_offset = (is_interacting == 0) ? total_cells : 0;

    float div = divergence_data[id];
    // Pure Divergence (1.0) for stability test
    div *= 1.0; 

    uint idx = id; uint res_x = uint(grid_res.x); uint res_y = uint(grid_res.y);
    uint z = idx / (res_x * res_y); uint rem = idx % (res_x * res_y);
    uint y = rem / res_x; uint x = rem % res_x;
    
    // Helper indices
    int aL = get_scalar_address(ivec3(int(x)-1, int(y), int(z)));
    int aR = get_scalar_address(ivec3(int(x)+1, int(y), int(z)));
    int aD = get_scalar_address(ivec3(int(x), int(y)-1, int(z)));
    int aU = get_scalar_address(ivec3(int(x), int(y)+1, int(z)));
    int aB = get_scalar_address(ivec3(int(x), int(y), int(z)-1));
    int aF = get_scalar_address(ivec3(int(x), int(y), int(z)+1));
    
    float pC = pressure_data[read_offset + id];
    
    // Neighbors
    float sum_p = 0.0;
    int active_neighbors = 0;
    
    // For each direction, if neighbor is valid grid (not Wall), add its P.
    // If neighbor is Wall, dP/dn = 0 implies P_neighbor = P_self. 
    // Mathematically: (P_neighbor - P_self) / 1^2.
    // So if neighbor is wall, the term becomes (P_self - P_self) = 0.
    // This reduces the '6' in the denominator.
    
    if (aL != -1) { sum_p += pressure_data[read_offset + aL]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; } // Neumann
    if (aR != -1) { sum_p += pressure_data[read_offset + aR]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; }
    if (aD != -1) { sum_p += pressure_data[read_offset + aD]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; }
    if (aU != -1) { sum_p += pressure_data[read_offset + aU]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; }
    if (aB != -1) { sum_p += pressure_data[read_offset + aB]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; }
    if (aF != -1) { sum_p += pressure_data[read_offset + aF]; active_neighbors++; }
    else { active_neighbors++; sum_p += pC; }
    
    // Laplacian discretized at boundary: (Sum - n*P_self) = div
    // P_self = (Sum - div) / n
    float calculated_p = pC;
    if (active_neighbors > 0) {
        calculated_p = (sum_p - div) / float(active_neighbors);
    }
    
    // Omega 1.1 for stable convergence (prevents jitter)
    // Omega 1.5 for faster pressure propagation
    pressure_data[write_offset + id] = mix(pC, calculated_p, 1.5);
}

// ------------------------------------------------------------------
// STAGE 6: PROJECT (Subtract Gradient)
// ------------------------------------------------------------------
void stage_project(uint id) {
    uint total_cells = uint(grid_res.x * grid_res.y * grid_res.z);
    if (id >= total_cells) return;
    
    // Only update cells that are either fluid or immediately adjacent to fluid
    // (Extrapolation)
    int weight = grid_data[id * 4];
    float div = divergence_data[id];
    
    // If the cell is completely isolated and empty, don't update to avoid noise
    if (weight <= 0 && abs(div) < 0.001) return;
    
    uint p_offset = 0;
    
    uint idx = id; uint res_x = uint(grid_res.x); uint res_y = uint(grid_res.y);
    uint z = idx / (res_x * res_y); uint rem = idx % (res_x * res_y);
    uint y = rem / res_x; uint x = rem % res_x;
    
    // Gradient Calculation with Boundary Checks
    int aL = get_scalar_address(ivec3(int(x)-1, int(y), int(z)));
    int aR = get_scalar_address(ivec3(int(x)+1, int(y), int(z)));
    int aD = get_scalar_address(ivec3(int(x), int(y)-1, int(z)));
    int aU = get_scalar_address(ivec3(int(x), int(y)+1, int(z)));
    int aB = get_scalar_address(ivec3(int(x), int(y), int(z)-1));
    int aF = get_scalar_address(ivec3(int(x), int(y), int(z)+1));
    
    // For projection, if wall (addr=-1), we assume dP/dn = 0.
    // So P_wall = P_self.
    // Gradient across wall = (P_wall - P_self) = 0. Correct.
    float pC = pressure_data[p_offset + id];
    
    float pL = (aL != -1) ? pressure_data[p_offset + aL] : pC;
    float pR = (aR != -1) ? pressure_data[p_offset + aR] : pC;
    float pD = (aD != -1) ? pressure_data[p_offset + aD] : pC;
    float pU = (aU != -1) ? pressure_data[p_offset + aU] : pC;
    float pB = (aB != -1) ? pressure_data[p_offset + aB] : pC;
    float pF = (aF != -1) ? pressure_data[p_offset + aF] : pC;
    
    // Gradient (Central Diff)
    uint addr = id * 4;
    float vx = float(grid_data[addr + 1]) / PRECISION;
    float vy = float(grid_data[addr + 2]) / PRECISION;
    float vz = float(grid_data[addr + 3]) / PRECISION;
    
    // Subtract Gradient
    vx -= (pR - pL) * 0.5;
    vy -= (pU - pD) * 0.5;
    vz -= (pF - pB) * 0.5;
    
    float max_v = 20.0; // Restored generous clamp
    vx = clamp(vx, -max_v, max_v);
    vy = clamp(vy, -max_v, max_v);
    vz = clamp(vz, -max_v, max_v);
    
    grid_data[addr + 1] = int(vx * PRECISION);
    grid_data[addr + 2] = int(vy * PRECISION);
    grid_data[addr + 3] = int(vz * PRECISION);
}

// ------------------------------------------------------------------
// STAGE 3: G2P (Grid to Particle) & ADVECTION & FLIP
// ------------------------------------------------------------------
void stage_g2p(uint id) {
    if (id >= particles.length()) return;
    
    Particle p = particles[id];
    vec3 cell_size = box_size / grid_res;
    vec3 grid_pos = p.pos / cell_size;
    
    ivec3 base_cell = ivec3(floor(grid_pos - 0.5));
    vec3 fract_pos = grid_pos - 0.5 - vec3(base_cell);
    
    vec3 new_vel = vec3(0.0);
    vec3 old_vel = vec3(0.0); // Pre-projection velocity (from orig_grid_buffer)
    
    // Gather velocity
    for (int k = 0; k < 2; k++) {
        for (int j = 0; j < 2; j++) {
            for (int i = 0; i < 2; i++) {
                ivec3 offset = ivec3(i, j, k);
                ivec3 current_cell = base_cell + offset;
                vec3 dist = abs(vec3(offset) - fract_pos);
                float weight = (1.0 - dist.x) * (1.0 - dist.y) * (1.0 - dist.z);
                
                int addr_int = get_grid_address(current_cell);
                if (addr_int != -1) {
                     uint addr = uint(addr_int);

                     // NEW VELOCITY (Already normalized in GridUpdate)
                     vec3 v_new;
                     v_new.x = float(grid_data[addr + 1]) / PRECISION;
                     v_new.y = float(grid_data[addr + 2]) / PRECISION;
                     v_new.z = float(grid_data[addr + 3]) / PRECISION;
                     new_vel += v_new * weight;
                     
                     // OLD VELOCITY (Stored as Momentum in OrigGrid, needs Normalization)
                     float node_w = float(orig_grid_data[addr + 0]) / PRECISION;
                     if (node_w > 0.0) {
                         old_vel.x += (float(orig_grid_data[addr + 1]) / (node_w * PRECISION)) * weight;
                         old_vel.y += (float(orig_grid_data[addr + 2]) / (node_w * PRECISION)) * weight;
                         old_vel.z += (float(orig_grid_data[addr + 3]) / (node_w * PRECISION)) * weight;
                     }
                }
            }
        }
    }
    
    // FLIP Blend
    // PIC = new_vel
    // FLIP = particle.vel + (new_vel - old_vel)
    vec3 pic_vel = new_vel;
    vec3 flip_vel = p.vel + (new_vel - old_vel);
    
    vec3 final_vel = mix(new_vel, p.vel + (new_vel - old_vel), flip_ratio);
    
    // 1% additional damp
    final_vel *= 0.99;
    
    float max_v = 20.0;
    if (length(final_vel) > max_v) final_vel = normalize(final_vel) * max_v;
    p.vel = final_vel;
    
    // Position Update (Advection)
    vec3 next_pos = p.pos + p.vel * dt;
    
    // Boundary reflection with slight bounce (0.2)
    float margin = 0.1;
    if (next_pos.x < margin) { next_pos.x = margin; p.vel.x = abs(p.vel.x) * 0.2; }
    if (next_pos.x > box_size.x - margin) { next_pos.x = box_size.x - margin; p.vel.x = -abs(p.vel.x) * 0.2; }
    if (next_pos.y < margin) { next_pos.y = margin; p.vel.y = abs(p.vel.y) * 0.2; }
    if (next_pos.y > box_size.y - margin) { next_pos.y = box_size.y - margin; p.vel.y = -abs(p.vel.y) * 0.2; }
    if (next_pos.z < margin) { next_pos.z = margin; p.vel.z = abs(p.vel.z) * 0.2; }
    if (next_pos.z > box_size.z - margin) { next_pos.z = box_size.z - margin; p.vel.z = -abs(p.vel.z) * 0.2; }
    
    p.pos = next_pos;
    
    // Sample Pressure for Visualization
    float p_val = 0.0;
    int addr = get_scalar_address(ivec3(floor(p.pos / cell_size)));
    if (addr != -1) p_val = pressure_data[addr];
    
    p.color = vec4(clamp(p_val * 0.1, 0.0, 1.0), length(p.vel) * 0.05, 0.0, 1.0);
    
    particles[id] = p;
}


void main() {
    uint id = gl_GlobalInvocationID.x;
    
    if (mode == 0) {
        stage_reset_grid(id);
    } else if (mode == 1) {
        stage_p2g(id);
    } else if (mode == 2) {
        stage_grid_update(id);
    } else if (mode == 3) {
        stage_g2p(id);
    } else if (mode == 4) {
        stage_divergence(id);
    } else if (mode == 5) {
        stage_jacobi(id);
    } else if (mode == 6) {
        stage_project(id);
    } else if (mode == 7) {
        stage_copy_grid(id);
    }
}
