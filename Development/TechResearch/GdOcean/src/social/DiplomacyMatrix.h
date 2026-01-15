#pragma once
#include "../core/Utils.h"
#include <unordered_map>

namespace NPCSystem {
namespace Social {

class DiplomacyMatrix {
private:
  std::unordered_map<int, std::unordered_map<int, float>> relations;

public:
  float get_standing(int faction_a, int faction_b);
};

} // namespace Social
} // namespace NPCSystem
