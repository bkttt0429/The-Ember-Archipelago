"""
Mega Tsunami - Tube perfectly aligned with wave crest
First column of tube = exact wave surface coordinates
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider
from mpl_toolkits.mplot3d import Axes3D
import matplotlib.colors as mcolors

NX, NY = 50, 35
DOMAIN_X, DOMAIN_Y = 10000, 5000
WAVE_HEIGHT, WATER_DEPTH = 400.0, 150.0


def create_barrel_wave():
    x = np.linspace(0, DOMAIN_X, NX)
    y = np.linspace(0, DOMAIN_Y, NY)
    X, Y = np.meshgrid(x, y)
    X_km, Y_km = X / 1000, Y / 1000
    dx = x[1] - x[0]
    
    wave_cmap = mcolors.LinearSegmentedColormap.from_list('wave', [
        (0.0, '#001a33'), (0.4, '#0077bb'), (0.7, '#44aadd'), (1.0, '#ffffff')])
    tube_cmap = mcolors.LinearSegmentedColormap.from_list('tube', [
        (0.0, '#003344'), (0.5, '#0099bb'), (1.0, '#55ddff')])
    inner_cmap = mcolors.LinearSegmentedColormap.from_list('inner', [
        (0.0, '#001122'), (0.5, '#005577'), (1.0, '#0088aa')])
    
    def compute(peak_x, peak_y, curl_deg, arc_size_pct):
        cx, cy = peak_x * 1000, peak_y * 1000
        A, h = WAVE_HEIGHT, WATER_DEPTH
        sigma_y, wave_w = DOMAIN_Y * 0.38, 1800
        
        crest_j = np.argmin(np.abs(x - cx))
        
        # Main wave
        Z = np.zeros_like(X)
        for i in range(NY):
            for j in range(NX):
                wave_dx = X[i,j] - cx
                dy = (Y[i,j] - cy) / sigma_y
                lat = np.exp(-dy**2)
                ht = A * np.exp(-(wave_dx / (wave_w * (0.4 if wave_dx < 0 else 0.65)))**2)
                tr = -0.08 * A * np.exp(-((X[i,j] - cx - wave_w) / (wave_w * 1.2))**2)
                Z[i,j] = (ht + tr) * lat + h
        
        # === TUBE: First column matches wave exactly ===
        n_path = 40
        extend_distance = A * 1.2 * (arc_size_pct / 100)
        curl_rad = np.radians(curl_deg)
        tube_thickness = A * 0.35
        
        tube_X_outer = np.zeros((NY, n_path))
        tube_Y_outer = np.zeros((NY, n_path))
        tube_Z_outer = np.zeros((NY, n_path))
        
        tube_X_inner = np.zeros((NY, n_path))
        tube_Y_inner = np.zeros((NY, n_path))
        tube_Z_inner = np.zeros((NY, n_path))
        
        for i in range(NY):
            # === EXACT wave surface coordinates at crest ===
            wave_x_start = X[i, crest_j]
            wave_y_start = Y[i, crest_j]
            wave_z_start = Z[i, crest_j]
            
            dy_norm = (wave_y_start - cy) / sigma_y
            lat = max(0.05, np.exp(-dy_norm**2))
            
            local_extend = extend_distance * lat
            local_thick = tube_thickness * lat
            
            # Slope at crest (dZ/dX)
            if crest_j + 1 < NX and crest_j > 0:
                slope_z = (Z[i, crest_j + 1] - Z[i, crest_j - 1]) / (2 * dx)
            else:
                slope_z = 0
            
            # Initial tangent (following wave slope)
            init_tang_x = 1.0
            init_tang_z = slope_z
            init_len = np.sqrt(init_tang_x**2 + init_tang_z**2)
            init_tang_x /= init_len
            init_tang_z /= init_len
            
            # Initial normal (perpendicular to wave surface, pointing outward/up)
            init_norm_x = -init_tang_z
            init_norm_z = init_tang_x
            
            # End direction
            end_tang_x = np.sin(curl_rad)
            end_tang_z = -np.cos(curl_rad)
            
            # Build path by integration
            path_x = [wave_x_start]
            path_z = [wave_z_start]
            path_tang_x = [init_tang_x]
            path_tang_z = [init_tang_z]
            
            step = local_extend / (n_path - 1)
            curr_x = wave_x_start
            curr_z = wave_z_start
            
            for si in range(1, n_path):
                s = si / (n_path - 1)
                ease = 3*s*s - 2*s*s*s
                
                tang_x = init_tang_x * (1 - ease) + end_tang_x * ease
                tang_z = init_tang_z * (1 - ease) + end_tang_z * ease
                tlen = np.sqrt(tang_x**2 + tang_z**2) + 1e-6
                tang_x /= tlen
                tang_z /= tlen
                
                curr_x += tang_x * step
                curr_z += tang_z * step
                
                path_x.append(curr_x)
                path_z.append(curr_z)
                path_tang_x.append(tang_x)
                path_tang_z.append(tang_z)
            
            # Build surfaces
            for si in range(n_path):
                s = si / (n_path - 1)
                
                spine_x = path_x[si]
                spine_z = path_z[si]
                tang_x = path_tang_x[si]
                tang_z = path_tang_z[si]
                
                # Normal
                norm_x = -tang_z
                norm_z = tang_x
                
                taper = 1 - 0.2 * s
                thick_local = local_thick * taper
                
                # === INNER: exactly on spine (wave surface at start) ===
                tube_X_inner[i, si] = spine_x / 1000
                tube_Y_inner[i, si] = wave_y_start / 1000
                tube_Z_inner[i, si] = max(spine_z, h + 2)
                
                # === OUTER: offset by thickness in normal direction ===
                tube_X_outer[i, si] = (spine_x + norm_x * thick_local) / 1000
                tube_Y_outer[i, si] = wave_y_start / 1000
                tube_Z_outer[i, si] = max(spine_z + norm_z * thick_local, h + 2)
        
        # Verify first column matches wave
        for i in range(NY):
            tube_X_inner[i, 0] = X[i, crest_j] / 1000
            tube_Y_inner[i, 0] = Y[i, crest_j] / 1000
            tube_Z_inner[i, 0] = Z[i, crest_j]
        
        return Z, tube_X_outer, tube_Y_outer, tube_Z_outer, tube_X_inner, tube_Y_inner, tube_Z_inner, crest_j
    
    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_subplot(111, projection='3d')
    plt.subplots_adjust(bottom=0.28)
    
    ax_px = plt.axes([0.2, 0.18, 0.6, 0.025])
    ax_py = plt.axes([0.2, 0.13, 0.6, 0.025])
    ax_curl = plt.axes([0.2, 0.08, 0.6, 0.025])
    ax_arc = plt.axes([0.2, 0.03, 0.6, 0.025])
    
    sl_px = Slider(ax_px, 'Peak X', 2, 8, valinit=5.0, valstep=0.2, color='#3399ff')
    sl_py = Slider(ax_py, 'Peak Y', 1, 4, valinit=2.5, valstep=0.2, color='#33cc99')
    sl_curl = Slider(ax_curl, 'Curl °', 30, 150, valinit=90, valstep=5, color='#ff6666')
    sl_arc = Slider(ax_arc, 'Arc Size %', 50, 200, valinit=120, valstep=10, color='#00aa00')
    
    def update(val):
        ax.clear()
        Z, tX_out, tY_out, tZ_out, tX_in, tY_in, tZ_in, cj = compute(
            sl_px.val, sl_py.val, sl_curl.val, sl_arc.val)
        
        # Wave
        Zn = (Z - Z.min()) / (Z.max() - Z.min() + 0.01)
        ax.plot_surface(X_km, Y_km, Z, facecolors=wave_cmap(Zn),
                       edgecolor='#003355', linewidth=0.1, alpha=0.9)
        
        # Tube outer
        tZn_out = (tZ_out - tZ_out.min()) / (tZ_out.max() - tZ_out.min() + 0.01)
        ax.plot_surface(tX_out, tY_out, tZ_out, facecolors=tube_cmap(tZn_out),
                       edgecolor='#00aacc', linewidth=0.3, alpha=0.92)
        
        # Tube inner
        tZn_in = (tZ_in - tZ_in.min()) / (tZ_in.max() - tZ_in.min() + 0.01)
        ax.plot_surface(tX_in, tY_in, tZ_in, facecolors=inner_cmap(tZn_in),
                       edgecolor='#004455', linewidth=0.25, alpha=0.88)
        
        # Crest line
        ax.plot(X_km[:, cj], Y_km[:, cj], Z[:, cj] + 3, 'lime', lw=3, label='Crest')
        
        ax.set_xlim(0, 10); ax.set_ylim(0, 5); ax.set_zlim(0, 700)
        ax.set_xlabel('X (km)'); ax.set_ylabel('Y (km)'); ax.set_zlabel('Z (m)')
        ax.view_init(elev=22, azim=-55)
        ax.set_title(f'Barrel Wave - Perfect Alignment\n'
                    f'Curl: {sl_curl.val:.0f}° | Arc Size: {sl_arc.val:.0f}%')
        ax.legend(loc='upper left')
        fig.canvas.draw_idle()
    
    for s in [sl_px, sl_py, sl_curl, sl_arc]:
        s.on_changed(update)
    
    update(None)
    print("✓ Tube first column = exact wave surface coordinates")
    plt.show()


if __name__ == "__main__":
    create_barrel_wave()
