#pragma once

#include "../core/Utils.h"
#include <optional>

namespace NPCSystem {

// SEC Profile for Geopolitics Integration
struct SECProfile {
  float truth_awareness = 0.0f;
  float suffering_coefficient = 0.0f;
  float wall_distrust_index = 0.0f;
  float obedience = 0.8f;
  float fear_threshold = 10.0f;
};

enum class FactionId {
  None,
  Syndicate, // 鋼鐵兄弟會
  Covenant,  // 漂流木公約
  Tidebound  // 深淵 (Tidebound)
};

struct FactionComponent {
  FactionId id;
  int rank; // 0-100
  SECProfile sec_profile;

  FactionComponent(FactionId i = FactionId::None, int r = 0) : id(i), rank(r) {}
};

enum class Alignment { Wild, Enemy, Npc, Tame, Owned, Passive };

struct AlignmentData {
  Alignment type;
  std::optional<Uid> owner;

  AlignmentData(Alignment t, std::optional<Uid> o = std::nullopt)
      : type(t), owner(o) {}

  bool hostile_towards(const AlignmentData &other) const;
  bool passive_towards(const AlignmentData &other) const;
  bool friendly_towards(const AlignmentData &other) const;
};

} // namespace NPCSystem
