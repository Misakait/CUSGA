# 迁移盘点

## 当前规模

- 项目自有 C# 文件约 200 个（`core/` 约 120、`entities/` 约 19、`resources/` 约 56，另有测试入口；`.godot/mono/temp` 生成文件不计入源码）。
- 现有 GDScript 约 90 个，主要位于 `scripts/` 和 GodotAI/其他插件目录。
- `project.godot` 仍启用 C# 特性，并注册 `PlayerWallet.cs`、`PlayerProgression.cs` 等 C# Autoload。
- 主场景和大量 `.tres` 资产仍通过 C# UID/路径加载脚本。

## 主要分层

- `core/constants`、`core/attributes`、`core/combat`、`core/crafting`、`core/map`、`core/gameflow`：规则、服务和流程。
- `entities/components`：属性、生命、能量、背包、装备、状态、伤害接收等节点组件。
- `resources/`：物品、卡牌、怪物、地形交互、掉落、天气和天赋等 Resource。
- `core/ui`：背包、装备、制造、仓库、HUD 和地图/战斗 UI。

## 高风险点

1. `.tres` / `.res` 依赖 C# Resource 脚本 UID 和导出字段序列化。
2. C# Autoload 与 GDScript 的属性、信号、`Object.call` 封送。
3. C# 组件之间的强类型继承和场景节点路径。
4. GDScript 与 C# 的 `Callable`、枚举、数组和 Variant 类型转换。
5. 测试和生成脚本可能继续硬编码旧 `.cs` 路径。

## 推荐顺序

独立工具/枚举/值对象 → Resource 数据 → 纯逻辑服务/效果 → entities 组件 → UI → gameflow/map/board → Autoload → 核心玩法 → 工程清理。

## 第一阶段依据

局外长按模块已有独立 Godot 测试 `tests/godot/world_hold_interaction_tests.gd`，其行为边界清晰，且主场景只通过 `WorldInteractionCoordinator` 使用控制器。先迁移该模块可以验证 GDScript `Tween`、CanvasItem 锚点和 C#→GDScript 动态调用的兼容方式，再扩展到其他跨层模块。
