#include "NPCAIController.h"
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace gd_ocean {

void NPCAIController::_bind_methods() {
  ClassDB::bind_method(D_METHOD("add_agent", "name", "faction_id", "rank"),
                       &NPCAIController::add_agent);
  ClassDB::bind_method(D_METHOD("set_agent_sec_profile", "name", "sec_data"),
                       &NPCAIController::set_agent_sec_profile);
  ClassDB::bind_method(D_METHOD("get_agent_sec_profile", "name"),
                       &NPCAIController::get_agent_sec_profile);
  ClassDB::bind_method(D_METHOD("print_simulation_status"),
                       &NPCAIController::print_simulation_status);
}

NPCAIController::NPCAIController() {
  // Enable processing so physics/logic updates happen
  set_process(true);
}

NPCAIController::~NPCAIController() {}

void NPCAIController::_process(double delta) {
  // Run the simulation logic
  simulation.step(delta);
}

void NPCAIController::add_agent(const String &name, int faction_id, int rank) {
  // Create a basic agent. In usage, we might want more config passed in.
  // For now, defaulting to "Humanoid" body type.
  NPCSystem::Agent agent = NPCSystem::Agent::from_body("Humanoid");

  // Set Faction
  agent.faction = NPCSystem::FactionComponent(
      static_cast<NPCSystem::FactionId>(faction_id), rank);

  std::string s_name = name.utf8().get_data();
  simulation.add_agent(s_name, agent);

  UtilityFunctions::print("[NPCAIController] Added agent: ", name,
                          " (Faction ID: ", faction_id, ", Rank: ", rank, ")");
}

void NPCAIController::set_agent_sec_profile(const String &name,
                                            const Dictionary &sec_data) {
  std::string s_name = name.utf8().get_data();
  NPCSystem::Agent *agent = simulation.get_agent(s_name);

  if (agent) {
    if (sec_data.has("truth_awareness"))
      agent->faction.sec_profile.truth_awareness =
          (float)sec_data["truth_awareness"];
    if (sec_data.has("suffering_coefficient"))
      agent->faction.sec_profile.suffering_coefficient =
          (float)sec_data["suffering_coefficient"];
    if (sec_data.has("wall_distrust_index"))
      agent->faction.sec_profile.wall_distrust_index =
          (float)sec_data["wall_distrust_index"];
    if (sec_data.has("obedience"))
      agent->faction.sec_profile.obedience = (float)sec_data["obedience"];
    if (sec_data.has("fear_threshold"))
      agent->faction.sec_profile.fear_threshold =
          (float)sec_data["fear_threshold"];

    // Debug output to confirm update (can be removed later to reduce spam)
    // UtilityFunctions::print("[NPCAIController] Updated SEC for: ", name);
  } else {
    UtilityFunctions::printerr(
        "[NPCAIController] Could not find agent to update SEC: ", name);
  }
}

Dictionary NPCAIController::get_agent_sec_profile(const String &name) {
  Dictionary data;
  std::string s_name = name.utf8().get_data();
  NPCSystem::Agent *agent = simulation.get_agent(s_name);

  if (agent) {
    data["truth_awareness"] = agent->faction.sec_profile.truth_awareness;
    data["suffering_coefficient"] =
        agent->faction.sec_profile.suffering_coefficient;
    data["wall_distrust_index"] =
        agent->faction.sec_profile.wall_distrust_index;
    data["obedience"] = agent->faction.sec_profile.obedience;
    data["fear_threshold"] = agent->faction.sec_profile.fear_threshold;
  } else {
    UtilityFunctions::printerr(
        "[NPCAIController] Could not find agent for SEC retrieval: ", name);
  }
  return data;
}

void NPCAIController::print_simulation_status() {
  // This logs to stdout, might not appear in Godot editor console directly
  // unless running from terminal
  simulation.print_all_status();
}

} // namespace gd_ocean
