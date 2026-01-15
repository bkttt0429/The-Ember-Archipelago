#include "FactionComponent.h"

namespace NPCSystem {

bool AlignmentData::hostile_towards(const AlignmentData &other) const {
  if (type == Alignment::Passive || other.type == Alignment::Passive)
    return false;
  if (type == Alignment::Enemy && other.type == Alignment::Enemy)
    return false;
  if (type == Alignment::Enemy && other.type == Alignment::Wild)
    return false;
  if (type == Alignment::Wild && other.type == Alignment::Enemy)
    return false;
  if (type == Alignment::Wild && other.type == Alignment::Wild)
    return false;
  if (type == Alignment::Npc && other.type == Alignment::Wild)
    return false;
  if (type == Alignment::Npc && other.type == Alignment::Enemy)
    return true;
  if (type == Alignment::Enemy || other.type == Alignment::Enemy)
    return true;
  return false;
}

bool AlignmentData::passive_towards(const AlignmentData &other) const {
  if (type == Alignment::Enemy && other.type == Alignment::Enemy)
    return true;
  if (type == Alignment::Owned && other.type == Alignment::Owned && owner &&
      other.owner && *owner == *other.owner)
    return true;
  if (type == Alignment::Npc && other.type == Alignment::Npc)
    return true;
  if (type == Alignment::Npc && other.type == Alignment::Tame)
    return true;
  if (type == Alignment::Enemy && other.type == Alignment::Wild)
    return true;
  if (type == Alignment::Wild && other.type == Alignment::Enemy)
    return true;
  if (type == Alignment::Tame && other.type == Alignment::Npc)
    return true;
  if (type == Alignment::Tame && other.type == Alignment::Tame)
    return true;
  if (other.type == Alignment::Passive)
    return true;
  return false;
}

bool AlignmentData::friendly_towards(const AlignmentData &other) const {
  if (type == Alignment::Enemy && other.type == Alignment::Enemy)
    return true;
  if (type == Alignment::Owned && other.type == Alignment::Owned && owner &&
      other.owner && *owner == *other.owner)
    return true;
  if (type == Alignment::Npc && other.type == Alignment::Npc)
    return true;
  if (type == Alignment::Npc && other.type == Alignment::Tame)
    return true;
  if (type == Alignment::Tame && other.type == Alignment::Npc)
    return true;
  if (type == Alignment::Tame && other.type == Alignment::Tame)
    return true;
  if (other.type == Alignment::Passive)
    return true;
  return false;
}

} // namespace NPCSystem
