# Gameplay And Data Specs

本层描述 CUSGA 的 GDScript 核心玩法、实体组件、Godot `Resource` 数据、地图、战斗、制作和物品系统。这里的 `backend` 是 Trellis 的目录名称，不表示网络服务器。

当前仓库已完成 GDScript 迁移，没有 C# 工程或 .NET 测试工程。若旧的长篇设计记录仍提到迁移前类型，只能把它们当作历史兼容背景；实现与验证必须以当前 `.gd`、`.tscn`、`.tres` 和 `tests/godot/` 为准。

## 指南

| 指南 | 使用场景 |
|---|---|
| [目录结构](./directory-structure.md) | 选择核心玩法、组件、资源、UI 和测试文件的位置。 |
| [玩法系统模式](./gameplay-system-patterns.md) | 修改战斗、制作、交互、地图、背包、遭遇或时间系统。 |
| [资源数据规范](./resource-data-guidelines.md) | 新增或修改 GDScript `Resource` 与 `.tres` 配置。 |
| [错误处理](./error-handling.md) | 选择返回值、失败枚举、警告、错误或配置失败处理。 |
| [测试规范](./testing-guidelines.md) | 选择 Godot 编辑器测试或场景冒烟测试。 |
| [质量规范](./quality-guidelines.md) | 执行 GDScript 风格、文档、依赖检查和验证要求。 |

## 当前代码依据

- 项目配置：`project.godot`。
- 核心流程：`core/gameflow/*.gd`、`core/map/*.gd`、`core/crafting/*.gd`、`core/shop/*.gd`。
- 实体组件：`entities/components/*.gd`。
- 数据资源：`resources/**/*.gd` 与 `resources/**/*.tres`。
- 场景脚本：`scripts/**/*.gd`。
- 运行时测试：`tests/godot/test_*.gd`。
