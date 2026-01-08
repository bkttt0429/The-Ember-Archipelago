#include "gd_ocean.h"
#include <algorithm>
#include <cmath>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using namespace gd_ocean;

// --- OceanWaveGenerator ---

void OceanWaveGenerator::_bind_methods() {
  ClassDB::bind_method(D_METHOD("get_wave_height", "x", "z"),
                       &OceanWaveGenerator::get_wave_height);
}

OceanWaveGenerator::OceanWaveGenerator() {
  time = 0.0;
  resolution = 64;
  size = 64.0;
  init_spectrum();
  set_process(true);
}

OceanWaveGenerator::~OceanWaveGenerator() {}

float OceanWaveGenerator::get_wave_height(float x, float z) {
  // Bilinear interpolation from height_map
  // Map world (x, z) to grid (u, v)
  // Assume grid covers 0..size

  double u = std::fmod(x, size);
  double v = std::fmod(z, size);
  if (u < 0)
    u += size;
  if (v < 0)
    v += size;

  double grid_x = (u / size) * resolution;
  double grid_z = (v / size) * resolution;

  int x0 = (int)grid_x % resolution;
  int z0 = (int)grid_z % resolution;
  int x1 = (x0 + 1) % resolution;
  int z1 = (z0 + 1) % resolution;

  double frac_x = grid_x - (int)grid_x;
  double frac_z = grid_z - (int)grid_z;

  double h00 = height_map[z0 * resolution + x0];
  double h10 = height_map[z0 * resolution + x1];
  double h01 = height_map[z1 * resolution + x0];
  double h11 = height_map[z1 * resolution + x1];

  double h_interp = (1 - frac_x) * (1 - frac_z) * h00 +
                    frac_x * (1 - frac_z) * h10 + (1 - frac_x) * frac_z * h01 +
                    frac_x * frac_z * h11;

  // Scale height for visualization
  return (float)(h_interp * 10.0);
}

// FFT Helpers
unsigned int OceanWaveGenerator::reverse_bits(unsigned int num, int log2n) {
  unsigned int reversed = 0;
  for (int i = 0; i < log2n; ++i) {
    if (num & (1 << i)) {
      reversed |= 1 << (log2n - 1 - i);
    }
  }
  return reversed;
}

void OceanWaveGenerator::bit_reverse_copy(
    const std::vector<std::complex<double>> &src,
    std::vector<std::complex<double>> &dst, int n) {
  int log2n = 0;
  while ((1 << log2n) < n)
    log2n++;

  for (int i = 0; i < n; ++i) {
    dst[reverse_bits(i, log2n)] = src[i];
  }
}

void OceanWaveGenerator::perform_fft(std::vector<std::complex<double>> &data,
                                     int n) {
  // Basic Cooley-Tukey
  int log2n = 0;
  while ((1 << log2n) < n)
    log2n++;

  std::vector<std::complex<double>> temp(n);
  bit_reverse_copy(data, temp, n);
  data = temp;

  const double PI = 3.14159265358979323846;
  for (int s = 1; s <= log2n; ++s) {
    int m = 1 << s;
    int m2 = m >> 1;
    std::complex<double> wm =
        std::exp(std::complex<double>(0, -2.0 * PI / m)); // Forward FFT uses -i

    for (int k = 0; k < n; k += m) {
      std::complex<double> w = 1.0;
      for (int j = 0; j < m2; ++j) {
        std::complex<double> t = w * data[k + j + m2];
        std::complex<double> u = data[k + j];
        data[k + j] = u + t;
        data[k + j + m2] = u - t;
        w *= wm;
      }
    }
  }
}

// Helper to get consistent test spectrum
std::complex<double> get_test_h0(int kx, int kz, int n) {
  // Aliasing handling: kx in [0, n/2] -> kx, [n/2+1, n-1] -> kx - n
  int real_kx = (kx <= n / 2) ? kx : kx - n;
  int real_kz = (kz <= n / 2) ? kz : kz - n;

  // Simple reproducible test case: 2 main waves
  if (real_kx == 1 && real_kz == 1)
    return std::complex<double>(10.0, 0.0);
  if (real_kx == 2 && real_kz == 0)
    return std::complex<double>(5.0, 5.0);
  return std::complex<double>(0.0, 0.0);
}

