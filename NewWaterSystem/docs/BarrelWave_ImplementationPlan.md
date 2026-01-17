# Barrel Wave System Implementation Plan

Based on the design in `BarrelWaveSystem_Design.md`.

## Phase 1: Core Wave Shape (核心形態)
- [x] Implement `BreakingWaveComponent.gd` in `NewWaterSystem/Core/Scripts/Waves/`
- [x] Extend `WaterManager.gd` with breaking wave interface
- [x] Modify `ocean_surface.gdshader` (Vertex Shader) to add curl logic
- [x] Test scene setup with single wave

## Phase 2: Foam System (泡沫系統)
- [x] Implement Foam Particle Physics in `WaterManager.gd`
- [x] Create `FoamParticleRenderer.gd` in `NewWaterSystem/Core/Scripts/Foam/`
- [x] Create `FoamParticle.gdshader` in `NewWaterSystem/Core/Shaders/`
- [x] Enhance Fragment Shader in `ocean_surface.gdshader` for foam
- [x] Performance tuning

## Phase 3: Interaction & Optimization (交互與優化)
- [ ] Implement `PlayerWaveInteraction.gd` in `NewWaterSystem/Core/Scripts/Interaction/`
- [ ] Implement LOD system in `WaterManager.gd`
- [ ] Implement frustum culling for waves
- [ ] Final performance verification
