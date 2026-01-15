#include "SimulationManager.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

void SimulationManager::_bind_methods() {
  ClassDB::bind_method(D_METHOD("add_agent", "faction_id", "pos"),
                       &SimulationManager::add_agent);
  ClassDB::bind_method(D_METHOD("publish_event", "type", "pos", "radius"),
                       &SimulationManager::publish_event);
  ClassDB::bind_method(D_METHOD("get_agent_states"),
                       &SimulationManager::get_agent_states);
}

SimulationManager::SimulationManager() {}
SimulationManager::~SimulationManager() {}

void SimulationManager::_process(double delta) {
  if (Engine::get_singleton()->is_editor_hint())
    return;

  for (auto &agent : agents) {
    agent->update(static_cast<float>(delta), event_bus, job_blackboard);
    ghost_recorder.record(agent->id, agent->position,
                          Time::get_singleton()->get_unix_time_from_system());
  }
}

void SimulationManager::add_agent(int faction_id, godot::Vector3 pos) {
  auto agent = std::make_unique<NPCSystem::Agent>(
      agents.size(), static_cast<NPCSystem::FactionId>(faction_id));
  agent->position = NPCSystem::Vec3(pos.x, pos.y, pos.z);
  agents.push_back(std::move(agent));
}

void SimulationManager::publish_event(int event_type, godot::Vector3 pos,
                                      float radius) {
  NPCSystem::WorldEvent e(static_cast<NPCSystem::WorldEventType>(event_type),
                          NPCSystem::Vec3(pos.x, pos.y, pos.z), radius,
                          0 // System source
  );
  event_bus.publish(e);
}

godot::TypedArray<godot::Dictionary>
SimulationManager::get_agent_states() const {
  godot::TypedArray<godot::Dictionary> result;
  for (const auto &agent : agents) {
    godot::Dictionary d;
    d["id"] = agent->id;
    d["pos"] =
        godot::Vector3(agent->position.x, agent->position.y, agent->position.z);
    d["action"] = static_cast<int>(agent->current_action);
    result.append(d);
  }
  return result;
}

} // namespace godot