void OceanWaveGenerator::_process(double delta) {
  // Debug: Print every frame? No, spam.
  // printf/print?
  static double print_timer = 0.0;
  print_timer += delta;
  if (print_timer > 1.0) {
    UtilityFunctions::print("CPP Ocean Update. Time: ", time);
    print_timer = 0.0;
  }

  if (Engine::get_singleton()->is_editor_hint())
    return;

  time += delta;

  const double PI = 3.14159265358979323846;
  const double G = 9.81;
  double L = size; // Physical size (e.g. 64 meters)

  // 1. Update Phase and H(k, t)
  for (int z = 0; z < resolution; ++z) {
    for (int x = 0; x < resolution; ++x) {
      int kx_idx = (x <= resolution / 2) ? x : x - resolution;
      int kz_idx = (z <= resolution / 2) ? z : z - resolution;

      double kx = 2.0 * PI * kx_idx / L;
      double kz = 2.0 * PI * kz_idx / L;
      double k_len = std::sqrt(kx * kx + kz * kz);

      if (k_len < 0.0001) {
        h_k_t[z * resolution + x] = std::complex<double>(0, 0);
        continue;
      }

      // Dispersion: w = sqrt(g * k)
      double w = std::sqrt(G * k_len);
      double phase = w * time;

      std::complex<double> h0 = h0_k[z * resolution + x];

      // Euler: exp(i * phase)
      std::complex<double> exp_phase = std::exp(std::complex<double>(0, phase));

      h_k_t[z * resolution + x] = h0 * exp_phase;
    }
  }

  // IFFT
  // 1. Row FFT
  std::vector<std::complex<double>> row_data(resolution);
  for (int y = 0; y < resolution; ++y) {
    for (int x = 0; x < resolution; ++x) {
      row_data[x] = h_k_t[y * resolution + x];
    }
    perform_fft(row_data, resolution);
    for (int x = 0; x < resolution; ++x) {
      h_k_t[y * resolution + x] = row_data[x];
    }
  }

  // 2. Col FFT
  std::vector<std::complex<double>> col_data(resolution);
  for (int x = 0; x < resolution; ++x) {
    for (int y = 0; y < resolution; ++y) {
      col_data[y] = h_k_t[y * resolution + x];
    }
    perform_fft(col_data, resolution);
    for (int y = 0; y < resolution; ++y) {
      // Sign flip for IFFT usually handled by conjugate or standard alg,
      // here our perform_fft is forward. For IFFT we can reverse or swap.
      // Simplified: Just use the output magnitude/real scaling for now.
      // A basic property of FFT/IFFT difference is scaling 1/N.
      // We will just scale output to look good.
      height_map[y * resolution + x] = col_data[y].real() *
                                       (1.0 / (resolution * resolution)) *
                                       100.0; // Arbitrary scale for visibility
    }
  }
}

// ... (get_wave_height, helpers remain same) ...

void OceanWaveGenerator::init_spectrum() {
  int total = resolution * resolution;
  h0_k.resize(total);
  h_k_t.resize(total);
  height_map.resize(total);

  for (int z = 0; z < resolution; ++z) {
    for (int x = 0; x < resolution; ++x) {
      h0_k[z * resolution + x] = get_test_h0(x, z, resolution);
    }
  }
}

// --- BuoyancyProbe3D ---

void BuoyancyProbe3D::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_buoyancy_force", "force"),
                       &BuoyancyProbe3D::set_buoyancy_force);
  ClassDB::bind_method(D_METHOD("get_buoyancy_force"),
                       &BuoyancyProbe3D::get_buoyancy_force);
  ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "buoyancy_force"),
               "set_buoyancy_force", "get_buoyancy_force");

  ClassDB::bind_method(D_METHOD("set_water_drag", "drag"),
                       &BuoyancyProbe3D::set_water_drag);
  ClassDB::bind_method(D_METHOD("get_water_drag"),
                       &BuoyancyProbe3D::get_water_drag);
  ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "water_drag"), "set_water_drag",
               "get_water_drag");

  ClassDB::bind_method(D_METHOD("set_ocean_node", "node_path"),
                       &BuoyancyProbe3D::set_ocean_node);
  ClassDB::bind_method(D_METHOD("get_ocean_node"),
                       &BuoyancyProbe3D::get_ocean_node);
  ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "ocean_node"), "set_ocean_node",
               "get_ocean_node");
}

BuoyancyProbe3D::BuoyancyProbe3D() {
  buoyancy_force = 10.0f;
  water_drag = 0.5f;
  ocean_node = nullptr;
  set_physics_process(true);
}

BuoyancyProbe3D::~BuoyancyProbe3D() {}

void BuoyancyProbe3D::_ready() {
  if (!ocean_node_path.is_empty()) {
    ocean_node = Object::cast_to<OceanWaveGenerator>(
        get_node<godot::Node>(ocean_node_path));
  }
}

void BuoyancyProbe3D::_physics_process(double delta) {
  if (ocean_node) {
    Vector3 global_pos = get_global_position();
    float wave_height =
        ocean_node->get_wave_height((float)global_pos.x, (float)global_pos.z);

    if (global_pos.y < wave_height) {
      float depth = wave_height - (float)global_pos.y;
      Vector3 up_force = Vector3(0, 1, 0) * (buoyancy_force * depth);

      // Apply drag
      Vector3 velocity = get_linear_velocity();
      Vector3 drag_force = -velocity * water_drag * depth;

      apply_central_force(up_force + drag_force);
    }
  }
}

void BuoyancyProbe3D::set_buoyancy_force(float p_force) {
  buoyancy_force = p_force;
}

float BuoyancyProbe3D::get_buoyancy_force() const { return buoyancy_force; }

void BuoyancyProbe3D::set_water_drag(float p_drag) { water_drag = p_drag; }

float BuoyancyProbe3D::get_water_drag() const { return water_drag; }

void BuoyancyProbe3D::set_ocean_node(const NodePath &p_path) {
  ocean_node_path = p_path;
  if (is_inside_tree()) {
    ocean_node =
        Object::cast_to<OceanWaveGenerator>(get_node<godot::Node>(p_path));
  }
}

NodePath BuoyancyProbe3D::get_ocean_node() const { return ocean_node_path; }
