#include "JobBlackboard.h"

namespace NPCSystem {

void JobBlackboard::post_job(const Job &job) { open_jobs.push_back(job); }

std::optional<Job> JobBlackboard::bid_for_job(Uid agent_id,
                                              JobType preferred_type) {
  int best_idx = -1;
  float best_score = -1.0f;

  for (int i = 0; i < (int)open_jobs.size(); ++i) {
    if (open_jobs[i].assigned_to.has_value())
      continue;

    float score = open_jobs[i].priority;
    if (open_jobs[i].type == preferred_type)
      score *= 2.0f;

    if (score > best_score) {
      best_score = score;
      best_idx = i;
    }
  }

  if (best_idx != -1) {
    open_jobs[best_idx].assigned_to = agent_id;
    return open_jobs[best_idx];
  }
  return std::nullopt;
}

void JobBlackboard::complete_job(Uid job_id) {
  open_jobs.erase(
      std::remove_if(open_jobs.begin(), open_jobs.end(),
                     [job_id](const Job &j) { return j.id == job_id; }),
      open_jobs.end());
}

void JobBlackboard::clear() { open_jobs.clear(); }

} // namespace NPCSystem
