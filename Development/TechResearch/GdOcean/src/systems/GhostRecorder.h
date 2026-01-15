#pragma once

#include "../core/Utils.h"
#include <unordered_map>
#include <vector>


namespace NPCSystem {

struct GhostFrame {
  Vec3 pos;
  double timestamp;
};

class GhostRecorder {
private:
  std::unordered_map<EntityId, std::vector<GhostFrame>> records;
  static constexpr size_t MAX_SAMPLES = 100;

public:
  void record(EntityId id, Vec3 pos, double time);
  const std::vector<GhostFrame> *get_ghost(EntityId id) const;
  void clear(EntityId id);
};

} // namespace NPCSystem
