#include "ocean_buoyancy_sampler_3d.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>


using namespace godot;

void OceanBuoyancySampler3D::_bind_methods() {
  ClassDB::bind_method(D_METHOD("get_physics_time"),
                       &OceanBuoyancySampler3D::get_physics_time);
  ClassDB::bind_method(D_METHOD("set_physics_time", "p_time"),
                       &OceanBuoyancySampler3D::set_physics_time);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "physics_time"),
                        "set_physics_time", "get_physics_time");

  ClassDB::bind_method(D_METHOD("get_wind_strength"),
                       &OceanBuoyancySampler3D::get_wind_strength);
  ClassDB::bind_method(D_METHOD("set_wind_strength", "p_strength"),
                       &OceanBuoyancySampler3D::set_wind_strength);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "wind_strength"),
                        "set_wind_strength", "get_wind_strength");

  ClassDB::bind_method(D_METHOD("get_wind_dir"),
                       &OceanBuoyancySampler3D::get_wind_dir);
  ClassDB::bind_method(D_METHOD("set_wind_dir", "p_dir"),
                       &OceanBuoyancySampler3D::set_wind_dir);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::VECTOR2, "wind_dir"),
                        "set_wind_dir", "get_wind_dir");

  ClassDB::bind_method(D_METHOD("get_wave_length"),
                       &OceanBuoyancySampler3D::get_wave_length);
  ClassDB::bind_method(D_METHOD("set_wave_length", "p_length"),
                       &OceanBuoyancySampler3D::set_wave_length);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "wave_length"),
                        "set_wave_length", "get_wave_length");

  ClassDB::bind_method(D_METHOD("get_wave_steepness"),
                       &OceanBuoyancySampler3D::get_wave_steepness);
  ClassDB::bind_method(D_METHOD("set_wave_steepness", "p_steepness"),
                       &OceanBuoyancySampler3D::set_wave_steepness);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "wave_steepness"),
                        "set_wave_steepness", "get_wave_steepness");

  ClassDB::bind_method(D_METHOD("get_wave_chaos"),
                       &OceanBuoyancySampler3D::get_wave_chaos);
  ClassDB::bind_method(D_METHOD("set_wave_chaos", "p_chaos"),
                       &OceanBuoyancySampler3D::set_wave_chaos);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "wave_chaos"),
                        "set_wave_chaos", "get_wave_chaos");

  ClassDB::bind_method(D_METHOD("get_peak_sharpness"),
                       &OceanBuoyancySampler3D::get_peak_sharpness);
  ClassDB::bind_method(D_METHOD("set_peak_sharpness", "p_sharpness"),
                       &OceanBuoyancySampler3D::set_peak_sharpness);
  ClassDB::add_property("OceanBuoyancySampler3D",
                        PropertyInfo(Variant::FLOAT, "peak_sharpness"),
                        "set_peak_sharpness", "get_peak_sharpness");

  ClassDB::bind_method(D_METHOD("get_wave_height", "p_global_pos"),
                       &OceanBuoyancySampler3D::get_wave_height);
}

OceanBuoyancySampler3D::OceanBuoyancySampler3D() {}
OceanBuoyancySampler3D::~OceanBuoyancySampler3D() {}

void OceanBuoyancySampler3D::_process(double delta) {}

void OceanBuoyancySampler3D::set_physics_time(float p_time) {
  _physics_time = p_time;
}
float OceanBuoyancySampler3D::get_physics_time() const { return _physics_time; }

void OceanBuoyancySampler3D::set_wind_strength(float p_strength) {
  _wind_strength = p_strength;
}
float OceanBuoyancySampler3D::get_wind_strength() const {
  return _wind_strength;
}

void OceanBuoyancySampler3D::set_wind_dir(const Vector2 &p_dir) {
  _wind_dir = p_dir;
}
Vector2 OceanBuoyancySampler3D::get_wind_dir() const { return _wind_dir; }

void OceanBuoyancySampler3D::set_wave_length(float p_length) {
  _wave_length = p_length;
}
float OceanBuoyancySampler3D::get_wave_length() const { return _wave_length; }

void OceanBuoyancySampler3D::set_wave_steepness(float p_steepness) {
  _wave_steepness = p_steepness;
}
float OceanBuoyancySampler3D::get_wave_steepness() const {
  return _wave_steepness;
}

void OceanBuoyancySampler3D::set_wave_chaos(float p_chaos) {
  _wave_chaos = p_chaos;
}
float OceanBuoyancySampler3D::get_wave_chaos() const { return _wave_chaos; }

void OceanBuoyancySampler3D::set_peak_sharpness(float p_sharpness) {
  _peak_sharpness = p_sharpness;
}
float OceanBuoyancySampler3D::get_peak_sharpness() const {
  return _peak_sharpness;
}

float OceanBuoyancySampler3D::get_wave_height(
    const Vector3 &p_global_pos) const {
  float wave_data[32] = {1.0f,  1.0f, 1.0f, 0.0f, 1.3f, 0.7f, 0.8f, 1.1f,
                         0.6f,  0.9f, 1.5f, 2.4f, 0.3f, 1.2f, 2.1f, -0.6f,
                         2.1f,  0.4f, 0.6f, 4.3f, 0.8f, 0.8f, 1.3f, -1.2f,
                         0.45f, 1.0f, 1.9f, 5.2f, 1.7f, 0.3f, 0.5f, 0.7f};

  float total_relative_steepness = 0.0f;
  for (int i = 0; i < 8; i++) {
    total_relative_steepness += wave_data[i * 4 + 1];
  }

  float global_energy_scale = std::sqrt(_wave_steepness);
  float steepness_norm = 1.0f;
  if (global_energy_scale * total_relative_steepness * _wind_strength > 0.75f) {
    steepness_norm = 0.75f / (global_energy_scale * total_relative_steepness *
                              _wind_strength);
  }

  float base_angle = std::atan2(_wind_dir.y, _wind_dir.x);
  float safe_chaos = std::min(_wave_chaos, 0.3f);

  float heightmap_y_disp = 0.0f;
  const float PI = 3.14159265358979323846f;
  float t = _physics_time;

  for (int i = 0; i < 8; i++) {
    int idx = i * 4;
    float w_len = wave_data[idx] * _wave_length;

    float lod_fade = 1.0f;

    float w_steep = wave_data[idx + 1] * global_energy_scale * _wind_strength *
                    steepness_norm * lod_fade;
    float w_speed = wave_data[idx + 2];
    float w_angle = base_angle + wave_data[idx + 3] * safe_chaos;

    Vector2 d = Vector2(std::cos(w_angle), std::sin(w_angle));

    float k = 2.0f * PI / w_len;
    float c = std::sqrt(9.81f / k) * w_speed;
    float f = k * (d.dot(Vector2(p_global_pos.x, p_global_pos.z)) - c * t);
    float a = w_steep / k;

    float h = std::sin(f);
    if (_peak_sharpness != 1.0f) {
      float s = h * 0.5f + 0.5f;
      h = std::pow(std::max(s, 0.001f), _peak_sharpness) * 2.0f - 1.0f;
    }

    heightmap_y_disp += a * h;
  }

  if (_wind_strength > 0.001f) {
    float noise = std::sin(p_global_pos.x * 2.0f + t) *
                  std::cos(p_global_pos.z * 2.0f - t * 0.5f) * 0.2f;
    heightmap_y_disp += noise * _wind_strength * safe_chaos;
  }

  return heightmap_y_disp;
}
