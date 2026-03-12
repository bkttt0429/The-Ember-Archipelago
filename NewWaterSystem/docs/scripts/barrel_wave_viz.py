"""
桶浪網格算法可視化
Barrel Wave Mesh Algorithm Visualization

對比當前實現與改進算法，模擬圖三圖四的真實破碎波效果
"""

import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from matplotlib import cm

# ============================================================
# 1. 當前實現：對數螺旋 + 簡單下垂
# ============================================================

def current_algorithm(radius=5.0, arc_segments=24, spiral_tightness=0.3, lip_droop=0.4):
    """
    當前 BarrelWaveMeshGenerator.gd 的算法
    - 使用對數螺旋 exp(-spiral_tightness * a_t)
    - 唇部簡單下垂 smoothstep
    """
    a_t = np.linspace(0, 1, arc_segments)
    
    # 螺旋半徑
    spiral_radius = radius * np.exp(-spiral_tightness * a_t)
    
    # 角度範圍
    total_arc = np.pi + lip_droop
    angle = np.pi - a_t * total_arc
    
    # 外表面座標
    x = np.cos(angle) * spiral_radius
    y = np.sin(angle) * spiral_radius
    y = np.maximum(y, 0.0)  # 不低於地面
    
    # 唇部額外下垂
    extra_droop = smoothstep(0.7, 1.0, a_t) * lip_droop * radius * 0.5
    y = y - extra_droop
    
    # 厚度
    base_thickness = radius * 0.35
    lip_thickness = radius * 0.08
    thickness = np.linspace(base_thickness, lip_thickness, arc_segments)
    
    return x, y, thickness, a_t

def smoothstep(edge0, edge1, x):
    """GLSL smoothstep 函數"""
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ============================================================
# 2. 改進算法：Catenary + Bezier 唇部
# ============================================================

def improved_algorithm(radius=5.0, arc_segments=24, curl_factor=1.2, pitch_angle=0.3):
    """
    改進算法：更接近真實破碎波形態
    
    關鍵改進：
    1. 使用 Catenary (懸鏈線) 模擬水牆自然曲線
    2. 使用 Bezier 曲線模擬唇部捲曲
    3. 橫截面呈「杏仁形」而非圓形
    """
    a_t = np.linspace(0, 1, arc_segments)
    
    # === 階段 1: 底部到中段 (Catenary 曲線) ===
    # 懸鏈線參數
    catenary_a = radius * 0.6
    
    # 底部到波峰的參數 (a_t: 0 ~ 0.5)
    phase1_mask = a_t <= 0.5
    phase1_t = a_t[phase1_mask] * 2  # 正規化到 0~1
    
    # 懸鏈線：從水平向左彎曲向上到波峰
    x1 = -radius * (1 - phase1_t * 0.3)  # 從 -radius 向右移動一點
    y1 = catenary_a * np.cosh(phase1_t * 1.5) - catenary_a + radius * 0.2 * phase1_t
    
    # === 階段 2: 波峰到唇部 (Bezier 曲線) ===
    # 唇部捲曲使用三次 Bezier
    phase2_mask = a_t > 0.5
    phase2_t = (a_t[phase2_mask] - 0.5) * 2  # 正規化到 0~1
    
    # Bezier 控制點（模擬真實破碎波的唇部）
    P0 = np.array([x1[-1], y1[-1]])       # 起點：波峰
    P1 = np.array([P0[0] + radius * 0.3, P0[1] + radius * 0.1])  # 控制點1：向上向前
    P2 = np.array([P0[0] + radius * 0.6, P0[1] - radius * 0.1])  # 控制點2：開始向下
    P3 = np.array([P0[0] + radius * curl_factor, P0[1] - radius * 0.5])  # 終點：唇部下垂
    
    x2, y2 = cubic_bezier(P0, P1, P2, P3, phase2_t)
    
    # 合併兩個階段
    x = np.concatenate([x1, x2])
    y = np.concatenate([y1, y2])
    
    # 厚度：使用更真實的分佈（中間最厚）
    base_thickness = radius * 0.35
    peak_thickness = radius * 0.4  # 波峰處略厚
    lip_thickness = radius * 0.05  # 唇部更薄
    
    thickness = np.zeros_like(a_t)
    for i, t in enumerate(a_t):
        if t < 0.3:
            thickness[i] = np.interp(t, [0, 0.3], [base_thickness, peak_thickness])
        elif t < 0.6:
            thickness[i] = peak_thickness
        else:
            thickness[i] = np.interp(t, [0.6, 1.0], [peak_thickness, lip_thickness])
    
    return x, y, thickness, a_t


def cubic_bezier(P0, P1, P2, P3, t):
    """三次 Bezier 曲線"""
    t = np.atleast_1d(t)
    x = ((1-t)**3 * P0[0] + 
         3*(1-t)**2 * t * P1[0] + 
         3*(1-t) * t**2 * P2[0] + 
         t**3 * P3[0])
    y = ((1-t)**3 * P0[1] + 
         3*(1-t)**2 * t * P1[1] + 
         3*(1-t) * t**2 * P2[1] + 
         t**3 * P3[1])
    return x, y


