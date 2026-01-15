# 天氣系統開發進度 (Progress Status)

## 📅 最後更新日期：2026-01-15

## ✅ 已完成事項 (Completed)
- [x] **目錄結構建立**：已初始化 `WeatherSystem/Core`, `VFX`, `Resources`, `Scenes` 等職責分明的文件夾。
- [x] **故障修復**：解決了因腳本移動導致的 `Invalid UID` 警告，並修復了 `GlobalWind.gd` 的 Autoload 加載失敗問題。
- [x] **核心控制器實作**：`WeatherController.gd` 已具備基礎框架，支持資源加載與屬性更新。
- [x] **晝夜系統 (Day/Night)**：
    - 實作了 24 小時太陽旋轉邏輯。
    - 實作了動態光照強度與色彩偏移（日出/日落暖色調）。
    - 解決了夜晚環境光過亮的問題，實現了真正的黑夜效果。
- [x] **風力聯動**：`GlobalWind` 單例已與 `OceanWaterManager` 完成對接，當前風速可實時影響海浪表現。
- [x] **平滑過渡 (States Tweening)**：實作了 `Tween` 邏輯，天氣切換時數值（風力、霧效、雨強度、天空色）平滑過渡。
- [x] **雨水系統 (Rain VFX)**：細化了 `RainController.gd`，支持粒子量比例縮放與 Shader 參數聯動。
- [x] **閃電系統 (Lightning)**：整合了隨機觸發的閃電光照（OmniLight3D）與視覺閃爍效果，僅在風暴模式下觸發。
- [x] **龍捲風 (Tornado)**：實作了 `TornadoController.gd`，成功整合 `Vortex.glsl` 計算著色器與雲朵看板粒子系統。
- [x] **測試場景與 UI**：
    - 建立了 `WeatherTest.tscn` 整合測試場景。
    - 實作了 UI 面板，包含天氣切換按鈕以及時間控制滑塊（Slider）。

## 🚧 進行中/待辦事項 (In Progress / TODO)
- [ ] **天氣音效系統**：需實作雨聲、雷聲與風聲的 3D 空間音效與動態混音。
- [ ] **天空盒細化**：目前使用程序化天空，未來可替換為更高品質的 HDRI 或天空資源，並實作雲層密度控制。
- [ ] **氣候區域 (Weather Zones)**：實作基於區域（Area3D）的天氣自動切換邏輯。
- [ ] **海浪物理感應**：讓龍捲風中心的吸力對物理浮體產生實質性影響。

## 🐞 已解決問題
- (已解決) 資源文件 (.tres) 屬性命名與腳本不匹配導致的載入失敗。
- (已解決) WeatherController 缺少平滑過渡邏輯。
- (已解決) 閃電與龍捲風 VFX 未能自動跟隨天氣狀態變化的問題。
