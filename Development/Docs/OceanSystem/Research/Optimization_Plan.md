# 🌊 雙重模擬海洋系統：效能與視覺優化計畫書 (2026)

| 項目 | 描述 |
| --- | --- |
| **目標** | 透過 Data-less Mesh 與 Nested Clipmaps 實現萬倍面積海洋渲染 |
| **當前架構** | C++/GDExtension (FFT) + Godot RenderingDevice (SWE) |
| **視覺風格** | 高級感 Low-Poly (低多邊形) |

---

## 一、 頂點層級：無數據化網格 (Data-less Mesh)

這是提升 FPS 最直觀的方法，核心思想是將記憶體壓力轉移到 GPU 計算。

### 1. 移除傳統頂點緩衝區

* **優化方案**：不再傳遞 `POSITION`、`NORMAL`、`UV`。
* **實現方式**：在 Godot Shader 中利用 `VERTEX_ID` 程序化生成平面網格座標。
* **數學公式**：
  ```glsl
  float x = mod(float(VERTEX_ID), grid_size);
  float z = floor(float(VERTEX_ID) / grid_size);
  vec3 pos = vec3(x, 0.0, z) * spacing;
  ```

* **視覺紅利 (Flat Shading)**：
由於您是 Low-poly 風格，不需要壓縮法線，直接在 Fragment Shader 利用 `dFdx` 和 `dFdy` 計算面法線，徹底省去法線傳輸開銷。

### 2. 局部像素對齊 (Pixel Snapping)

* 為了維持 Low-poly 的「像素感」，頂點位移後需進行量化處理：
  ```glsl
  world_pos.xz = floor(world_pos.xz / snap_size) * snap_size;
  ```

---

## 二、 空間層級：幾何夾片 (Nested Clipmaps)

解決影片中提到的「遠處山脈不需要百萬三角形」的問題，針對海洋實作動態縮放。

### 1. 同心圓網格架構

* **配置**：實作 4-5 層嵌套網格（LOD Layers），每層網格數量固定（如 128x128），但縮放倍率以 2 的冪次方遞增。
* **渲染策略**：
    * **Level 0 (玩家周圍)**：開啟 FFT + SWE 混合，採樣最高頻率的高度圖。
    * **Level 1-4 (遠景)**：關閉 SWE，僅採樣 FFT 低頻組分，並大幅降低著色頻率。

### 2. 解決邊界裂縫 (Seams)

* **裙邊 (Skirts)**：在每層網格邊緣自動向下延伸 0.5 單位，防止因頂點不對齊露出的背景。
* **幾何變形 (Geomorphing)**：在 Shader 中計算頂點到相機的距離權重 $w$，平滑地將邊緣頂點插值到上一層 LOD 的位置。

---

## 三、 模擬混合層：FFT 與 SWE 耦合

將全局物理與局部互動優雅地結合。

### 1. 混合高度緩衝區 (Height Blending)

* 使用 `smoothstep` 建立局部網格遮罩。
* **混合公式**：
  ```glsl
  float blend = smoothstep(swe_radius, swe_radius * 0.8, dist_to_center);
  float final_h = fft_h + swe_h * blend;
  ```

### 2. 互動批次處理 (Batching)

* 當場景有多個互動體（如多艘船隻）時，使用 **SSBO (Structured Buffer)** 存儲每艘船的 `Transform` 和 `Force`。
* **GPU 剔除**：在 Compute Shader 中預先判斷哪些 SWE 區域位於視錐內，僅更新可見區域的模擬。

---

## 四、 渲染層級：高級感 Low-poly 著色

針對優化後的數據結構，加入光學細節。

### 1. 物理透明度 (Beer's Law)

* 不要使用固定的 Alpha 值。
* **實作**：根據深度緩衝區計算光線路徑，呈現「近岸淺綠、深海暗藍」的過渡。

### 2. 螢幕空間折射 (SSR)

* 利用 Godot 的 `SCREEN_TEXTURE` 配合法線偏移實現。
* **像素風格優化**：折射偏移量需進行像素化處理，防止與 Low-poly 模型產生視覺衝突。

---

## 五、 風險控管與開發優先序

### 🚨 核心風險

1. **浮點精度**：遠海渲染會產生「抖動」，必須使用 **Camera-Relative Coordinates**。
2. **同步延遲**：FFT 計算在 CPU，渲染在 GPU。若延遲過大，物理浮球會陷進水裡。
3. **效能轉移**：過多的 Shader 數學運算（`mod`, `floor`）可能在舊手機/顯卡上造成負擔。

### 📅 實施路徑 (Roadmap)

* **Phase 1 (當前)**：移除網格數據，改用 `VERTEX_ID` 渲染，實作 Flat Shading。
* **Phase 2**：實作 3 層固定級距的 LOD 網格，測試幾何裂縫處理。
* **Phase 3**：引入 SWE 局部遮罩混合與距離衰減。
* **Phase 4**：加入 SSA 與比爾定律顏色過渡。
