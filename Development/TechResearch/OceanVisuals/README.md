# 海洋視覺系統設置指南 (Ocean Visuals Setup Guide)

此資料夾包含 FFT 海洋系統的 **GPU 端實作 (Visuals)**。

## 檔案說明
- **Shaders/fft_ocean.glsl**: 負責計算波浪數據的 Compute Shader (目前包含基礎 Sine 波測試邏輯)。
- **Shaders/water_lowpoly.gdshader**: 負責渲染 Low Poly 海洋並實現動態平坦著色 (Dynamic Flat Shading) 的表面 Shader。
- **GpuOcean.gd**: 用於驅動 Compute Shader 並更新紋理的 GDScript 控制腳本。

## 測試步驟 (How to Test)
1.  在 Godot 中建立一個新場景。
2.  新增一個 `MeshInstance3D` 並賦予 `PlaneMesh`。
    *   將 `PlaneMesh` 的細分 (Subdivision) 設為較高的數值 (例如 200x200)，以支援頂點位移。
3.  新增一個 `Node3D` 作為子節點 (或兄弟節點)，並將 `GpuOcean.gd` 腳本掛載上去。
4.  在 `GpuOcean.gd` 的屬性面板 (Inspector) 中：
    *   **Compute Shader**: 載入 `Shaders/fft_ocean.glsl`。
    *   **Material To Update**: 指派您的 MeshInstance3D 所使用的材質。
5.  在 `MeshInstance3D` 的材質設定中：
    *   建立一個 `ShaderMaterial`。
    *   載入 `Shaders/water_lowpoly.gdshader`。
6.  執行場景。

## 下一步 (Next Steps)
C++ 端的 `GdOcean` (Physics) 已實作完成。接下來的關鍵步驟是：
1.  **實作完整 GPU FFT**: 將 `gd_ocean.cpp` 中的 C++ FFT 邏輯移植到 `fft_ocean.glsl`。
2.  **數據同步**: 透過 `WaterManager` 或全域變數，確保 GPU 的 `time` 和 FFT 參數 (風速、頻譜) 與 CPU 端完全一致，以達到視覺與物理的完美同步。
