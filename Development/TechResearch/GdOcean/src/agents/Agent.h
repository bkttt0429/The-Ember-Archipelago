#pragma once

#include "../components/BuoyancyComponent.h"
#include "../components/FactionComponent.h"
#include "../components/ResourceNeeds.h"
#include "../core/Utils.h"
#include "../systems/JobBlackboard.h"
#include "../systems/WorldEventBus.h"
#include <string>


namespace NPCSystem {

struct Psyche {
  float flee_health_threshold = 0.3f;
  float aggression = 0.5f;
  float sight_distance = 500.0f;
};

struct Awareness {
  float level = 0.0f; // 0.0 (Unaware) - 1.0 (Alert)
  enum class State { Unaware, Suspicious, Alert };
  State state = State::Unaware;

  void update(float dt);
};

enum class Action { Idle, Trade, Flee, Attack, Scavenge, Dive };

class Agent {
public:
  Uid id;
  Vec3 position;
  Vec3 velocity;
  float health = 100.0f;

  FactionComponent faction;
  AlignmentData alignment;
  BuoyancyComponent buoyancy;
  ResourceNeeds needs;
  Psyche psyche;
  Awareness awareness;

  Action current_action = Action::Idle;
  std::optional<Uid> current_target;

  Agent(Uid id, FactionId f = FactionId::None, Alignment a = Alignment::Npc)
      : id(id), faction(f), alignment(a) {}

  void update(float dt, WorldEventBus &bus, JobBlackboard &blackboard);
  void decide_next_action(WorldEventBus &bus, JobBlackboard &blackboard);
  void execute_action(float dt);
};

} // namespace NPCSystem
