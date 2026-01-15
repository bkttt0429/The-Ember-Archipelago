#pragma once

#include "Utils.h"
#include <array>
#include <functional>
#include <optional>


namespace NPCSystem {

// PID 控制器模板 (原本在 NPCAISYSTEM.cpp 12 部分)
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

} // namespace NPCSystem
