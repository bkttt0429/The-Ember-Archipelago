# 完整懸掛攀爬系統規劃

## 業界研究總結

### 邊緣偵測方法
| 方法 | 引擎 | 優點 | 缺點 |
|------|------|------|------|
| **雙射線法** | Godot/Unity | 簡單、精確 | 需要調參 |
| 觸發器法 | Unity | 自動觸發 | 需改環境 |
| 線追蹤掃描 | Unreal | 精確對齊 | 複雜 |

**推薦：雙射線法**
- 下方射線擊中牆 + 上方射線未擊中 = 有邊緣

### 狀態機設計
```
Falling → LedgeGrab → Hanging → ClimbUp → Locomotion
                  ↘ Drop → Falling
```

---

## Godot 4 實現架構

### 節點結構
```
Player/
├── LedgeDetector/ (Node3D)
│   ├── WallRay (RayCast3D) - 胸部，向前 0.5m
│   ├── TopRay (RayCast3D) - 頭頂，向前 0.5m
│   └── ClearanceRay - 確認頂部空間
```

### 偵測邏輯
```gdscript
func _detect_ledge() -> Dictionary:
    if wall_ray.is_colliding() and not top_ray.is_colliding():
        # 有邊緣！計算精確位置
        return {
            "valid": true,
            "position": _calculate_grab_point(),
            "normal": wall_ray.get_collision_normal()
        }
    return {"valid": false}
```

---

## 開發階段

### Phase 1: 基礎偵測 ✅ 可開始
- [ ] 建立 LedgeDetector 節點
- [ ] 雙射線偵測邏輯
- [ ] Debug 視覺化

### Phase 2: 快速攀爬 ✅ 可開始
- [ ] 偵測 + 按跳 → ClimbUp 動畫
- [ ] 傳送到頂部
- [ ] 跳過懸掛（暫無動畫）

### Phase 3: 完整懸掛 ⏳ 需動畫
- [ ] Hang_Idle 迴圈動畫
- [ ] 左右 Shimmy
- [ ] 放手下落

---

## 現有動畫
| 動畫 | 狀態 |
|------|------|
| ClimbUp_1m_RM | ✅ 已有 |
| Hang_Idle | ❌ 需取得 |
| Shimmy | ❌ 需取得 |
