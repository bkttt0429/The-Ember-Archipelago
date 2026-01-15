#pragma once

#include "../core/Utils.h"
#include <algorithm>
#include <optional>
#include <vector>


namespace NPCSystem {

enum class JobType { Scavenge, Repair, Combat, Transport };

struct Job {
  Uid id;
  JobType type;
  Vec3 position;
  float priority;
  std::optional<Uid> assigned_to;
  float difficulty;

  Job(Uid i, JobType t, Vec3 pos, float p, float d = 1.0f)
      : id(i), type(t), position(pos), priority(p), difficulty(d) {}
};

class JobBlackboard {
private:
  std::vector<Job> open_jobs;

public:
  void post_job(const Job &job);
  std::optional<Job> bid_for_job(Uid agent_id, JobType preferred_type);
  void complete_job(Uid job_id);
  void clear();
};

} // namespace NPCSystem
