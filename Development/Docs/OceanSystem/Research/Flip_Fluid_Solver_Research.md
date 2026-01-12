# Godot 4 Compute Shader: FLIP 流體解算器實作研究

本研究文檔詳細說明如何在 Godot 4 中實作 FLIP (Fluid-Implicit Particle) 流體解算器的核心機制，重點在於高效的 P2G (Particle to Grid) 與 G2P (Grid to Particle) 傳輸邏輯。

## 核心系統架構

### 1. 數據結構 (Data Structures)

#### 粒子緩衝區 (Particle Buffer)
我們使用一個 `StorageBuffer` 來存儲所有粒子的狀態。每個粒子由以下結構組成：

```glsl
struct Particle {
    vec3 pos;
    float padding1;
    vec3 vel;
    float padding2;
    vec4 color;
};

layout(set = 0, binding = 0, std430) buffer ParticleBuffer {
    Particle particles[];
};
```

#### 3. MAC Grid (Staggered Grid)
使用單一 `StorageBuffer` 模擬 3D MAC Grid。為了處理 P2G 階段的併發寫入，我們將浮點數權重與動量轉換為整數後使用 `atomicAdd`。

```glsl
layout(set = 0, binding = 1, std430) buffer GridBuffer {
    // 佈局示例：[Weight, VelX, VelY, VelZ] 的連續數據
    int grid_data[]; 
};
```

## 核心演算流程

### P2G (Particle to Grid)
粒子將其屬性分發到周圍的網格節點上。

*   **併發處理**：由於多個粒子可能同時寫入同一節點，使用 `atomicAdd`。由於 GLSL 不支持對浮點緩衝區直接執行 `atomicAdd`，我們將數值乘上一個大係數（如 `1000.0`）轉為整數。
*   **權重內核**：使用線性插值內核 (Linear Kernel) $N(d) = \max(0, 1 - |d|)$。

### G2P (Grid to Particle)
網格將解算後的場回饋給粒子，更新粒子的速度與位置。

*   **Hybrid FLIP/PIC**：
    *   **PIC**：直接採樣網格速度 $v_{new}$。
    *   **FLIP**：計算網格速度變化 $\Delta v = v_{new} - v_{old}$，並加回原粒子速度。
    *   **混合公式**：$v_{particle} = \alpha \cdot v_{FLIP} + (1 - \alpha) \cdot v_{PIC}$。

## Compute Shader 實作範例 (GLSL)

```glsl
// P2G 傳輸邏輯片段
void transfer_p2g(uint p_idx) {
    Particle p = particles[p_idx];
    vec3 grid_pos = (p.pos - grid_origin) / cell_size;
    ivec3 base_cell = ivec3(floor(grid_pos - 0.5));

    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            for (int k = 0; k < 2; k++) {
                ivec3 cell = base_cell + ivec3(i, j, k);
                float weight = calculate_weight(grid_pos, cell);
                
                // 將 float 轉為整數以進行 atomicAdd
                uint addr = get_grid_address(cell);
                atomicAdd(grid_data[addr], int(weight * PRECISION));
                atomicAdd(grid_data[addr + 1], int(p.vel.x * weight * PRECISION));
                // ... y, z 同理
            }
        }
    }
}
```

## 渲染整合：SSAO 與深度緩衝區
為了讓流體支持 SSAO，我們需要將粒子渲染進深度緩衝區。

1.  **頂點變換**：Compute Shader 更新後的 `particles[].pos` 可直接綁定為 `ImmediateMesh` 或是 `MultiMesh` 的頂點緩衝區。
2.  **Point Sprites**：在頂點著色器中，將點擴展為 Quad。
3.  **深度寫入**：利用 `FRAGMENT` 中的 `DEPTH` 輸出計算球體深度，使粒子在視覺上呈現平滑的表面。

## GDScript 管理代碼 (RenderingDevice)

```gdscript
class_name FluidController extends Node

var rd: RenderingDevice
var shader: RID
var particle_buffer: RID
var grid_buffer: RID

func _setup_buffers(particle_count: int, grid_res: Vector3i):
    rd = RenderingServer.create_local_rendering_device()
    
    # 建立粒子緩衝區
    var p_data = PackedFloat32Array() # 初始化數據
    particle_buffer = rd.storage_buffer_create(p_data.size() * 4, p_data.to_byte_array())
    
    # 建立 Grid 緩衝區 (Int 數組用於 Atomic)
    var g_size = grid_res.x * grid_res.y * grid_res.z * 4 
    grid_buffer = rd.storage_buffer_create(g_size * 4)
    
    # 管理生命週期
    # 注意：在 Node 銷毀時需手動 rd.free_rid(buffer)
```

## 結論
透過 Godot 4 的 `RenderingDevice` 與 `atomicAdd` 技巧，我們能在 GPU 上高效完成 FLIP 流體解算，並透過與頂點流水線的結合，實作高品質的流體視覺效果。
