# NaN 错误修复说明

## 🐛 问题描述

错误信息：
```
set_axis_angle: The axis Vector3 (nan, nan, nan) must be normalized.
```

**原因：** Shader 中的法线计算在某些情况下产生了 NaN（Not a Number），导致后续的物理计算失败。

---

## ✅ 修复内容

### 1. `gerstner_wave_normal()` 函数安全检查

**添加的检查：**
- ✅ 波长有效性检查（避免除以零）
- ✅ 波方向向量有效性检查（避免归一化零向量）
- ✅ NaN/Inf 检测和过滤

```glsl
// 安全检查：避免除以零或无效波长
if (wavelength < 0.001) {
    return vec3(0.0);
}

// 安全检查：避免归一化零向量
vec2 wave_dir = wave_params.xy;
float dir_len_sq = dot(wave_dir, wave_dir);
if (dir_len_sq < 0.000001) {
    return vec3(0.0);
}

// 安全检查：防止 NaN 或 Inf
if (any(isnan(normal_contrib)) || any(isinf(normal_contrib))) {
    return vec3(0.0);
}
```

---

### 2. `get_normal_analytical()` 函数安全检查

**添加的检查：**
- ✅ Waterspout 距离检查（避免除以零）
- ✅ 法线长度检查（避免归一化零向量）
- ✅ NaN/Inf 检测和回退

```glsl
// 安全检查：避免除以零（当距离太小时）
if (dist_to_spout < waterspout_radius * 2.0 && waterspout_strength > 0.01 && dist_to_spout > 0.001) {
    vec2 to_spout_dir = p.xz - waterspout_pos.xz;
    float dist_sq = dot(to_spout_dir, to_spout_dir);
    if (dist_sq > 0.000001) { // 避免归一化零向量
        vec2 to_spout = normalize(to_spout_dir);
        // ... 计算
    }
}

// 安全检查：确保法线有效（防止 NaN）
float normal_len = length(normal_sum);
if (normal_len < 0.0001 || isnan(normal_len) || isinf(normal_len)) {
    // 如果法线无效，返回默认向上法线
    return vec3(0.0, 1.0, 0.0);
}
```

---

### 3. `vertex()` 函数最终检查

**添加的检查：**
- ✅ 最终法线有效性验证
- ✅ 回退到默认法线

```glsl
vec3 computed_normal = get_normal_analytical(v_world_pos);

// 最终安全检查：确保法线有效
if (any(isnan(computed_normal)) || any(isinf(computed_normal)) || length(computed_normal) < 0.1) {
    // 回退到默认向上法线
    computed_normal = vec3(0.0, 1.0, 0.0);
}

NORMAL = computed_normal;
```

---

## 🔍 可能导致 NaN 的情况

### 1. 无效的波浪参数
- **波长 = 0** → 除以零
- **波方向 = (0,0)** → 归一化零向量

### 2. Waterspout 位置重叠
- **物体位置 = waterspout_pos** → 距离 = 0，归一化失败

### 3. 极端参数值
- **height_scale = 0 或极大值** → 计算溢出
- **steepness = 0** → 无效计算

### 4. 纹理采样失败
- **vertex_noise_big 未初始化** → 返回无效值

---

## ✅ 修复效果

1. **防止 NaN 产生**
   - 所有可能导致 NaN 的计算都有安全检查
   - 无效值会被过滤或替换为默认值

2. **优雅降级**
   - 当计算失败时，回退到默认向上法线
   - 不会中断游戏运行

3. **性能影响**
   - 安全检查开销极小（主要是条件判断）
   - 不影响正常情况下的性能

---

## 🧪 测试建议

1. **极端参数测试**
   - 设置 `wavelength = 0`
   - 设置 `wave_a = Vector4(0, 0, 0, 0)`
   - 设置 `waterspout_pos = 物体位置`

2. **运行时测试**
   - 运行场景，观察是否还有 NaN 错误
   - 检查水面渲染是否正常
   - 验证物理计算是否正常

3. **性能测试**
   - 确认修复不影响性能
   - 检查帧率是否稳定

---

## 📝 注意事项

1. **参数验证**
   - 建议在 `WaterController` 或 `WaterManager` 中添加参数验证
   - 确保传入 shader 的参数在有效范围内

2. **调试模式**
   - 如果仍有问题，可以启用更详细的检查
   - 输出警告信息帮助定位问题

3. **默认值**
   - 确保所有 shader uniform 都有合理的默认值
   - 避免未初始化的参数

---

**修复完成时间**：2024
**状态**：✅ 已修复，添加了全面的安全检查
