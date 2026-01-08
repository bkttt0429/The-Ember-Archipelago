# 海洋系統開發進度追蹤 (Ocean System Progress Tracker)

此文件用於追蹤「雙重模擬海洋系統」的開發進度，包含已完成項目與待辦事項。

## 1. 基礎核心架構 (Core Infrastructure) [已完成]

- [x] **C++ GDExtension 環境建置**
    - [x] 設定 SCons 建置系統
    - [x] 配置 VS Code 除錯環境 (`launch.json`)
    - [x] 解決 DLL 鎖定與熱重載問題 (`rebuild_all.bat`)
- [x] **GDScript 渲染架構 (RenderDevice)**
    - [x] 建立 `GpuOcean.gd` 管理 RenderingDevice
    - [x] 設置 Compute Pipeline 與 Uniform Sets
    - [x] 實作 Ping-Pong Texture 機制 (用於多 Pass FFT)

## 2. 全局海浪模擬 (Global FFT Ocean) [已完成]

- [x] **物理層模擬 (CPU/C++)**
    - [x] 實作 `OceanWaveGenerator` 類別
    - [x] 實作 Cooley-Tukey FFT 算法 (CPU版)
    - [x] 實作色散關係 (Dispersion Relation) $\omega^2 = gk$
    - [x] 實作 `get_wave_height(x, z)` 雙線性插值查詢 API
    - [x] 修復 `_process` 循環未執行問題
- [x] **視覺層模擬 (GPU/Shader)**
    - [x] 實作 `fft_ocean.glsl` Compute Shader
    - [x] 移植 FFT 算法至 GLSL (Shared Memory 優化)
    - [x] 實作 `water_lowpoly.gdshader` 接收 Height Map
- [x] **雙重同步驗證 (Sync Verification)**
    - [x] 確保 CPU 與 GPU 使用相同的初始頻譜 (Test Spectrum)
    - [x] 建立 `OceanTest.gd` 測試場景
    - [x] 驗證：物理浮球 (紅色) 與視覺海面 (藍色) 同步起伏

## 3. 局部物理互動 (Local Interaction - SWE/NS) [待辦 - Next Step]

目標：實作船隻航行時的尾流、推開水面、以及漩渦效果。參考 `Unity-SWE` 與 `FluidNinja`。

- [x] **局部模擬網格 (Local Simulation Grid)**
    - [x] 建立跟隨玩家(船隻)移動的局部 Simulation Texture
    - [x] 實作 Pixel Snapping (防止移動時的數據抖動)
- [x] **淺水方程求解器 (SWE Solver)**
    - [x] 實作 Advection (平流) Pass
    - [x] 實作 Pressure/Divergence 解算
    - [x] 實作 Height-Velocity 耦合
- [x] **物體互動 (Object Interaction)**
    - [x] 將船隻的形狀/速度 寫入 "Obstacle/Force Texture" (Implemented via Buffer)
    - [x] 在 Shader 中讀取 Force Texture 並注入動量

## 4. 融合與優化 (Hybrid & Polish) [待辦]

- [ ] **混合系統 (Blending)**
    - [x] 將 Global FFT 高度 與 Local SWE 高度在 Vertex Shader 中疊加
    - [x] 處理邊界過渡 (隨距離衰減 Local 影響)
- [ ] **視覺效果增強**
    - [x] 白沫 (Foam) 生成邏輯 (基於 速度散度 與 互動)
    - [x] 次表面散射 (SSS) 與各向異性高光 (Anisotropic Specular)
- [ ] **效能優化 (LOD & Optimization)** [In Progress]
    - [ ] LOD (Level of Detail) 網格系統 (QuadTree 或 Clipmap)
    - [ ] Culling (視錐剔除)

## 5. 專案整合 (Game Integration) [待辦]

- [ ] **Geopolitics 系統整合**
    - [ ] 讓貿易船隻使用此海洋物理移動
    - [ ] 根據海況影響船隻速度 (逆風/順風)
