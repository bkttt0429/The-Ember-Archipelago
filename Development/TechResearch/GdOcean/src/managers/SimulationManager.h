#pragma once

#include "../agents/Agent.h"
#include "../systems/GhostRecorder.h"
#include "../systems/JobBlackboard.h"
#include "../systems/WorldEventBus.h"
#include <godot_cpp/classes/node.hpp>
#include <memory>
#include <vector>


namespace godot {

class SimulationManager : public Node {
  GDCLASS(SimulationManager, Node)

private:
  NPCSystem::WorldEventBus event_bus;
  NPCSystem::JobBlackboard job_blackboard;
  NPCSystem::GhostRecorder ghost_recorder;
  std::vector<std::unique_ptr<NPCSystem::Agent>> agents;

protected:
  static void _bind_methods();

public:
  SimulationManager();
  ~SimulationManager();

  void _process(double delta) override;

  void add_agent(int faction_id, godot::Vector3 pos);
  void publish_event(int event_type, godot::Vector3 pos, float radius);

  godot::TypedArray<godot::Dictionary> get_agent_states() const;
};

} // namespace godot
