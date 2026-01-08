#include "gd_ocean.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <gdextension_interface.h>

using namespace godot;

void initialize_gd_ocean_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    ClassDB::register_class<gd_ocean::OceanWaveGenerator>();
    ClassDB::register_class<gd_ocean::BuoyancyProbe3D>();
}

void uninitialize_gd_ocean_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT gd_ocean_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_gd_ocean_module);
    init_obj.register_terminator(uninitialize_gd_ocean_module);

    return init_obj.init();
}
}
