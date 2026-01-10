#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <deque>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <queue>
#include <string>
#include <unordered_map>
#include <vector>

// ============================================================================
// 1. 基礎類型與向量數學
// ============================================================================

struct Vec3 {
  float x, y, z;
  Vec3(float x = 0, float y = 0, float z = 0) : x(x), y(y), z(z) {}

  float length() const { return std::sqrt(x * x + y * y + z * z); }
  float distance(const Vec3 &other) const {
    return Vec3(x - other.x, y - other.y, z - other.z).length();
  }
  Vec3 operator-(const Vec3 &other) const {
    return Vec3(x - other.x, y - other.y, z - other.z);
  }
  Vec3 operator+(const Vec3 &other) const {
    return Vec3(x + other.x, y + other.y, z + other.z);
  }
  Vec3 operator*(float s) const { return Vec3(x * s, y * s, z * s); }
  Vec3 normalized() const {
    float len = length();
    return len > 0 ? Vec3(x / len, y / len, z / len) : Vec3(0, 0, 0);
  }
};

struct Vec2 {
  float x, y;
  Vec2(float x = 0, float y = 0) : x(x), y(y) {}
  Vec2 operator*(float s) const { return Vec2(x * s, y * s); }
  float length() const { return std::sqrt(x * x + y * y); }
};

using Uid = uint64_t;
using EntityId = uint64_t;
using SiteId = uint32_t;
using TradeId = uint32_t;

// ============================================================================
// 2. 陣營系統 (Alignment)
// ============================================================================

enum class Alignment {
  Wild,   // 野生動物和溫和巨獸
  Enemy,  // 地牢邪教徒和土匪
  Npc,    // 村莊中的友善居民
  Tame,   // 村民的農場動物和寵物
  Owned,  // 用項圈馴服的寵物
  Passive // 被動物體如訓練假人
};

struct AlignmentData {
  Alignment type;
  std::optional<Uid> owner; // 用於 Owned 類型

  AlignmentData(Alignment t, std::optional<Uid> o = std::nullopt)
      : type(t), owner(o) {}

