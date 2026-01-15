#pragma once

#include "../components/FactionComponent.h"
#include "../core/Utils.h"
#include <string>
#include <unordered_map>
#include <vector>


namespace NPCSystem {

enum class WorldEventType {
  StructuralFailure,
  DistressSignal,
  ResourceEvent,
  FloodingAlarm,
  HarpoonEvent,
  DiplomacyChange,
  ResourceScarce
};

struct WorldEvent {
  WorldEventType type;
  Vec3 position;
  float radius;
  EntityId source_id;
  FactionId source_faction;
  float intensity;
  std::string metadata;

  WorldEvent(WorldEventType t, Vec3 pos, float r, EntityId src,
             FactionId fac = FactionId::None)
      : type(t), position(pos), radius(r), source_id(src), source_faction(fac),
        intensity(r) {}
};

class SpatialHash {
private:
  float cell_size;
  std::unordered_map<std::string, std::vector<int>> grid;
  std::string key(const Vec3 &pos) const;

public:
  SpatialHash(float size = 100.0f) : cell_size(size) {}
  void insert(const Vec3 &pos, int index);
  void clear();
  std::vector<int> query(const Vec3 &pos) const;
};

class WorldEventBus {
private:
  std::vector<WorldEvent> events;
  SpatialHash spatial_index;

public:
  WorldEventBus() : spatial_index(100.0f) {}
  void publish(const WorldEvent &e);
  std::vector<WorldEvent> query_nearby(Vec3 pos, float range) const;
  void clear_old();
};

} // namespace NPCSystem
