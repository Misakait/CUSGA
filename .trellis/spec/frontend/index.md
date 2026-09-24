# Godot Scene And UI Specs

本层覆盖 Godot 场景、GDScript UI、autoload、编辑器插件以及场景与核心玩法之间的连接。`frontend` 是 Trellis 的目录名称，不表示 Web 前端。

当前生产代码使用 GDScript。旧规范或历史记录中提到的跨语言桥接只用于理解迁移背景，不是新增功能的实现方式。

## 指南

| 指南 | 使用场景 |
|---|---|
| [目录结构](./directory-structure.md) | 选择场景、GDScript、UI 控件和插件的位置。 |
| [组件规范](./component-guidelines.md) | 添加 GDScript UI、场景脚本或可复用视图组件。 |
| [状态管理](./state-management.md) | 使用 autoload、导出路径、信号、本地节点状态和场景流转。 |
| [类型安全](./type-safety.md) | 处理类型数组、动态资源字段、节点协议和 Variant 边界。 |
| [质量规范](./quality-guidelines.md) | 验证 GDScript、场景、UI、资源和运行时集成。 |

## 当前代码依据

- Godot 配置：`project.godot`。
- UI：`core/ui/**/*.gd`、`scripts/ui_scripts/*.gd`。
- 场景逻辑：`scripts/**/*.gd`、`core/gameflow/*.gd`、`core/map/*.gd`。
- 资源：`resources/**/*.gd` 与 `.tres`。
- 运行时测试：`tests/godot/test_*.gd`。
