#include "GhostRecorder.h"

namespace NPCSystem {

void GhostRecorder::record(EntityId id, Vec3 pos, double time) {
  auto &frames = records[id];
  frames.push_back({pos, time});
  if (frames.size() > MAX_SAMPLES) {
    frames.erase(frames.begin());
  }
}

const std::vector<GhostFrame> *GhostRecorder::get_ghost(EntityId id) const {
  auto it = records.find(id);
  if (it != records.end())
    return &it->second;
  return nullptr;
}

void GhostRecorder::clear(EntityId id) { records.erase(id); }

} // namespace NPCSystem
