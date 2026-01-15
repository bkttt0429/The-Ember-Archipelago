#ifndef NPC_AI_CONTROLLER_H
#define NPC_AI_CONTROLLER_H

#include "NPCSystem.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>


namespace gd_ocean {

class NPCAIController : public godot::Node {
  GDCLASS(NPCAIController, godot::Node)

private:
  NPCSystem::Simulation simulation;

protected:
  static void _bind_methods();

public:
  NPCAIController();
  ~NPCAIController();

  void _process(double delta) override;

  // Agent Management
  // faction_id maps to NPCSystem::FactionId enum
  void add_agent(const godot::String &name, int faction_id, int rank);

  // SEC Profile Access
  void set_agent_sec_profile(const godot::String &name,
                             const godot::Dictionary &sec_data);
  godot::Dictionary get_agent_sec_profile(const godot::String &name);

  // Helpers
  void print_simulation_status();
};

} // namespace gd_ocean

#endif // NPC_AI_CONTROLLER_H
