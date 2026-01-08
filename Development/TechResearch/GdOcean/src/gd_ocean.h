#ifndef GD_OCEAN_H
#define GD_OCEAN_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/node_path.hpp>

#include <vector>
#include <complex>

namespace gd_ocean {

class OceanWaveGenerator : public godot::Node {
    GDCLASS(OceanWaveGenerator, godot::Node)

private:
    double time;
    int resolution = 64; 
    double size = 64.0;
    
    // FFT Data - Using double for precision in calculation
    std::vector<std::complex<double>> h0_k; 
    std::vector<std::complex<double>> h_k_t;
    std::vector<std::complex<double>> butterfly_data;
    std::vector<double> height_map;

    void init_spectrum();
    void perform_fft(std::vector<std::complex<double>>& data, int n);
    void bit_reverse_copy(const std::vector<std::complex<double>>& src, std::vector<std::complex<double>>& dst, int n);
    unsigned int reverse_bits(unsigned int num, int log2n);

protected:
    static void _bind_methods();

public:
    OceanWaveGenerator();
    ~OceanWaveGenerator();

    void _process(double delta) override;
    
    // API
    float get_wave_height(float x, float z);
};

class BuoyancyProbe3D : public godot::RigidBody3D {
    GDCLASS(BuoyancyProbe3D, godot::RigidBody3D)

private:
    float buoyancy_force;
    float water_drag;
    godot::NodePath ocean_node_path;
    OceanWaveGenerator* ocean_node;

protected:
    static void _bind_methods();

public:
    BuoyancyProbe3D();
    ~BuoyancyProbe3D();

    void _ready() override;
    void _physics_process(double delta) override;

    void set_buoyancy_force(float p_force);
    float get_buoyancy_force() const;

    void set_water_drag(float p_drag);
    float get_water_drag() const;

    void set_ocean_node(const godot::NodePath& p_path);
    godot::NodePath get_ocean_node() const;
};

}

#endif
