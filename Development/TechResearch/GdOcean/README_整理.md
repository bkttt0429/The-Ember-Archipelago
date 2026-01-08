# GdOcean 文件夹整理指南

## 📁 当前状态

### 已修复
- ✅ 节点路径错误（破图问题）
- ✅ 变量遮蔽警告
- ✅ 未使用参数警告

### 待整理
- ⚠️ 构建日志文件过多（20+ 个文件）
- ⚠️ 文件组织混乱（场景、脚本、配置混在一起）

---

## 🧹 快速整理（5 分钟）

### 步骤 1：创建日志文件夹

在 `GdOcean/` 目录下创建 `build_logs/` 文件夹。

### 步骤 2：移动日志文件

手动或使用脚本移动：
- `build*.log` → `build_logs/`
- `build*.txt` → `build_logs/`
- `error*.log` → `build_logs/`

### 步骤 3：添加 .gitignore

创建 `.gitignore` 文件（已提供模板）。

---

## 📊 整理效果

### 整理前
```
GdOcean/
├── build_log.txt
├── build_log_v3.txt
├── build_log_v5.txt
├── build_log_v6.txt
├── build_log_v8.txt
├── build_log_final.txt
├── build_log_cleanup.txt
├── build_log_safe.txt
├── build_final.log
├── build_final_2.log
├── build_error.log
├── error_v4.log
├── error.txt
├── build.log
├── build_v2.log
├── HybridOceanTest.tscn
├── OceanTest.gd
├── gd_ocean.gdextension
└── ... (20+ 个文件混在一起)
```

### 整理后
```
GdOcean/
├── src/                    # C++ 源代码
├── godot-cpp/              # 绑定库
├── Scenes/                  # 场景文件
│   ├── HybridOceanTest.tscn
│   └── OceanDemoScene.tscn
├── Scripts/                 # 脚本
│   └── OceanTest.gd
├── Config/                  # 配置
│   ├── gd_ocean.gdextension
│   └── SConstruct
├── build_logs/              # 构建日志（集中）
│   └── (所有日志文件)
├── Docs/                    # 文档
│   └── README.md
└── .gitignore              # Git 忽略规则
```

---

## 🎯 整理优先级

### 高优先级（立即执行）
1. ✅ **修复破图问题** - 已完成
2. ⚠️ **清理构建日志** - 建议执行
3. ⚠️ **添加 .gitignore** - 建议执行

### 中优先级（可选）
4. 📁 **重组文件夹结构** - 如果时间允许
5. 📝 **更新文档** - 如果重组了结构

---

## 📝 注意事项

1. **不要删除重要文件**
   - `src/` - 源代码
   - `godot-cpp/` - 绑定库
   - `*.tscn`, `*.gd` - 场景和脚本
   - `*.gdextension` - 扩展配置

2. **移动文件后更新路径**
   - 如果移动了场景文件，检查脚本路径
   - 如果移动了配置文件，检查引用

3. **备份重要文件**
   - 整理前建议备份整个文件夹

---

**整理指南创建时间**：2024
