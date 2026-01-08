# GdOcean: GDExtension for High-Performance Ocean Physics

This directory contains the C++ source code for the ocean physics system.

## Structure
- `src/`: C++ Source files
    - `gd_ocean.h/cpp`: The main logic class `OceanWaveGenerator`.
    - `register_types.cpp`: GDExtension entry point.
- `godot-cpp/`: The Godot C++ Bindings (Submodule).
- `SConstruct`: The build script logic.

## How to Build
1.  **First Time Only**: Compile the godot-cpp bindings.
    ```bash
    cd godot-cpp
    scons platform=windows target=template_debug
    cd ..
    ```
2.  **Build GdOcean Library**:
    ```bash
    scons
    ```

3.  **Result**:
    - The compiled library will be in `bin/gd_ocean.windows.template_debug.x86_64.dll` (or similar).
    - You need to create a `.gdextension` resource file in Godot to load this DLL.
