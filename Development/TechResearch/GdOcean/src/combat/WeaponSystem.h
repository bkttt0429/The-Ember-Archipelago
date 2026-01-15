#pragma once
#include "../core/Utils.h"

namespace NPCSystem {
namespace Combat {

class WeaponSystem {
public:
  void update(float dt);
  void fire(Uid target_id);
};

class BallisticsSolver {
public:
  Vec3 predict_impact(Vec3 start, Vec3 velocity, Vec3 target_pos,
                      float target_speed);
};

} // namespace Combat
} // namespace NPCSystem
