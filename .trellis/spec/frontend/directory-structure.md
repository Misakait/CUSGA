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

新增全局状态前先检查 `project.godot` 的 `[autoload]`。现有全局服务包括事件总线、物品控制、仓库、场景管理、过场、设置、天气、玩家进度、钱包、时间、等级、结算和飘字。

**不要用 `autoload_manage(op="add")` 注册 autoload。** 它会按自己的内部顺序重写整个 `[autoload]` 段，把 `SaveManager` 从首位挪走，直接让 `test_save_system_contract` 失败（存档参与者必须排在存档层之前，见 `frontend/state-management.md`）。正确做法是直接编辑 `project.godot`，把新行插在 `SettlementManager` 之后、`_mcp_game_helper` 之前：

```ini
[autoload]
SaveManager="*res://core/save/save_manager.gd"
# ...
SettlementManager="*res://core/settlement/settlement_manager.gd"
FloatingText="*res://core/autoloads/floating_text.gd"
_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
```

改完用 `git diff project.godot` 确认只多了一行，并重跑 `test_run(suite="save_system_contract")`。

**autoload 服务不要声明 `class_name`**：autoload 已经提供同名全局标识符，再声明 `class_name FloatingText` 会冲突。同时调用方**不得裸写该标识符**——`test_run` 环境没有 autoload，裸标识符会让脚本解析失败；一律用 `const X_PATH: NodePath = ^"/root/X"` + `get_node_or_null` + `has_method` 鸭子类型，让缺失的服务优雅降级。

## 放置规则

- 可测试的纯数据和规则放在所属领域的 `core/<system>/` 或 `resources/`。
- 需要场景树生命周期的逻辑放在 Node/Control 脚本。
- UI 视图和输入感知脚本放在 `core/ui/` 或已有 `scripts/ui_scripts/`、`scripts/map_scripts/` 子目录。
- 测试夹具就近放在对应测试文件，不为一次性断言新增全局单例。