  // 總是攻擊
  bool hostile_towards(const AlignmentData &other) const {
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

  // 通常從不攻擊
  bool passive_towards(const AlignmentData &other) const {
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

  // 永不攻擊
  bool friendly_towards(const AlignmentData &other) const {
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
};

// ============================================================================
// 2.1 派系與需求系統 (Factions & Needs) [Prompt 1]
// ============================================================================

enum class FactionId {
  None,
  Syndicate, // 鋼鐵兄弟會
  Covenant,  // 漂流木公約
  Tidebound  // 深淵 (Tidebound)
};

struct FactionComponent {
  FactionId id;
  int rank; // 0-100

  FactionComponent(FactionId i = FactionId::None, int r = 0) : id(i), rank(r) {}
};

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

enum class BuoyancyState { Floating, Sinking, Submerged };

struct BuoyancyComponent {
  float current_buoyancy; // 0.0 - 100.0
  float max_buoyancy;
  bool health_linked;

  BuoyancyComponent(float max_b = 100.0f)
      : current_buoyancy(max_b), max_buoyancy(max_b), health_linked(true) {}

  BuoyancyState check_state(float health_pct) {
    if (health_linked && health_pct < 0.2f) { // If health low, buoyancy drops
      current_buoyancy = std::min(current_buoyancy, max_buoyancy * 0.2f);
    }

    if (current_buoyancy <= 0)
      return BuoyancyState::Submerged;
    if (current_buoyancy < max_buoyancy * 0.2f)
      return BuoyancyState::Sinking; // Low buoyancy threshold
    return BuoyancyState::Floating;
  }
};

// ============================================================================
// 3. 行為能力系統 (Behavior)
// ============================================================================

enum BehaviorCapability { NONE = 0, SPEAK = 1 << 0, TRADE = 1 << 1 };

enum BehaviorState { TRADING = 1 << 0, TRADING_ISSUER = 1 << 1 };

enum class TradingBehaviorType { None, RequireBalanced, AcceptFood };

struct TradingBehavior {
  TradingBehaviorType type;
  std::optional<SiteId> trade_site;

  TradingBehavior() : type(TradingBehaviorType::None) {}

  bool can_trade(const AlignmentData &alignment, Uid counterparty) const {
    switch (type) {
    case TradingBehaviorType::RequireBalanced:
      return true;
    case TradingBehaviorType::AcceptFood:
      return alignment.type == Alignment::Owned && alignment.owner &&
             *alignment.owner == counterparty;
    case TradingBehaviorType::None:
      return false;
    }
    return false;
  }
};

class Behavior {
private:
  int capabilities;
  int state;

public:
  TradingBehavior trading_behavior;

  Behavior() : capabilities(BehaviorCapability::NONE), state(0) {}

  explicit Behavior(int caps) : capabilities(caps), state(0) {}

  Behavior &maybe_with_capabilities(std::optional<int> maybe_caps) {
    if (maybe_caps)
      allow(*maybe_caps);
    return *this;
  }

  Behavior &with_trade_site(std::optional<SiteId> site) {
    if (site) {
      trading_behavior.type = TradingBehaviorType::RequireBalanced;
      trading_behavior.trade_site = site;
    }
    return *this;
  }

  void allow(int cap) { capabilities |= cap; }
  void deny(int cap) { capabilities &= ~cap; }
  bool can(int cap) const { return (capabilities & cap) != 0; }

  void set_state(int s) { state |= s; }
  void unset_state(int s) { state &= ~s; }
  bool is(int s) const { return (state & s) != 0; }

  bool can_trade(const AlignmentData &alignment, Uid counterparty) const {
    return trading_behavior.can_trade(alignment, counterparty);
  }

  std::optional<SiteId> trade_site() const {
    if (trading_behavior.type == TradingBehaviorType::RequireBalanced) {
      return trading_behavior.trade_site;
    }
    return std::nullopt;
  }
};

// ============================================================================
// 4. 心理特質 (Psyche)
// ============================================================================

struct Psyche {
  float flee_health;               // 逃跑血量閾值 (0.0-1.0)
  float sight_dist;                // 視野距離
  float listen_dist;               // 聽覺距離
  std::optional<float> aggro_dist; // 攻擊距離 (None = 總是攻擊)
  float idle_wander_factor;        // 閒置遊蕩因子
  float aggro_range_multiplier;    // 攻擊範圍倍數
  bool should_stop_pursuing;       // 是否應該停止追擊

  Psyche()
      : flee_health(0.4f), sight_dist(40.0f), listen_dist(30.0f),
        aggro_dist(20.0f), idle_wander_factor(1.0f),
        aggro_range_multiplier(1.0f), should_stop_pursuing(true) {}

  // 最大偵測距離
  float search_dist() const {
    return std::max(sight_dist, listen_dist) * aggro_range_multiplier;
  }

  // 根據身體類型設置（簡化版）
  static Psyche from_body_type(const std::string &body_type) {
    Psyche p;
    if (body_type == "Humanoid") {
      p.flee_health = 0.4f;
      p.sight_dist = 40.0f;
      p.aggro_dist = 20.0f;
    } else if (body_type == "BirdLarge") {
      p.flee_health = 0.0f;
      p.sight_dist = 250.0f;
      p.aggro_dist = std::nullopt;
      p.should_stop_pursuing = false;
    } else if (body_type == "Wolf") {
      p.flee_health = 0.2f;
      p.sight_dist = 40.0f;
      p.aggro_dist = std::nullopt;
    }
    return p;
  }
};

// ============================================================================
// 5. 聲音系統 (Sound)
// ============================================================================

enum class SoundKind {
  Unknown,
  Utterance,
  Movement,
  Melee,
  Projectile,
  Explosion,
  Beam,
  Shockwave,
  Mine,
  Trap
};

struct Sound {
  SoundKind kind;
  Vec3 pos;
  float vol;
  double time;

  Sound(SoundKind k, Vec3 p, float v, double t)
      : kind(k), pos(p), vol(v), time(t) {}

  Sound with_new_vol(float new_vol) const {
    return Sound(kind, pos, new_vol, time);
  }
};

// ============================================================================
// 6. 目標系統 (Target)
// ============================================================================

struct Target {
  EntityId target;
  bool hostile;
  double selected_at;
  bool aggro_on;
  std::optional<Vec3> last_known_pos;

  Target(EntityId t, bool h, double s, bool a,
         std::optional<Vec3> pos = std::nullopt)
      : target(t), hostile(h), selected_at(s), aggro_on(a),
        last_known_pos(pos) {}
};

// ============================================================================
// 7. 計時器系統 (Timer)
// ============================================================================

enum class TimerAction { Interact, Warn };

class Timer {
private:
  std::unordered_map<TimerAction, std::optional<double>> action_starts;
  std::optional<TimerAction> last_action;

public:
  Timer() {}

  bool reset(TimerAction action) {
    auto it = action_starts.find(action);
    if (it != action_starts.end() && it->second.has_value()) {
      it->second = std::nullopt;
      return true;
    }
    return false;
  }

  void start(double time, TimerAction action) {
    action_starts[action] = time;
    last_action = action;
  }

  void progress(double time, TimerAction action) {
    if (last_action != action) {
      start(time, action);
    }
  }

  std::optional<double> time_of_last(TimerAction action) const {
    auto it = action_starts.find(action);
    return (it != action_starts.end()) ? it->second : std::nullopt;
  }

  bool time_since_exceeds(double time, TimerAction action,
                          double timeout) const {
    auto last_time = time_of_last(action);
    if (!last_time)
      return true;
    return std::max(0.0, time - *last_time) > timeout;
  }

  std::optional<bool> timeout_elapsed(double time, TimerAction action,
                                      double timeout) {
    if (time_since_exceeds(time, action, timeout)) {
      return reset(action);
    } else {
      progress(time, action);
      return std::nullopt;
    }
  }
};

// ============================================================================
// 8. 意識系統 (Awareness)
// ============================================================================

enum class AwarenessState {
  Unaware = 0,
  Low = 1,
  Medium = 2,
  High = 3,
  Alert = 4
};

class Awareness {
private:
  static constexpr float ALERT = 1.0f;
  static constexpr float HIGH = 0.6f;
  static constexpr float MEDIUM = 0.3f;
  static constexpr float LOW = 0.1f;
  static constexpr float UNAWARE = 0.0f;

  float level;
  bool reached;

public:
  Awareness(float lvl = 0.0f)
      : level(std::clamp(lvl, UNAWARE, ALERT)), reached(false) {}

  float get_level() const { return level; }

  AwarenessState state() const {
    if (level == ALERT)
      return AwarenessState::Alert;
    if (level >= HIGH)
      return AwarenessState::High;
    if (level >= MEDIUM)
      return AwarenessState::Medium;
    if (level >= LOW)
      return AwarenessState::Low;
    return AwarenessState::Unaware;
  }

  bool has_reached() const { return reached; }

  void change_by(float amount) {
    level = std::clamp(level + amount, UNAWARE, ALERT);

    if (state() == AwarenessState::Alert) {
      reached = true;
    } else if (state() == AwarenessState::Unaware) {
      reached = false;
    }
  }

  void set_maximally_aware() {
    reached = true;
    level = ALERT;
  }
};

// ============================================================================
// 9. 代理事件 (AgentEvent)
// ============================================================================

enum class AgentEventType {
  Talk,
  TradeInvite,
  TradeAccepted,
  FinishedTrade,
  UpdatePendingTrade,
  ServerSound,
  Hurt,
  Dialogue
};

struct AgentEvent {
  AgentEventType type;
  std::optional<Uid> uid;
  std::optional<Sound> sound;

  AgentEvent(AgentEventType t, std::optional<Uid> u = std::nullopt,
             std::optional<Sound> s = std::nullopt)
      : type(t), uid(u), sound(s) {}
};

// ============================================================================
// 9.1 世界事件總線 (World Event Bus) [Prompt 2]
// ============================================================================

enum class WorldEventType {
  StructuralFailure, // Physics -> Social
  DistressSignal,
  ResourceEvent, // Drifting debris
  FloodingAlarm, // Sensor -> AI
  HarpoonEvent   // Combat,
};

struct WorldEvent {
  WorldEventType type;
  Vec3 position;
  float radius;
  EntityId source_id;
  FactionId source_faction;
  std::string metadata; // e.g. "Sensor > 0.5m" or "LegBroken"

  WorldEvent(WorldEventType t, Vec3 pos, float r, EntityId src,
             FactionId fac = FactionId::None)
      : type(t), position(pos), radius(r), source_id(src), source_faction(fac) {
  }
};

class WorldEventBus {
private:
  std::deque<WorldEvent> events;

public:
  void publish(const WorldEvent &e) { events.push_back(e); }

  // Returns events relevant to a position and radius
  std::vector<WorldEvent> query_nearby(Vec3 pos, float range) const {
    std::vector<WorldEvent> result;
    for (const auto &e : events) {
      if (e.position.distance(pos) <= range) {
        result.push_back(e);
      }
    }
    return result;
  }

  void clear_old() {
    // Simple clear for simulation step
    events.clear();
  }
};

// ============================================================================
// 9.2 邏輯橋接系統 (Logic Bridge System) [Prompt 3]
// ============================================================================

struct Sensor {
  std::string metric; // "WaterLevel"
  float value;
  float threshold;
  EntityId owner_id;
  Vec3 position;

  bool check() const { return value > threshold; }
};

class LogicBridgeSystem {
public:
  void process_sensors(const std::vector<Sensor> &sensors, WorldEventBus &bus) {
    for (const auto &s : sensors) {
      if (s.check()) {
        if (s.metric == "WaterLevel") {
          bus.publish(WorldEvent(WorldEventType::FloodingAlarm, s.position,
                                 50.0f, s.owner_id));
        }
      }
    }
  }
};

// ============================================================================
// 10. 動作狀態 (ActionState)
// ============================================================================

constexpr size_t NUM_TIMERS = 5;
constexpr size_t NUM_COUNTERS = 5;
constexpr size_t NUM_INT_COUNTERS = 5;
constexpr size_t NUM_CONDITIONS = 5;
constexpr size_t NUM_POSITIONS = 5;

struct ActionState {
  std::array<float, NUM_TIMERS> timers;
  std::array<float, NUM_COUNTERS> counters;
  std::array<bool, NUM_CONDITIONS> conditions;
  std::array<uint8_t, NUM_INT_COUNTERS> int_counters;
  std::array<std::optional<Vec3>, NUM_POSITIONS> positions;
  bool initialized;

  ActionState() : initialized(false) {
    timers.fill(0.0f);
    counters.fill(0.0f);
    conditions.fill(false);
    int_counters.fill(0);
    positions.fill(std::nullopt);
  }
};

// ============================================================================
// 11. 尋路系統 (Chaser)
// ============================================================================

class Chaser {
private:
  std::vector<Vec3> nodes;
  std::optional<Vec3> goal;

public:
  Chaser() {}

  void set_path(const std::vector<Vec3> &path) { nodes = path; }

  void set_goal(const Vec3 &g) { goal = g; }

  std::optional<Vec3> get_next_node() const {
    if (!nodes.empty())
      return nodes[0];
    return std::nullopt;
  }

  void advance() {
    if (!nodes.empty())
      nodes.erase(nodes.begin());
  }

  bool has_path() const { return !nodes.empty(); }
  std::optional<Vec3> get_goal() const { return goal; }
};

// ============================================================================
// 12. PID 控制器 (用於飛行載具)
// ============================================================================

template <size_t NUM_SAMPLES> class PidController {
private:
  float kp, ki, kd;
  float sp; // setpoint
  std::array<std::pair<double, float>, NUM_SAMPLES> pv_samples;
  size_t pv_idx;
  double integral_error;
  std::function<float(float, float)> error_func;

public:
  PidController(
      float kp, float ki, float kd, float sp, double time,
      std::function<float(float, float)> ef = [](float a,
                                                 float b) { return a - b; })
      : kp(kp), ki(ki), kd(kd), sp(sp), pv_idx(0), integral_error(0.0),
        error_func(ef) {
    pv_samples.fill({time, sp});
  }

  void add_measurement(double time, float pv) {
    pv_idx = (pv_idx + 1) % NUM_SAMPLES;
    pv_samples[pv_idx] = {time, pv};
    update_integral_error();
  }

  float calc_error() const {
    return kp * proportional_error() + ki * integral_error_value() +
           kd * derivative_error();
  }

  float proportional_error() const {
    return error_func(sp, pv_samples[pv_idx].second);
  }

  float integral_error_value() const {
    return static_cast<float>(integral_error);
  }

  float derivative_error() const {
    size_t prev_idx = (pv_idx + NUM_SAMPLES - 1) % NUM_SAMPLES;
    auto [a, x0] = pv_samples[prev_idx];
    auto [b, x1] = pv_samples[pv_idx];
    double h = b - a;
    if (h == 0.0)
      return 0.0f;
    return (error_func(sp, x1) - error_func(sp, x0)) / static_cast<float>(h);
  }

  void limit_integral_windup(std::function<void(double &)> limiter) {
    limiter(integral_error);
  }

private:
  void update_integral_error() {
    size_t prev_idx = (pv_idx + NUM_SAMPLES - 1) % NUM_SAMPLES;
    auto [a, x0] = pv_samples[prev_idx];
    auto [b, x1] = pv_samples[pv_idx];
    double dx = b - a;

    if (dx < 5.0) { // 忽略過長的間隔
      auto f = [this](float x) {
        return static_cast<double>(error_func(sp, x));
      };
      integral_error += dx * (f(x1) + f(x0)) / 2.0;
    }
  }
};

enum class FlightMode { Braking, FlyThrough };

template <size_t NUM_SAMPLES> struct PidControllers {
  FlightMode mode;
  std::optional<PidController<NUM_SAMPLES>> x_controller;
  std::optional<PidController<NUM_SAMPLES>> y_controller;
  std::optional<PidController<NUM_SAMPLES>> z_controller;

  PidControllers(FlightMode m) : mode(m) {}

  void add_measurement(double time, const Vec3 &pos) {
    if (x_controller)
      x_controller->add_measurement(time, pos.x);
    if (y_controller)
      y_controller->add_measurement(time, pos.y);
    if (z_controller)
      z_controller->add_measurement(time, pos.z);
  }

  Vec3 calc_error() const {
    return Vec3(x_controller ? x_controller->calc_error() : 0.0f,
                y_controller ? y_controller->calc_error() : 0.0f,
                z_controller ? z_controller->calc_error() : 0.0f);
  }
};

// ============================================================================
// 13. RtSim 控制器 (簡化版)
// ============================================================================

class RtSimController {
private:
  std::optional<Vec3> destination;

public:
  RtSimController() {}

  static RtSimController with_destination(const Vec3 &dest) {
    RtSimController ctrl;
    ctrl.destination = dest;
    return ctrl;
  }

  std::optional<Vec3> get_destination() const { return destination; }
  void set_destination(const Vec3 &dest) { destination = dest; }
  void clear_destination() { destination = std::nullopt; }
};

// ============================================================================
// 13.1 Geopolitics Event System (New)
// ============================================================================

enum class WorldEventType {
  StructuralFailure,
  HarpoonEvent,
  ResourceScarce,
  DiplomacyChange
};

struct WorldEvent {
  WorldEventType type;
  Vec3 position;
  float intensity;
  int source_id;
  FactionId related_faction;

  WorldEvent(WorldEventType t, Vec3 pos, float i, int src,
             FactionId fac = FactionId::None)
      : type(t), position(pos), intensity(i), source_id(src),
        related_faction(fac) {}
};

struct Sensor {
  std::string type;
  float value;
  float threshold;
  int id;
  Vec3 position;
};

class EventBus {
public:
  void publish(const WorldEvent &event) {
    std::cout << "[EventBus] 發布事件: Type=" << (int)event.type << " Pos=("
              << event.position.x << "," << event.position.y << ","
              << event.position.z << ") Intensity=" << event.intensity << "\n";
  }
};

class LogicBridge {
public:
  void process_sensors(const std::vector<Sensor> &sensors, EventBus &bus) {
    for (const auto &s : sensors) {
      if (s.value > s.threshold) {
        std::cout << "[LogicBridge] 傳感器觸發: " << s.type << "\n";
        // Logic to trigger event based on sensor
      }
    }
  }
};

// ============================================================================
// 14. Agent 主類
// ============================================================================

constexpr float DEFAULT_INTERACTION_TIME = 3.0f;
constexpr float TRADE_INTERACTION_TIME = 300.0f;
constexpr double SECONDS_BEFORE_FORGET_SOUNDS = 180.0;

class Agent {
public:
  RtSimController rtsim_controller;
  std::optional<Vec3> patrol_origin;
  std::optional<Target> target;
  Chaser chaser;
  Behavior behavior;
  Psyche psyche;
  std::deque<AgentEvent> inbox;
  ActionState combat_state;
  ActionState behavior_state;
  Timer timer;
  Vec2 bearing;
  std::vector<Sound> sounds_heard;
  std::optional<PidControllers<16>> multi_pid_controllers;
  std::optional<Vec3> flee_from_pos;
  Awareness awareness;
  std::optional<Vec3> stay_pos;

  // [Prompt 1] Components
  FactionComponent faction;
  ResourceNeeds needs;
  BuoyancyComponent buoyancy;

  // 構造函數：從身體類型創建
  static Agent from_body(const std::string &body_type) {
    Agent agent;
    agent.psyche = Psyche::from_body_type(body_type);
    return agent;
  }

  Agent &with_patrol_origin(const Vec3 &origin) {
    patrol_origin = origin;
    return *this;
  }

  Agent &with_behavior(const Behavior &b) {
    behavior = b;
    return *this;
  }

  Agent &with_no_flee_if(bool condition) {
    if (condition)
      psyche.flee_health = 0.0f;
    return *this;
  }

  void set_no_flee() { psyche.flee_health = 0.0f; }

  Agent &with_destination(const Vec3 &pos) {
    psyche.flee_health = 0.0f;
    rtsim_controller = RtSimController::with_destination(pos);
    behavior.allow(BehaviorCapability::SPEAK);
    return *this;
  }

  Agent &with_idle_wander_factor(float factor) {
    psyche.idle_wander_factor = factor;
    return *this;
  }

  Agent &with_aggro_range_multiplier(float multiplier) {
    psyche.aggro_range_multiplier = multiplier;
    return *this;
  }

  Agent &with_altitude_pid_controller(const PidControllers<16> &mpid) {
    multi_pid_controllers = mpid;
    return *this;
  }

  Agent &with_aggro_no_warn() {
    psyche.aggro_dist = std::nullopt;
    return *this;
  }

  void forget_old_sounds(double time) {
    if (!sounds_heard.empty()) {
      sounds_heard.erase(
          std::remove_if(sounds_heard.begin(), sounds_heard.end(),
                         [time](const Sound &s) {
                           return time - s.time > SECONDS_BEFORE_FORGET_SOUNDS;
                         }),
          sounds_heard.end());
    }
  }

  bool allowed_to_speak() const {
    return behavior.can(BehaviorCapability::SPEAK);
  }

  void push_event(const AgentEvent &event) { inbox.push_back(event); }

  // [Prompt 4] 派系特徵決策邏輯
  void decide_next_action(WorldEventBus *bus, const Vec3 &current_pos) {
    if (!bus)
      return;

    // Syndicate (鋼鐵): 煤炭需求與維修
    if (faction.id == FactionId::Syndicate) {
      // [Prompt 1 & 4] Coal Need
      if (needs.coal < 20.0f) {
        std::cout << "[Syndicate] 警告: 煤炭不足 (" << needs.coal
                  << "<20)! 尋找貿易站或煤礦.\n";
        // 實際邏輯: set_goal(nearest_trade_post)
      }

      // [Prompt 2] Structural Failure Response
      auto nearby = bus->query_nearby(current_pos, 200.0f);
      for (const auto &e : nearby) {
        if (e.type == WorldEventType::StructuralFailure &&
            e.source_faction == FactionId::Syndicate) {
          std::cout << "[Syndicate] 收到盟友 (" << e.source_id
                    << ") 結構損壞求救! 發送維修請求.\n";
        }
      }
    }

    // Covenant (漂流木): 拾荒與魚叉
    if (faction.id == FactionId::Covenant) {
      auto nearby = bus->query_nearby(current_pos, 100.0f);
      for (const auto &e : nearby) {
        // [Prompt 4] Harpoon -> Swarm
        if (e.type == WorldEventType::HarpoonEvent) {
          std::cout
              << "[Covenant] 偵測到魚叉攻擊! 觸發 SwarmAttack 蜂群戰術!\n";
          awareness.set_maximally_aware();
        }
        // [Prompt 2] Structural Failure -> Scavenge
        if (e.type == WorldEventType::StructuralFailure) {
          std::cout << "[Covenant] 發現殘骸 (" << e.source_id
                    << ")! 設定目標進行拾荒 (Scavenge).\n";
        }
      }
    }

    // Tidebound (深淵): 潛行
    if (faction.id == FactionId::Tidebound) {
      // [Prompt 4] High Awareness -> Dive
      if (awareness.state() == AwarenessState::High ||
          awareness.state() == AwarenessState::Alert) {
        std::cout << "[Tidebound] 威脅過高! 執行下潛 (Dive) 規避視線.\n";
        buoyancy.current_buoyancy = -10.0f; // Force dive
      }
    }

    // Logic Bridge Response [Prompt 3]
    auto sensors = bus->query_nearby(current_pos, 50.0f);
    for (const auto &e : sensors) {
      if (e.type == WorldEventType::FloodingAlarm) {
        std::cout << "[Agent] 收到水位警報! 切換至損管 (DamageControl) 狀態.\n";
      }
    }

    // Check Buoyancy [Prompt 1]
    if (buoyancy.check_state(1.0f) ==
        BuoyancyState::Sinking) { // Assuming full health for check
      std::cout << "[Agent] 浮力過低 (<20%)! 正在下沉!\n";
    }
  }

  // 更新函數
  void update(double dt, double current_time, const Vec3 &current_pos,
              WorldEventBus *world_bus = nullptr) {
    // 0. 派系與物理決策 [Prompt 4]
    if (world_bus) {
      decide_next_action(world_bus, current_pos);
    }
    // 1. 處理事件
    while (!inbox.empty()) {
      process_event(inbox.front());
      inbox.pop_front();
    }

    // 2. 忘記舊聲音
    forget_old_sounds(current_time);

    // 3. 更新意識（自然衰減）
    awareness.change_by(-dt * 0.01f);

    // 4. 更新 PID 控制器
    if (multi_pid_controllers) {
      multi_pid_controllers->add_measurement(current_time, current_pos);
    }
  }

  void print_status(const std::string &name) const {
    std::cout << "\n=== " << name << " 狀態 ===\n";
    std::cout << "意識等級: " << awareness_to_string(awareness.state()) << " ("
              << (awareness.get_level() * 100) << "%)\n";
    std::cout << "已達警戒: " << (awareness.has_reached() ? "是" : "否")
              << "\n";
    std::cout << "聽到聲音數: " << sounds_heard.size() << "\n";
    std::cout << "收件箱事件: " << inbox.size() << "\n";
    if (target) {
      std::cout << "目標: 實體 " << target->target
                << (target->hostile ? " (敵對)" : " (非敵對)") << "\n";
    }
    if (patrol_origin) {
      std::cout << "巡邏原點: (" << patrol_origin->x << ", " << patrol_origin->y
                << ", " << patrol_origin->z << ")\n";
    }
  }

private:
  void process_event(const AgentEvent &event) {
    switch (event.type) {
    case AgentEventType::ServerSound:
      if (event.sound) {
        sounds_heard.push_back(*event.sound);
        // 根據聲音類型增加意識
        float awareness_increase = 0.1f;
        if (event.sound->kind == SoundKind::Explosion) {
          awareness_increase = 0.5f;
        } else if (event.sound->kind == SoundKind::Melee) {
          awareness_increase = 0.3f;
        }
        awareness.change_by(awareness_increase);
      }
      break;

    case AgentEventType::Hurt:
      awareness.set_maximally_aware();
      break;

    case AgentEventType::Talk:
    case AgentEventType::Dialogue:
      awareness.change_by(0.2f);
      break;

    default:
      break;
    }
  }

  static std::string awareness_to_string(AwarenessState state) {
    switch (state) {
    case AwarenessState::Unaware:
      return "未察覺";
    case AwarenessState::Low:
      return "低度警覺";
    case AwarenessState::Medium:
      return "中度警覺";
    case AwarenessState::High:
      return "高度警覺";
    case AwarenessState::Alert:
      return "完全警戒";
    default:
      return "未知";
    }
  }
};

// ============================================================================
// 15. 測試與演示
// ============================================================================

class Simulation {
private:
  std::vector<std::pair<std::string, Agent>> agents;
  double current_time;

public:
  WorldEventBus event_bus; // Public for testing access
  LogicBridgeSystem logic_bridge;

  Simulation() : current_time(0.0) {}

  void add_agent(const std::string &name, const Agent &agent) {
    agents.push_back({name, agent});
  }

  void step(double dt) {
    current_time += dt;

    for (auto &[name, agent] : agents) {
      Vec3 pos(0, 0, 0); // 簡化：固定位置
      agent.update(dt, current_time, pos, &event_bus);
    }

    // Clear old events
    event_bus.clear_old();
  }

  void print_all_status() const {
    for (const auto &[name, agent] : agents) {
      agent.print_status(name);
    }
  }

  Agent *get_agent(const std::string &name) {
    for (auto &[n, agent] : agents) {
      if (n == name)
        return &agent;
    }
    return nullptr;
  }
};
// ============================================================================
// 16. 完整測試場景
// ============================================================================
void test_alignment_system() {
  std::cout << "\n========== 測試 1: 陣營系統 ==========\n";
  AlignmentData wild(Alignment::Wild);
  AlignmentData enemy(Alignment::Enemy);
  AlignmentData npc(Alignment::Npc);
  AlignmentData tame(Alignment::Tame);
  AlignmentData owned1(Alignment::Owned, 100);
  AlignmentData owned2(Alignment::Owned, 200);
  AlignmentData owned3(Alignment::Owned, 100);
  AlignmentData passive(Alignment::Passive);

  std::cout << "敵人 vs NPC (hostile): "
            << (enemy.hostile_towards(npc) ? "是" : "否") << "\n";
  std::cout << "野生 vs 野生 (hostile): "
            << (wild.hostile_towards(wild) ? "是" : "否") << "\n";
  std::cout << "NPC vs NPC (friendly): "
            << (npc.friendly_towards(npc) ? "是" : "否") << "\n";
  std::cout << "擁有者1的寵物 vs 擁有者2的寵物 (friendly): "
            << (owned1.friendly_towards(owned2) ? "是" : "否") << "\n";
  std::cout << "擁有者1的寵物 vs 擁有者1的另一寵物 (friendly): "
            << (owned1.friendly_towards(owned3) ? "是" : "否") << "\n";
  std::cout << "任何陣營 vs 被動物體 (friendly): "
            << (enemy.friendly_towards(passive) ? "是" : "否") << "\n";
}
void test_behavior_system() {
  std::cout << "\n========== 測試 2: 行為系統 ==========\n";
  Behavior merchant;
  merchant.allow(BehaviorCapability::SPEAK);
  merchant.allow(BehaviorCapability::TRADE);
  merchant = merchant.with_trade_site(101);

  std::cout << "商人可以說話: "
            << (merchant.can(BehaviorCapability::SPEAK) ? "是" : "否") << "\n";
  std::cout << "商人可以交易: "
            << (merchant.can(BehaviorCapability::TRADE) ? "是" : "否") << "\n";
  std::cout << "商人的交易站點: "
            << (merchant.trade_site() ? std::to_string(*merchant.trade_site())
                                      : "無")
            << "\n";

  merchant.set_state(BehaviorState::TRADING);
  std::cout << "商人正在交易: "
            << (merchant.is(BehaviorState::TRADING) ? "是" : "否") << "\n";

  merchant.unset_state(BehaviorState::TRADING);
  std::cout << "取消交易後: "
            << (merchant.is(BehaviorState::TRADING) ? "是" : "否") << "\n";
}
void test_psyche_system() {
  std::cout << "\n========== 測試 3: 心理特質系統 ==========\n";
  Psyche humanoid = Psyche::from_body_type("Humanoid");
  Psyche bird = Psyche::from_body_type("BirdLarge");
  Psyche wolf = Psyche::from_body_type("Wolf");

  std::cout << "人形生物:\n";
  std::cout << "  逃跑血量: " << (humanoid.flee_health * 100) << "%\n";
  std::cout << "  視野距離: " << humanoid.sight_dist << "m\n";
  std::cout << "  搜索距離: " << humanoid.search_dist() << "m\n";

  std::cout << "\n大型鳥類:\n";
  std::cout << "  逃跑血量: " << (bird.flee_health * 100) << "%\n";
  std::cout << "  視野距離: " << bird.sight_dist << "m\n";
  std::cout << "  停止追擊: " << (bird.should_stop_pursuing ? "是" : "否")
            << "\n";

  std::cout << "\n狼:\n";
  std::cout << "  逃跑血量: " << (wolf.flee_health * 100) << "%\n";
  std::cout << "  攻擊距離: "
            << (wolf.aggro_dist ? std::to_string(*wolf.aggro_dist) : "總是攻擊")
            << "\n";
}
void test_timer_system() {
  std::cout << "\n========== 測試 4: 計時器系統 ==========\n";
  Timer timer;
  double current_time = 0.0;

  timer.start(current_time, TimerAction::Interact);
  std::cout << "開始互動計時 (t=" << current_time << ")\n";

  current_time = 2.0;
  std::cout << "2秒後檢查是否超時 (閾值=3秒): "
            << (timer.time_since_exceeds(current_time, TimerAction::Interact,
                                         3.0)
                    ? "是"
                    : "否")
            << "\n";

  current_time = 4.0;
  std::cout << "4秒後檢查是否超時 (閾值=3秒): "
            << (timer.time_since_exceeds(current_time, TimerAction::Interact,
                                         3.0)
                    ? "是"
                    : "否")
            << "\n";

  auto result = timer.timeout_elapsed(current_time, TimerAction::Interact, 3.0);
  std::cout << "timeout_elapsed 返回: "
            << (result ? (*result ? "已重置" : "未重置") : "仍在計時") << "\n";
}
void test_awareness_system() {
  std::cout << "\n========== 測試 5: 意識系統 ==========\n";
  Awareness aware(0.0f);

  std::cout << "初始狀態: " << awareness_state_to_string(aware.state())
            << " (等級: " << (aware.get_level() * 100) << "%)\n";

  aware.change_by(0.25f);
  std::cout << "聽到聲音後: " << awareness_state_to_string(aware.state())
            << " (等級: " << (aware.get_level() * 100) << "%)\n";

  aware.change_by(0.40f);
  std::cout << "看到敵人後: " << awareness_state_to_string(aware.state())
            << " (等級: " << (aware.get_level() * 100) << "%)\n";

  aware.set_maximally_aware();
  std::cout << "受到攻擊後: " << awareness_state_to_string(aware.state())
            << " (等級: " << (aware.get_level() * 100) << "%)\n";
  std::cout << "已達警戒: " << (aware.has_reached() ? "是" : "否") << "\n";

  aware.change_by(-0.5f);
  std::cout << "經過時間衰減: " << awareness_state_to_string(aware.state())
            << " (等級: " << (aware.get_level() * 100) << "%)\n";
  std::cout << "已達警戒標記保持: " << (aware.has_reached() ? "是" : "否")
            << "\n";
}
void test_pid_controller() {
  std::cout << "\n========== 測試 6: PID 控制器 ==========\n";
  PidController<16> pid(1.0f, 0.1f, 0.8f, 100.0f, 0.0);

  std::cout << "目標高度: 100m\n";

  double time = 0.0;
  std::vector<float> altitudes = {50.0f, 65.0f, 78.0f,  88.0f,
                                  95.0f, 99.0f, 100.5f, 100.0f};

  for (float alt : altitudes) {
    pid.add_measurement(time, alt);
    float error = pid.calc_error();

    std::cout << "時間 " << time << "s, 當前高度: " << alt
              << "m, PID 誤差: " << error << "\n";
    std::cout << "  P項: " << pid.proportional_error()
              << ", I項: " << pid.integral_error_value()
              << ", D項: " << pid.derivative_error() << "\n";

    time += 1.0;
  }
}
void test_chaser_system() {
  std::cout << "\n========== 測試 7: 尋路系統 ==========\n";
  Chaser chaser;
  std::vector<Vec3> path = {Vec3(10, 0, 0), Vec3(20, 10, 0), Vec3(30, 10, 5),
                            Vec3(40, 0, 5)};

  chaser.set_path(path);
  chaser.set_goal(Vec3(40, 0, 5));

  std::cout << "設置路徑點數: " << path.size() << "\n";
  std::cout << "目標: (" << chaser.get_goal()->x << ", " << chaser.get_goal()->y
            << ", " << chaser.get_goal()->z << ")\n";

  int step = 1;
  while (chaser.has_path()) {
    auto next = chaser.get_next_node();
    if (next) {
      std::cout << "步驟 " << step++ << ": 前往 (" << next->x << ", " << next->y
                << ", " << next->z << ")\n";
    }
    chaser.advance();
  }

  std::cout << "路徑完成\n";
}
void test_agent_integration() {
  std::cout << "\n========== 測試 8: Agent 整合測試 ==========\n";
  Simulation sim;

  // 創建村民
  Agent villager = Agent::from_body("Humanoid");
  villager.behavior.allow(BehaviorCapability::SPEAK);
  villager.behavior.allow(BehaviorCapability::TRADE);
  villager = villager.with_patrol_origin(Vec3(100, 100, 0));
  sim.add_agent("村民", villager);

  // 創建狼
  Agent wolf = Agent::from_body("Wolf");
  wolf = wolf.with_aggro_no_warn();
  sim.add_agent("狼", wolf);

  // 創建巨鳥
  Agent bird = Agent::from_body("BirdLarge");
  bird = bird.with_idle_wander_factor(2.0f);
  sim.add_agent("巨鳥", bird);

  std::cout << "\n--- 初始狀態 ---\n";
  sim.print_all_status();

  // 場景 1: 村民聽到聲音
  std::cout << "\n--- 場景 1: 村民聽到爆炸聲 ---\n";
  Agent *v = sim.get_agent("村民");
  if (v) {
    Sound explosion(SoundKind::Explosion, Vec3(50, 50, 0), 1.0f, 0.0);
    v->push_event(
        AgentEvent(AgentEventType::ServerSound, std::nullopt, explosion));
    sim.step(1.0);
    v->print_status("村民");
  }

  // 場景 2: 狼受傷
  std::cout << "\n--- 場景 2: 狼受到攻擊 ---\n";
  Agent *w = sim.get_agent("狼");
  if (w) {
    w->push_event(AgentEvent(AgentEventType::Hurt));
    sim.step(1.0);
    w->print_status("狼");
  }

  // 場景 3: 時間流逝，意識衰減
  std::cout << "\n--- 場景 3: 10 秒後 ---\n";
  for (int i = 0; i < 10; ++i) {
    sim.step(1.0);
  }
  sim.print_all_status();
}
void test_action_state() {
  std::cout << "\n========== 測試 9: 動作狀態系統 ==========\n";
  ActionState state;

  std::cout << "初始化狀態: " << (state.initialized ? "是" : "否") << "\n";

  state.initialized = true;
  state.timers[0] = 5.0f;
  state.counters[0] = 3.14f;
  state.int_counters[0] = 42;
  state.conditions[0] = true;
  state.positions[0] = Vec3(10, 20, 30);

  std::cout << "設置狀態後:\n";
  std::cout << "  計時器[0]: " << state.timers[0] << "\n";
  std::cout << "  計數器[0]: " << state.counters[0] << "\n";
  std::cout << "  整數計數器[0]: " << (int)state.int_counters[0] << "\n";
  std::cout << "  條件[0]: " << (state.conditions[0] ? "真" : "假") << "\n";
  std::cout << "  位置[0]: (" << state.positions[0]->x << ", "
            << state.positions[0]->y << ", " << state.positions[0]->z << ")\n";

  std::cout << "\n可用狀態槽位:\n";
  std::cout << "  計時器: " << NUM_TIMERS << "\n";
  std::cout << "  浮點計數器: " << NUM_COUNTERS << "\n";
  std::cout << "  整數計數器: " << NUM_INT_COUNTERS << "\n";
  std::cout << "  條件: " << NUM_CONDITIONS << "\n";
  std::cout << "  位置: " << NUM_POSITIONS << "\n";
}
void test_rtsim_controller() {
  std::cout << "\n========== 測試 10: RtSim 控制器 ==========\n";
  RtSimController ctrl;
  std::cout << "初始目的地: " << (ctrl.get_destination() ? "已設置" : "未設置")
            << "\n";

  ctrl.set_destination(Vec3(100, 200, 50));
  auto dest = ctrl.get_destination();
  if (dest) {
    std::cout << "設置目的地: (" << dest->x << ", " << dest->y << ", "
              << dest->z << ")\n";
  }

  ctrl.clear_destination();
  std::cout << "清除後: " << (ctrl.get_destination() ? "已設置" : "未設置")
            << "\n";

  // 使用靜態工廠方法
  auto ctrl2 = RtSimController::with_destination(Vec3(50, 75, 25));
  dest = ctrl2.get_destination();
  if (dest) {
    std::cout << "工廠方法創建的控制器目的地: (" << dest->x << ", " << dest->y
              << ", " << dest->z << ")\n";
  }
}
std::string awareness_state_to_string(AwarenessState state) {
  switch (state) {
  case AwarenessState::Unaware:
    return "未察覺";
  case AwarenessState::Low:
    return "低度警覺";
  case AwarenessState::Medium:
    return "中度警覺";
  case AwarenessState::High:
    return "高度警覺";
  case AwarenessState::Alert:
    return "完全警戒";
  default:
    return "未知";
  }
}
// ============================================================================
// 17. 地緣政治系統測試 [New]
// ============================================================================
void test_geopolitics_system() {
  std::cout << "\n========== 測試 11: 地緣政治與派系邏輯 ==========\n";
  Simulation sim;

  // 1. Setup Syndicate Agent (Low Coal)
  Agent syn = Agent::from_body("Humanoid");
  syn.faction = FactionComponent(FactionId::Syndicate, 50);
  syn.needs.coal = 15.0f; // Critical
  sim.add_agent("鋼鐵工兵", syn);

  // 2. Setup Covenant Agent
  Agent cov = Agent::from_body("Humanoid");
  cov.faction = FactionComponent(FactionId::Covenant, 30);
  sim.add_agent("漂流拾荒者", cov);

  // 3. Setup Tidebound Agent (High Awareness)
  Agent tide = Agent::from_body("Humanoid");
  tide.faction = FactionComponent(FactionId::Tidebound, 80);
  tide.awareness.set_maximally_aware(); // Alert
  sim.add_agent("深淵潛者", tide);

  std::cout << "--- 初始狀態 ---\n";
  // Step 1: Check initial needs/states
  sim.step(0.1);

  std::cout << "\n--- 事件觸發: 結構斷裂 (StructuralFailure) ---\n";
  // Syndicate Ally needs help
  sim.event_bus.publish(WorldEvent(WorldEventType::StructuralFailure,
                                   Vec3(10, 0, 0), 50.0f, 101,
                                   FactionId::Syndicate));
  sim.step(0.1);

  std::cout << "\n--- 事件觸發: 魚叉攻擊 (HarpoonEvent) ---\n";
  // Covenant should swarm
  sim.event_bus.publish(
      WorldEvent(WorldEventType::HarpoonEvent, Vec3(0, 0, 0), 50.0f, 999));
  sim.step(0.1);

  std::cout << "\n--- 事件觸發: 水位傳感器 (LogicBridge) ---\n";
  // Sensor logic
  std::vector<Sensor> sensors = {
      {"WaterLevel", 1.5f, 0.5f, 999, Vec3(0, 0, 0)}};
  sim.logic_bridge.process_sensors(sensors, sim.event_bus);
  sim.step(0.1);
}

int main() {
  std::cout << "============================================\n";
  std::cout << "  Veloren-style NPC AI 系統完整實現\n";
  std::cout << "============================================\n";
  test_alignment_system();
  test_behavior_system();
  test_psyche_system();
  test_timer_system();
  test_awareness_system();
  test_pid_controller();
  test_chaser_system();
  test_action_state();
  test_rtsim_controller();
  test_agent_integration();
  void test_geopolitics_system();
  test_geopolitics_system();

  std::cout << "\n============================================\n";
  std::cout << "  所有測試完成\n";
  std::cout << "============================================\n";

  return 0;