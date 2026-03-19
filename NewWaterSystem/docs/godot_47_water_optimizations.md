# Godot 4.7 水體系統可用優化分析

> **基於代碼精讀** — `WaterManager.gd`、`BuoyancyComponent.gd`、`OceanLODManager.gd`、`ripple_simulation.gdshader`
> 日期：2026-03-14

---

## 優先等級
- 🔴 **立即有感** — 升級當天或同時就能改
- 🟡 **中期值得** — 需要一些設定或測試時間
- 🟢 **長遠技術債** — 利用 4.7 新能力重構

---

## 🔴 優化 1：Bent Normal Map → 水面 SSS 和 AO 更真實

**對應 4.7 PR**: [GH-114336](https://github.com/godotengine/godot/pull/114336) — Compatibility 渲染器新增 Bent Normal Map

**你的現況** (`WaterManager.gd` 的 `ocean_surface.gdshader`):
你的水體 shader 使用了 SSS (`sss_strength`, `sss_color`) 和法線貼圖疊加，但目前在 Compatibility 模式下無法使用 Bent Normal Map。

**4.7 之後可以做**:
```glsl
// ocean_surface.gdshader 新增
// 用水面 Gerstner 波法線作為 Bent Normal，改善水下散射感
// 在 Compatibility renderer 中現在可以這樣寫：
render_mode specular_schlick_ggx, diffuse_lambert, ambient_light_disabled;

void fragment() {
    // ... 現有代碼 ...
    
    // 4.7 新增：使用 Gerstner 法線作為 Bent Normal
    // 讓水面的 AO 計算更物理正確
    vec3 bent_normal = normalize(mix(NORMAL, analytical_normal, 0.5));
    // 用於 SSS：沿 bent_normal 方向的散射更真實
    float sss_factor = max(0.0, dot(bent_normal, -LIGHT_DIRECTION));
    BACKLIGHT = sss_color.rgb * sss_strength * sss_factor;
}
```

**實際效益**: 在 Compatibility 模式（你的 `project.godot` 沒有強制指定渲染器，預設 Forward+）下，
這個功能讓你的水體在低端設備上也能有更好的散射效果。

---

## 🔴 優化 2：`_find_water_mesh` 遞歸改用 `find_child()`

**對應 4.7**: Editor search API 改善 + 內建遞歸更高效

**你的現況** (`WaterManager.gd` L493-L503):
```gdscript
# ❌ 手寫 DFS，每次 _update_interaction_ripples() 都被呼叫
func _find_water_mesh(node: Node) -> MeshInstance3D:
    for child in node.get_children():
        if child is MeshInstance3D:
            var mat = child.get_active_material(0)
            if mat is ShaderMaterial:
                return child
        var result = _find_water_mesh(child)
        if result:
            return result
    return null
```

**問題**: `_update_interaction_ripples()` 每幀被呼叫，每次都掃描整個子樹。

**改法 1 — 快取**（最簡單）:
```gdscript
var _cached_water_mesh: MeshInstance3D = null

func _find_water_mesh_cached() -> MeshInstance3D:
    if is_instance_valid(_cached_water_mesh):
        return _cached_water_mesh
    # ✅ 使用 find_child (C++ 實作，比 GDScript 遞歸快)
    for child in find_children("*", "MeshInstance3D", true, false):
        if child.get_active_material(0) is ShaderMaterial:
            _cached_water_mesh = child
            return child
    return null
```

**改法 2 — `find_children()` 批量搜索**（一行代替整個函數）:
```gdscript
# _ready() 中一次性找到並快取
func _ready():
    # ...
    await get_tree().process_frame
    var meshes = find_children("*", "MeshInstance3D", true, false)
    for m in meshes:
        if m.get_active_material(0) is ShaderMaterial:
            _cached_water_mesh = m
            break
```

> [!IMPORTANT]
> 這個改動對你的系統效能影響顯著：`_update_interaction_ripples()` 每幀呼叫，快取後掃描次數從 N（子樹大小）降到 1。

---

## 🔴 優化 3：`_bake_obstacles()` — CPU 射線重災區改成批量版本

**對應 4.7**: Core 和 Physics 多個穩定性及效能修復

**你的現況** (`WaterManager.gd` L1373-L1400):
```gdscript
# ❌ 雙層迴圈：最壞情況 128*128 = 16384 次物理射線！
for y in range(grid_res):
    for x in range(grid_res):
        var query = PhysicsRayQueryParameters3D.create(...)
        var result = space_state.intersect_ray(query)  # 每次都是獨立 CPU 射線
```

**問題**: `grid_res = 128` 時，`_bake_obstacles()` 發出 **16,384 次射線**，
這在一幀裡造成嚴重卡頓（雖然它只在 `_ready()` 時執行一次）。

**4.7 兼容的改法 — 分幀執行**:
```gdscript
# 用協程分攤到多幀，避免單幀卡幀
func _bake_obstacles_async() -> void:
    if not is_inside_tree(): return
    var world = get_world_3d()
    if not world or not world.direct_space_state: return
    
    var space_state = world.direct_space_state
    var BATCH_SIZE = 64  # 每幀處理 64 個格子
    var obstacles_hit = 0
    
    # 重置 alpha
    for y in range(grid_res):
        for x in range(grid_res):
            var col = sim_image.get_pixel(x, y)
            col.a = 0.0
            sim_image.set_pixel(x, y, col)
    
    # 分幀執行射線 (grid_res^2 / BATCH_SIZE 幀)
    for y in range(grid_res):
        for x in range(grid_res):
            var uv = Vector2(x, y) / float(grid_res)
            var local_pos = Vector3((uv.x - 0.5) * sea_size.x, 100.0, (uv.y - 0.5) * sea_size.y)
            var world_pos = to_global(local_pos)
            
            var query = PhysicsRayQueryParameters3D.create(world_pos, world_pos + Vector3.DOWN * 200.0)
            query.collide_with_areas = false
            query.collide_with_bodies = true
            
            var result = space_state.intersect_ray(query)
            if result and result.position.y > global_position.y - 2.0:
                var col = sim_image.get_pixel(x, y)
                col.a = 1.0
                sim_image.set_pixel(x, y, col)
                obstacles_hit += 1
            
            # 每 BATCH_SIZE 個格子讓出一幀
            if (y * grid_res + x) % BATCH_SIZE == 0:
                await get_tree().process_frame
    
    # 上傳到 GPU
    if rd:
        rd.texture_update(sim_texture_A, 0, sim_image.get_data())
        rd.texture_update(sim_texture_B, 0, sim_image.get_data())
    visual_texture.update(sim_image)
    print("[WaterManager] Baked %d obstacles (async)" % obstacles_hit)
```

---

## 🔴 優化 4：`interaction_points` Array 改用更快的資料結構

**對應 4.7 PR**: [GH-116284](https://github.com/godotengine/godot/pull/116284) — `HashSet`/`RBMap` move semantics

**你的現況** (`WaterManager.gd` L317):
```gdscript
const MAX_INTERACTIONS = 128
var interaction_points: Array = []  # 用 Dictionary Array
```

每幀在 `_update_interaction_points()` 中做大量 `append`、`remove_at`、遍歷。

**改法 — 改成固定大小 Ring Buffer**（效能更穩定）:
```gdscript
# 固定長度 ring buffer，避免動態 resize
var _interaction_ring: Array = []
var _interaction_write_idx: int = 0

func _ready():
    # 預分配
    _interaction_ring.resize(MAX_INTERACTIONS)
    for i in range(MAX_INTERACTIONS):
        _interaction_ring[i] = {"uv": Vector2.ZERO, "strength": 0.0, "radius": 0.0, "active": false}

func _add_interaction(uv: Vector2, strength: float, radius: float):
    _interaction_ring[_interaction_write_idx] = {
        "uv": uv, "strength": strength, "radius": radius, "active": true
    }
    _interaction_write_idx = (_interaction_write_idx + 1) % MAX_INTERACTIONS
```

---

## 🟡 優化 5：Visual Shader Smoothing → 即時調參不跳變

**對應 4.7 PR**: [GH-116624](https://github.com/godotengine/godot/pull/116624) — Visual Shader 屬性值平滑過渡

**你的現況**: 你有大量 `@export` 參數即時更新 shader：
```gdscript
@export var wave_height_multiplier: float = 1.0:
    set(v):
        wave_height_multiplier = v
        _update_shader_params_deferred()  # 立即生效，可能跳變
```

**4.7 的行為**: 當你在編輯器調整這些值時，Visual Shader 節點內部會自動做值的平滑過渡，
避免在調參時出現視覺跳變。這對你的 `color_deep`、`sss_strength`、`foam_crest_strength` 等參數特別有幫助。

**行動**: 無需修改代碼。升級後在編輯器調參時自動受益。

---

## 🟡 優化 6：`OceanLODManager` Camera3D LOD 改善

**對應 4.7 PR**: [GH-113552](https://github.com/godotengine/godot/pull/113552) — Camera3D Preview 改版

**你的現況** (`OceanLODManager.gd` L62-L74):
```gdscript
func _update_cascade_positions():
    var cam = get_viewport().get_camera_3d()
    if not cam: return
    # ... snap 邏輯 ...
```

**需要注意**: 4.7 改版了 Camera3D 的 Preview 邏輯。你的 `_update_cascade_positions()` 在 `@tool` 模式下
也會執行（L22 強制 `or true`），這可能和 4.7 新的 editor camera preview 產生意外互動。

**建議修改**:
```gdscript
func _process(_delta):
    # ✅ 明確分開編輯器和遊戲執行時的邏輯
    if Engine.is_editor_hint():
        # 編輯器預覽：使用 editor camera，但限制更新頻率
        if Engine.get_frames_drawn() % 10 == 0:  # 每 10 幀更新一次，省 editor CPU
            _update_cascade_positions()
    else:
        _update_cascade_positions()
```

---

## 🟡 優化 7：`_init_default_normals()` 的重複代碼 + 雙重初始化 Bug

**這不是 4.7 的改動，但值得注意的既有 Bug**

**你的現況** (`WaterManager.gd` L1146-L1194):
```gdscript
func _init_default_normals():
    if not normal_map1:
        # 建立 normal_map1 ... （約 10 行）
    if not normal_map2:
        # 建立 normal_map2 ... （約 10 行）
    
    # ⚠️ 完全重複的代碼！下方又來一次
    if not normal_map1:
        # 同樣的 10 行
    if not normal_map2:
        # 同樣的 10 行
```

而且 `_ready()` 中也呼叫了兩次：
```gdscript
_init_default_normals()     # L659
_generate_envelope_texture()
_init_default_normals()     # L663 ← 重複了
_generate_envelope_texture() # L664 ← 重複了
```

**4.7 的 GDScript 靜態方法** 可以讓工廠函數更清晰：
```gdscript
# 修復：移除重複代碼，用靜態工廠簡化
static func _make_normal_noise(seed_val: int, freq: float) -> NoiseTexture2D:
    var noise = FastNoiseLite.new()
    noise.seed = seed_val
    noise.frequency = freq
    var tex = NoiseTexture2D.new()
    tex.width = 512
    tex.height = 512
    tex.seamless = true
    tex.as_normal_map = true
    tex.noise = noise
    return tex

func _init_default_normals():
    if not normal_map1:
        normal_map1 = _make_normal_noise(12345, 0.05)
        print("[WaterManager] Normal Map 1 created")
    if not normal_map2:
        normal_map2 = _make_normal_noise(67890, 0.08)
        print("[WaterManager] Normal Map 2 created")
```

---

## 🟢 優化 8：`_splat_to_texture` — CPU 泡沫烘焙遷移到 GPU Compute Shader

**對應 4.7**: Vulkan raytracing plumbing（間接顯示 compute shader 路線成熟）

**你的現況** (`WaterManager.gd` L579-L599):
```gdscript
# ❌ CPU 逐像素寫入 — 這是你最大的 CPU 效能瓶頸
func _splat_to_texture(img: Image, uv: Vector2, intensity: float, radius: float):
    for y in range(...):
        for x in range(...):
            var col = img.get_pixel(x, y)  # CPU ↔ RAM 頻繁存取
            col.a = min(col.a + intensity * falloff * 0.5, 1.0)
            img.set_pixel(x, y, col)
```

你已有整套 GPU Compute Shader 管線（SWE、FFT 等），泡沫烘焙理應也放 GPU。

**遷移路線** (使用你現有的 `rd` RenderingDevice):
```gdscript
# 新建 foam_splat.glsl compute shader
# layout(local_size_x = 8, local_size_y = 8) in;
# uniform image2D foam_texture;
# struct SplatData { vec2 uv; float intensity; float radius; };
# layout(set = 0, binding = 1) buffer SplatBuffer { SplatData splats[]; };

# GDScript 端：
func _gpu_splat_foam_particles():
    if foam_particles.is_empty(): return
    
    # 打包 particle 數據到 buffer
    var buf = PackedFloat32Array()
    for p in foam_particles:
        var uv = _world_to_uv(Vector2(p.position.x, p.position.z))
        var intensity = 1.0 - (p.age / p.lifetime)
        buf.append(uv.x); buf.append(uv.y)
        buf.append(intensity * p.scale); buf.append(2.0)  # radius
    
    # 一次 GPU dispatch 搞定所有粒子
    rd.buffer_update(foam_splat_buffer, 0, buf.to_byte_array())
    # dispatch compute ...
```

---

## 📋 執行優先順序（以你的系統瓶頸排序）

| 優先 | 項目 | 當前痛點 | 4.7 關聯 | 工時 |
|------|------|---------|----------|------|
| 🔴 1 | `_find_water_mesh` 快取 | 每幀遞歸掃描 | `find_children()` 改善 | 15 分鐘 |
| 🔴 2 | `_bake_obstacles` 分幀 | 啟動時嚴重卡幀 | 物理穩定修復 | 30 分鐘 |
| 🔴 3 | `_init_default_normals` 重複代碼 | 直接 Bug | GDScript 靜態方法 | 10 分鐘 |
| 🟡 4 | `interaction_points` Ring Buffer | 動態 array resize | Move semantics | 20 分鐘 |
| 🟡 5 | `OceanLODManager` editor mode 修正 | 4.7 相機改版 | Camera3D 改版 | 10 分鐘 |
| 🟡 6 | Bent Normal Map 啟用 | 水體光影更真實 | GH-114336 | 30 分鐘 |
| 🟢 7 | `_splat_to_texture` GPU 化 | CPU 最大瓶頸 | Compute 路線成熟 | 2-3 小時 |

---

## 🎯 對你水體系統影響最大的 4.7 改動

| 4.7 改動 | 你的直接受益 |
|---------|------------|
| Bent Normal Map (Compatibility) | 水面 SSS 在低端設備更真實 |
| Visual Shader 值平滑 | 編輯器調波浪參數不跳變 |
| `find_children()` 搜索改善 | `_find_water_mesh` 搜索更快 |
| Camera3D Preview 改版 | LOD Manager 在 editor 中顯示更正確 |
| Physics interpolation 修復 | 浮力在渲染幀之間更流暢 |

> [!TIP]
> **最高 ROI 的改動**: 優先 #1（水面網格快取）+ #2（障礙物烘焙分幀）。
> 這兩個改動跟 4.7 版本無關但能立即改善效能，升級前後都適用。
