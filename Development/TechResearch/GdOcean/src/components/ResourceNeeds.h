#pragma once

#include "FactionComponent.h"

namespace NPCSystem {

struct ResourceNeeds {
  float coal;    // Syndicate specific
  float scrap;   // Covenant specific
  float essence; // Tidebound specific

  ResourceNeeds() : coal(0.0f), scrap(0.0f), essence(0.0f) {}

  bool is_critical(FactionId faction) const {
    switch (faction) {
    case FactionId::Syndicate:
      return coal < 20.0f;
    case FactionId::Covenant:
      return scrap < 10.0f;
    default:
      return false;
    }
  }
};

} // namespace NPCSystem
