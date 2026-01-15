#include "WorldEventBus.h"
#include <cmath>

namespace NPCSystem {

std::string SpatialHash::key(const Vec3 &pos) const {
  int x = static_cast<int>(std::floor(pos.x / cell_size));
  int z = static_cast<int>(std::floor(pos.z / cell_size));
  return std::to_string(x) + "," + std::to_string(z);
}

void SpatialHash::insert(const Vec3 &pos, int index) {
  grid[key(pos)].push_back(index);
}

void SpatialHash::clear() { grid.clear(); }

std::vector<int> SpatialHash::query(const Vec3 &pos) const {
  int x = static_cast<int>(std::floor(pos.x / cell_size));
  int z = static_cast<int>(std::floor(pos.z / cell_size));
  std::vector<int> result;

  for (int i = -1; i <= 1; ++i) {
    for (int j = -1; j <= 1; ++j) {
      std::string k = std::to_string(x + i) + "," + std::to_string(z + j);
      auto it = grid.find(k);
      if (it != grid.end()) {
        result.insert(result.end(), it->second.begin(), it->second.end());
      }
    }
  }
  return result;
}

void WorldEventBus::publish(const WorldEvent &e) {
  events.push_back(e);
  spatial_index.insert(e.position, events.size() - 1);
}

std::vector<WorldEvent> WorldEventBus::query_nearby(Vec3 pos,
                                                    float range) const {
  std::vector<WorldEvent> result;
  std::vector<int> indices = spatial_index.query(pos);

  for (int idx : indices) {
    const auto &e = events[idx];
    if (e.position.distance(pos) <= range) {
      result.push_back(e);
    }
  }
  return result;
}

void WorldEventBus::clear_old() {
  events.clear();
  spatial_index.clear();
}

} // namespace NPCSystem
