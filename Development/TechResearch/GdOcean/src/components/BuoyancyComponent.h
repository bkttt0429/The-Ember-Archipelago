#pragma once

#include <algorithm>

namespace NPCSystem {

enum class BuoyancyState { Floating, Sinking, Submerged };

struct BuoyancyComponent {
  float current_buoyancy; // 0.0 - 100.0
  float max_buoyancy;
  bool health_linked;

  BuoyancyComponent(float max_b = 100.0f)
      : current_buoyancy(max_b), max_buoyancy(max_b), health_linked(true) {}

  BuoyancyState check_state(float health_pct) {
    if (health_linked && health_pct < 0.2f) { // If health low, buoyancy drops
      current_buoyancy = std::min(current_buoyancy, max_buoyancy * 0.2f);
    }

    if (current_buoyancy <= 0)
      return BuoyancyState::Submerged;
    if (current_buoyancy < max_buoyancy * 0.2f)
      return BuoyancyState::Sinking; // Low buoyancy threshold
    return BuoyancyState::Floating;
  }
};

} // namespace NPCSystem
