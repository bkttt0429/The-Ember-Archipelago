"""
破碎波時間演化網格模擬
Breaking Wave Time Evolution Mesh Simulation

模擬參考圖：Breaking sea waves profiles
- 多條輪廓線代表不同時間步
- 波浪從深水區向淺水區傳播
- 強曲率區域形成捲曲（桶浪）
"""

import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from matplotlib import cm
import matplotlib.colors as mcolors

# ============================================================
# 1. 物理模型：淺水波破碎演化
# ============================================================


def solitary_wave_profile(x, amplitude, x0, width):
    """
    孤立波初始輪廓（sech² 分佈）
    用於模擬深水波向淺水區傳播
    """
    return amplitude * (1.0 / np.cosh((x - x0) / width)) ** 2


def _cubic_bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (
        (u * u * u) * p0
        + (3 * u * u * t) * p1
        + (3 * u * t * t) * p2
        + (t * t * t) * p3
    )


def breaking_wave_profile(x, t, params):
    """
    破碎波輪廓生成

    基於簡化的淺水波方程 + 經驗性破碎模型

    參數：
    - x: 水平座標陣列
    - t: 時間參數 (0 = 初始, 1 = 完全破碎)
    - params: 波浪參數字典
    """
    amp = params["amplitude"]
    x0 = params["x0"]
    width = params["width"]
    bottom_slope = params["bottom_slope"]
    curl_factor = params["curl_factor"]

    # 基礎孤立波
    z_base = solitary_wave_profile(x, amp, x0, width)

    # 淺化效應：隨著 t 增加，波峰變陡
    # 模擬：波速 = sqrt(gh)，淺處慢，深處快 → 波峰追上波谷
    shoaling_factor = 1.0 + t * 0.8  # 波高增加
    steepening = t * 1.5  # 前傾程度

    # 波峰位置隨時間前移
    peak_shift = -t * width * 0.3

    # 非對稱變形：前傾
    asymmetry = np.zeros_like(x)
    mask = x > (x0 + peak_shift)
    asymmetry[mask] = -steepening * (x[mask] - (x0 + peak_shift)) ** 2 / (width**2)

    z = z_base * shoaling_factor + asymmetry * amp
    z = np.maximum(z, 0)  # 不低於水面

    # === 破碎捲曲 (t > 0.4 時開始) ===
    if t > 0.4:
        curl_t = (t - 0.4) / 0.6
        curl_t = max(0.0, min(curl_t, 1.0))

        # 波峰區域
        peak_region = np.abs(x - (x0 + peak_shift)) < width * 0.5
        peak_indices = np.where(peak_region)[0]

        if len(peak_indices) > 0:
            peak_idx = peak_indices[len(peak_indices) // 2]
            curl_start = peak_idx
            curl_span = int(len(x) * 0.3)
            curl_end = min(peak_idx + curl_span, len(x) - 1)
            curl_length = curl_end - curl_start

            if curl_length > 2:
                peak_x = x[peak_idx]
                peak_z = z[peak_idx]

                forward = width * (0.8 + 0.4 * curl_t)
                drop = amp * (0.6 + 0.8 * curl_t)
                lift = amp * 0.15 * (1.0 - curl_t)

                p0 = np.array([peak_x, peak_z])
                p1 = np.array([peak_x + forward * 0.25, peak_z + lift])
                p2 = np.array([peak_x + forward * 0.7, peak_z - drop * 0.5])
                p3 = np.array([peak_x + forward, peak_z - drop])

                for i in range(curl_length):
                    s = i / max(curl_length - 1, 1)
                    bez = _cubic_bezier(p0, p1, p2, p3, s)
                    idx = curl_start + i
                    x[idx] = bez[0]
                    z[idx] = max(bez[1], 0.0)

    return x.copy(), z


def generate_breaking_sequence(num_profiles=12):
    """
    生成破碎波時間序列
    類似參考圖的多條輪廓線
    """
    # 參數設定
    params = {
        "amplitude": 0.6,  # 初始波高 (米)
        "x0": -1.5,  # 初始波峰位置
        "width": 0.8,  # 波寬
        "bottom_slope": 0.1,  # 海底坡度
        "curl_factor": 1.2,  # 捲曲強度
    }

    # 水平座標
    x_base = np.linspace(-3.0, 1.0, 200)

    profiles = []
    time_steps = np.linspace(0, 1.0, num_profiles)

    for i, t in enumerate(time_steps):
        x = x_base.copy()

        # 更新波峰位置（向岸傳播）
        params_t = params.copy()
        params_t["x0"] = params["x0"] + t * 1.0  # 向右移動
        params_t["amplitude"] = params["amplitude"] * (1 + t * 0.5)  # 淺化增高

        x_profile, z_profile = breaking_wave_profile(x, t, params_t)
        profiles.append((x_profile, z_profile, t))

    return profiles


# ============================================================
# 2. 3D 網格生成
# ============================================================


def generate_3d_wave_mesh(profiles, y_extent=2.0):
    """
    將 2D 輪廓序列延伸為 3D 網格
    沿 Y 軸（波浪延伸方向）複製
    """
    num_profiles = len(profiles)
    num_points = len(profiles[0][0])

    # 創建 3D 網格
    X = np.zeros((num_profiles, num_points))
    Y = np.zeros((num_profiles, num_points))
    Z = np.zeros((num_profiles, num_points))
    T = np.zeros((num_profiles, num_points))  # 用於著色

    y_values = np.linspace(-y_extent / 2, y_extent / 2, num_profiles)

    for i, (x_prof, z_prof, t) in enumerate(profiles):
        X[i, :] = x_prof
        Y[i, :] = y_values[i]
        Z[i, :] = z_prof
        T[i, :] = t  # 時間參數用於顏色

    return X, Y, Z, T


# ============================================================
# 3. 可視化
# ============================================================


def visualize_breaking_wave():
    """
    可視化破碎波演化
    包含 2D 輪廓序列和 3D 網格視圖
    """
    fig = plt.figure(figsize=(16, 8))

    # === 生成數據 ===
    profiles = generate_breaking_sequence(num_profiles=15)

    # === 左圖：2D 輪廓序列（模擬參考圖） ===
    ax1 = fig.add_subplot(1, 2, 1)
    ax1.set_title("Breaking Sea Waves Profiles\n破碎波輪廓演化", fontsize=14)

    # 繪製每條輪廓
    for i, (x, z, t) in enumerate(profiles):
        if i == 0 or i == len(profiles) - 1:
            # 首尾用紅色
            ax1.plot(x, z, "r-", linewidth=1.5, alpha=0.9)
        else:
            # 中間用藍色
            ax1.plot(x, z, "b-", linewidth=1.0, alpha=0.7)

    # 標註強曲率區域
    ax1.annotate(
        "strong curvature",
        xy=(0.0, 0.5),
        xytext=(0.5, 0.7),
        fontsize=10,
        arrowprops=dict(arrowstyle="->", color="black"),
    )

    # 海底線
    ax1.axhline(y=0, color="brown", linestyle="-", linewidth=2, alpha=0.5)
    ax1.fill_between([-3, 1], [-0.1, -0.1], [0, 0], color="brown", alpha=0.2)

    ax1.set_xlabel("x (m)", fontsize=12)
    ax1.set_ylabel("z (m)", fontsize=12)
    ax1.set_xlim(-3, 1)
    ax1.set_ylim(-0.1, 1.0)
    ax1.set_aspect("equal")
    ax1.grid(True, alpha=0.3)

    # === 右圖：3D 網格視圖 ===
    ax2 = fig.add_subplot(1, 2, 2, projection="3d")
    ax2.set_title("3D Wave Mesh\n3D 波浪網格", fontsize=14)

    X, Y, Z, T = generate_3d_wave_mesh(profiles, y_extent=3.0)

    # 使用時間參數著色
    colors = cm.get_cmap("ocean")((1 - T) * 0.8 + 0.1)

    # 繪製表面
    surf = ax2.plot_surface(
        X,
        Y,
        Z,
        facecolors=colors,
        edgecolor="navy",
        linewidth=0.3,
        alpha=0.85,
        shade=True,
    )

    # 繪製線框強調
    for i in range(0, len(profiles), 3):
        ax2.plot(X[i, :], Y[i, :], Z[i, :], "b-", linewidth=0.8, alpha=0.5)

    ax2.set_xlabel("X (m)")
    ax2.set_ylabel("Y (沿波浪方向)")
    ax2.set_zlabel("Z (高度)")
    ax2.view_init(elev=25, azim=-45)

    plt.tight_layout()

    # 保存
    import os

    output_path = os.path.join(os.path.dirname(__file__), "breaking_wave_mesh.png")
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {output_path}")

    plt.show()
    return output_path


# ============================================================
# 4. 額外：波浪破碎動畫幀生成
# ============================================================


def generate_animation_frames(output_dir=None, num_frames=30):
    """
    生成破碎波動畫幀序列
    可用於後續 GIF 或視頻製作
    """
    import os

    if output_dir is None:
        output_dir = os.path.join(os.path.dirname(__file__), "wave_frames")

    os.makedirs(output_dir, exist_ok=True)

    params = {
        "amplitude": 0.6,
        "x0": -2.0,
        "width": 0.8,
        "bottom_slope": 0.1,
        "curl_factor": 1.5,
    }

    x_base = np.linspace(-3.0, 1.0, 200)

    for frame in range(num_frames):
        t = frame / (num_frames - 1)

        fig, ax = plt.subplots(figsize=(10, 6))

        # 當前時間步
        params_t = params.copy()
        params_t["x0"] = params["x0"] + t * 1.5
        params_t["amplitude"] = params["amplitude"] * (1 + t * 0.6)

        x = x_base.copy()
        x_prof, z_prof = breaking_wave_profile(x, t, params_t)

        # 繪製
        ax.fill_between(x_prof, 0, z_prof, color="deepskyblue", alpha=0.6)
        ax.plot(x_prof, z_prof, "b-", linewidth=2)

        # 海底
        ax.axhline(y=0, color="brown", linewidth=2)
        ax.fill_between([-3, 1], [-0.15, -0.15], [0, 0], color="sandybrown", alpha=0.5)

        ax.set_xlim(-3, 1)
        ax.set_ylim(-0.15, 1.2)
        ax.set_aspect("equal")
        ax.set_title(f"Breaking Wave - t = {t:.2f}", fontsize=14)
        ax.set_xlabel("x (m)")
        ax.set_ylabel("z (m)")

        frame_path = os.path.join(output_dir, f"frame_{frame:03d}.png")
        plt.savefig(frame_path, dpi=100, bbox_inches="tight")
        plt.close(fig)

        print(f"Generated: {frame_path}")

    print(f"\nAnimation frames saved to: {output_dir}")
    return output_dir


if __name__ == "__main__":
    visualize_breaking_wave()
    # 可選：生成動畫幀
    # generate_animation_frames()
