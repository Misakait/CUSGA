# Quality Guidelines

本规范适用于 Godot 4.7.1 场景、GDScript、UI、autoload、资源和编辑器插件。

## GDScript 风格

- 使用制表符缩进、LF 换行和明确的返回类型；从 `Variant`、字典或动态属性读取时显式声明接收类型。
- 场景依赖使用 `@export`、`@export_group` 和 `@onready`；可选节点使用 `get_node_or_null`。
- 新建 `class_name` 后先执行 `filesystem_manage(op="scan")`，再运行依赖它的场景或测试。
- 信号由创建连接的一方在 `_exit_tree` 中断开；连接前检查 `is_connected`，确保脚本重复进入场景树时幂等。
- 缺少必需依赖使用 `push_error`，可降级依赖使用 `push_warning` 并提供明确回退。

## MVC 与 UI

- Model 保存资源配置、运行状态和业务规则，不引用 UI 节点。
- View 只读取 Model 并刷新节点、文本、图标和场景实例；不直接修改业务数据。
- Controller 接收输入意图，校验后调用 Model 的公开方法，再由信号通知 View 刷新。
- UI 重复控件在容量增长时只创建缺少的子节点；普通刷新不销毁仍有效的节点。
- UI 隐藏时可以延迟昂贵的纯表现刷新，但不能延迟玩家数据、库存或战斗状态的修改。

## 场景与资源安全

- 修改脚本、节点、信号或资源字段前，使用 `rg` 查找 `.gd`、`.tscn`、`.tres` 和 `project.godot` 的引用。
- `.tscn` 中的导出值不等于运行时注入成功；依赖路径必须通过真实场景运行验证。
- `PackedScene.instantiate()` 得到的生产脚本必须按真实生命周期测试；非 `@tool` 脚本的行为夹具应使用脚本 `.new()` 后手动建立最小子树。
- `Window` 派生 UI 使用 `min_size`；不要把 `Control.custom_minimum_size` 误用到 `PopupPanel`、`PopupMenu` 或 `AcceptDialog`。
- 生成文件只能修改其生成器或源资源，不直接编辑生成结果。

## Godot 验证

编辑器必须保持打开并加载 CUSGA。使用 `filesystem_manage(op="scan")`、`test_run`、`project_run`、`logs_read(source="game")`、`game_eval` 和 `editor_screenshot` 完成验证；结束时用 `project_manage(op="stop")` 停止游戏，但不关闭编辑器。

不得使用 GitNexus、CodeGraph、.NET 构建或旧版命令行 Godot 作为本项目的验证步骤。
