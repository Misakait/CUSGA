# Directory Structure

- `scenes/`：主菜单、主场景、地图、战斗、背包、制作和其他 UI 场景。
- `scripts/`：地图、战斗、卡牌、动画、仓库和通用 UI 场景脚本。
- `core/`：按领域组织的 GDScript Model、Controller、View、组件和工具脚本。
- `entities/`：玩家、怪物与 `entities/components/` 下的节点组件。
- `resources/`：GDScript `Resource` 定义和 `.tres` 数据资产。
- `addons/`：Godot 编辑器插件。
- `tests/godot/`：由 Godot 编辑器 MCP 发现并运行的 `test_*.gd` 测试。
- `scripts/generated/`：生成的 GDScript 文件，只通过对应生成器更新。

## Autoload

新增全局状态前先检查 `project.godot` 的 `[autoload]`。现有全局服务包括事件总线、物品控制、仓库、场景管理、过场、设置、天气、玩家进度、钱包、时间和等级。

## 放置规则

- 可测试的纯数据和规则放在所属领域的 `core/<system>/` 或 `resources/`。
- 需要场景树生命周期的逻辑放在 Node/Control 脚本。
- UI 视图和输入感知脚本放在 `core/ui/` 或已有 `scripts/ui_scripts/`、`scripts/map_scripts/` 子目录。
- 测试夹具就近放在对应测试文件，不为一次性断言新增全局单例。