# ============================================================
# 3. 3D 網格生成（用於可視化）
# ============================================================

def generate_3d_mesh(x_profile, y_profile, thickness, length=30.0, length_segments=8):
    """
    將 2D 橫截面延伸為 3D 網格
    沿 Z 軸（波浪方向）複製橫截面
    """
    z_values = np.linspace(-length/2, length/2, length_segments)
    
    # 外表面
    X_outer = np.tile(x_profile, (length_segments, 1))
    Y_outer = np.tile(y_profile, (length_segments, 1))
    Z_outer = np.tile(z_values.reshape(-1, 1), (1, len(x_profile)))
    
    # 內表面（使用厚度偏移）
    # 計算法線方向
    dx = np.gradient(x_profile)
    dy = np.gradient(y_profile)
    normal_x = -dy / np.sqrt(dx**2 + dy**2 + 1e-6)
    normal_y = dx / np.sqrt(dx**2 + dy**2 + 1e-6)
    
    X_inner = X_outer + np.tile(normal_x * thickness, (length_segments, 1))
    Y_inner = Y_outer + np.tile(normal_y * thickness, (length_segments, 1))
    Z_inner = Z_outer
    
    return (X_outer, Y_outer, Z_outer), (X_inner, Y_inner, Z_inner)


# ============================================================
# 4. 可視化
# ============================================================

def visualize_comparison():
    """
    創建對比圖：當前算法 vs 改進算法
    """
    fig = plt.figure(figsize=(16, 12))
    
    # 參數
    radius = 5.0
    arc_segments = 48
    length = 30.0
    
    # === 2D 橫截面對比 ===
    ax1 = fig.add_subplot(2, 2, 1)
    ax1.set_title('2D Cross-Section Comparison\n橫截面對比', fontsize=12)
    
    # 當前算法
    x_cur, y_cur, thick_cur, _ = current_algorithm(radius, arc_segments)
    ax1.plot(x_cur, y_cur, 'b-', linewidth=2, label='Current (當前)')
    ax1.fill_between(x_cur, y_cur, y_cur - thick_cur * 0.5, alpha=0.3, color='blue')
    
    # 改進算法
    x_imp, y_imp, thick_imp, _ = improved_algorithm(radius, arc_segments)
    ax1.plot(x_imp, y_imp, 'r-', linewidth=2, label='Improved (改進)')
    ax1.fill_between(x_imp, y_imp, y_imp - thick_imp * 0.5, alpha=0.3, color='red')
    
    ax1.set_xlabel('X (Forward / 前進方向)')
    ax1.set_ylabel('Y (Height / 高度)')
    ax1.legend()
    ax1.set_aspect('equal')
    ax1.grid(True, alpha=0.3)
    ax1.axhline(y=0, color='k', linestyle='--', alpha=0.5)
    
    # === 厚度分佈對比 ===
    ax2 = fig.add_subplot(2, 2, 2)
    ax2.set_title('Thickness Distribution\n厚度分佈', fontsize=12)
    
    a_t = np.linspace(0, 1, arc_segments)
    ax2.plot(a_t, thick_cur, 'b-', linewidth=2, label='Current')
    ax2.plot(a_t, thick_imp, 'r-', linewidth=2, label='Improved')
    ax2.set_xlabel('Arc Position (0=底部, 1=唇部)')
    ax2.set_ylabel('Thickness / 厚度')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # === 3D 當前算法 ===
    ax3 = fig.add_subplot(2, 2, 3, projection='3d')
    ax3.set_title('Current Algorithm 3D\n當前算法 3D', fontsize=12)
    
    outer_cur, inner_cur = generate_3d_mesh(x_cur, y_cur, thick_cur, length, 12)
    ax3.plot_surface(outer_cur[0], outer_cur[2], outer_cur[1], 
                     cmap=cm.Blues, alpha=0.7, edgecolor='none')
    ax3.set_xlabel('X')
    ax3.set_ylabel('Z (Wave Direction)')
    ax3.set_zlabel('Y (Height)')
    ax3.view_init(elev=20, azim=-60)
    
    # === 3D 改進算法 ===
    ax4 = fig.add_subplot(2, 2, 4, projection='3d')
    ax4.set_title('Improved Algorithm 3D\n改進算法 3D', fontsize=12)
    
    outer_imp, inner_imp = generate_3d_mesh(x_imp, y_imp, thick_imp, length, 12)
    ax4.plot_surface(outer_imp[0], outer_imp[2], outer_imp[1], 
                     cmap=cm.ocean, alpha=0.7, edgecolor='none')
    ax4.set_xlabel('X')
    ax4.set_ylabel('Z (Wave Direction)')
    ax4.set_zlabel('Y (Height)')
    ax4.view_init(elev=20, azim=-60)
    
    plt.tight_layout()
    
    # 保存圖片
    import os
    output_path = os.path.join(os.path.dirname(__file__), 'barrel_wave_viz.png')
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"Saved visualization to: {output_path}")
    
    plt.show()
    return output_path


if __name__ == "__main__":
    visualize_comparison()
