#pragma once
#include "../core/Utils.h"

namespace NPCSystem {
namespace Economy {

class MarketExchange {
public:
  float get_price(SiteId site, TradeId item);
  void simulate_market(float dt);
};

} // namespace Economy
} // namespace NPCSystem
