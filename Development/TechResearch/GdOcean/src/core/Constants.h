#pragma once

namespace NPCSystem {

// 全域常數與配置
static constexpr float DEFAULT_INTERACTION_TIME = 3.0f;
static constexpr float TRADE_INTERACTION_TIME = 300.0f;
static constexpr double SECONDS_BEFORE_FORGET_SOUNDS = 180.0;

// PID 控制器預設參數
static constexpr float DEFAULT_PID_KP = 1.0f;
static constexpr float DEFAULT_PID_KI = 0.1f;
static constexpr float DEFAULT_PID_KD = 0.8f;

// 空間分區配置
static constexpr float SPATIAL_CELL_SIZE = 100.0f;

} // namespace NPCSystem
