#include "Agent.h"

namespace NPCSystem {

void Awareness::update(float dt) {
  if (level > 0.8f)
    state = State::Alert;
  else if (level > 0.3f)
    state = State::Suspicious;
  else
    state = State::Unaware;

  level = std::max(0.0f, level - 0.05f * dt); // Decay
}

void Agent::update(float dt, WorldEventBus &bus, JobBlackboard &blackboard) {
  awareness.update(dt);
  decide_next_action(bus, blackboard);
  execute_action(dt);
}

void Agent::decide_next_action(WorldEventBus &bus, JobBlackboard &blackboard) {
  // 派系特定邏輯 (原本在 NPCAISYSTEM.cpp 1350 左右)
  if (faction.id == FactionId::Syndicate) {
    if (needs.coal < 20.0f) {
      current_action = Action::Trade;
      return;
    }

    auto events = bus.query_nearby(position, psyche.sight_distance);
    for (const auto &e : events) {
      if (e.type == WorldEventType::StructuralFailure &&
          e.source_faction == FactionId::Syndicate) {
        current_action = Action::Scavenge; // Help ally
        return;
      }
    }
  } else if (faction.id == FactionId::Covenant) {
    auto events = bus.query_nearby(position, psyche.sight_distance);
    for (const auto &e : events) {
      if (e.type == WorldEventType::HarpoonEvent) {
        awareness.level += 0.5f;
        current_action = Action::Attack; // Swarm tactic
        return;
      }
    }
  } else if (faction.id == FactionId::Tidebound) {
    if (awareness.state == Awareness::State::Alert) {
      current_action = Action::Dive;
      return;
    }
  }
}

void Agent::execute_action(float dt) {
  // 執行邏輯 (導航、旋轉等)
}

} // namespace NPCSystem
