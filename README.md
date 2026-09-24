# CUSGA

CUSGA 是一个基于 **Godot 4.7.1 + GDScript** 的 2D 游戏项目，当前包含地图探索、地形交互、遭遇战斗、背包/仓库、装备与词条、制作系统等核心玩法模块。

## 技术栈

- Godot 4.7.1
- GDScript
- Godot 场景（`.tscn`）与资源（`.tres`）

当前仓库没有 C# 工程文件，不需要 .NET SDK，也不需要执行 `dotnet` 构建。

## 当前功能概览

- **地图与场景流转**：地图生成、房间加载与昼夜切换。
- **战斗接入**：世界场景与战斗场景切换，支持按地形和天数调整怪物。
- **地形交互**：地形卡点击、采集与遭遇逻辑。
- **背包与仓库**：背包 UI、全局仓库、物品增减与堆叠。
- **装备与标签**：装备槽位、装备标签校验和属性修正。
- **制作系统**：材料校验、空间校验与制作结果反馈。

## 目录结构

```text
core/                  核心玩法、地图、战斗、制作和 UI 脚本
entities/              玩家、怪物与可复用组件
resources/             怪物、道具、配方、交互和天气等资源定义
scenes/                主菜单、主场景、地图、战斗和 UI 场景
scripts/               地图、战斗、卡牌、动画和 UI 脚本
tests/godot/           Godot 编辑器运行时测试
addons/                Godot 编辑器插件
```

## 环境要求

- Godot 4.7.1
- 打开项目根目录中的 `project.godot`

`project.godot` 的当前功能标记为 `("4.7", "Forward Plus")`，项目使用 GDScript，不启用 C# 功能。

## 启动项目

1. 使用 Godot 4.7.1 打开 `project.godot`。
2. 运行项目。主场景由 `project.godot` 的 `run/main_scene` 指定，当前对应 `scenes/main_menu_scenes/main_menu.tscn`。

项目启用了 `addons/godot_ai` 编辑器插件。自动化验证需要保持 Godot 编辑器打开，通过编辑器 MCP 运行；不要使用旧版命令行 Godot，也不要在测试结束时关闭编辑器。

## 验证方式

项目没有独立编译步骤。按改动范围使用 Godot 编辑器 MCP：

- `filesystem_manage(op="scan")`：刷新文件系统并检查新脚本错误。
- `test_run(suite=..., test_name=...)`：运行 `tests/godot/` 下的聚焦测试。
- `project_run(mode="custom", scene="res://X.tscn")`：运行指定场景。
- `logs_read(source="game")`：检查运行日志中的脚本、解析和资源加载错误。
- `game_eval(code=...)`：在运行中的游戏里检查状态。
- `editor_screenshot(source="game")`：验证 UI 画面。
- `project_manage(op="stop")`：测试结束后停止游戏，但保留编辑器。

## 开发说明

- 自动加载节点（Autoload）以 `project.godot` 的 `[autoload]` 配置为准。
- 修改脚本、节点名称或资源字段时，需要同时检查 `.gd`、`.tscn`、`.tres` 和 `project.godot` 中的引用。
- GDScript 不使用 GitNexus 或 CodeGraph 做依赖分析；使用 `rg` 查找引用，并通过 Godot 编辑器运行验证动态调用和场景连接。
