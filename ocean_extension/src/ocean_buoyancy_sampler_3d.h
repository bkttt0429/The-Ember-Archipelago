#ifndef OCEAN_BUOYANCY_SAMPLER_3D_H
#define OCEAN_BUOYANCY_SAMPLER_3D_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class OceanBuoyancySampler3D : public Node3D {
  GDCLASS(OceanBuoyancySampler3D, Node3D)

private:
  float _physics_time = 0.0f;

  // Wave Parameters
  float _wind_strength = 1.0f;
  Vector2 _wind_dir = Vector2(1.0f, 0.0f);
  float _wave_length = 50.0f;
  float _wave_steepness = 0.5f;
  float _wave_chaos = 0.5f;
  float _peak_sharpness = 1.0f;

protected:
  static void _bind_methods();

public:
  OceanBuoyancySampler3D();
  ~OceanBuoyancySampler3D();

  void set_physics_time(float p_time);
  float get_physics_time() const;

  void set_wind_strength(float p_strength);
  float get_wind_strength() const;

  void set_wind_dir(const Vector2 &p_dir);
  Vector2 get_wind_dir() const;

  void set_wave_length(float p_length);
  float get_wave_length() const;

  void set_wave_steepness(float p_steepness);
  float get_wave_steepness() const;

  void set_wave_chaos(float p_chaos);
  float get_wave_chaos() const;

  void set_peak_sharpness(float p_sharpness);
  float get_peak_sharpness() const;

  float get_wave_height(const Vector3 &p_global_pos) const;

  void _process(double delta) override;
};

} // namespace godot

#endif
