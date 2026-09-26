# Testing Guidelines

CUSGA 使用 `tests/godot/` 下的 GDScript 测试和真实场景冒烟测试。不要假设项目存在 .NET、xUnit、NUnit、Playwright 或命令行 Godot 测试环境。

## 运行前提

- Godot 4.7.1 编辑器必须已打开并加载 CUSGA。
- 使用 `editor_state` 或 `session_manage(op="list")` 检查连接。
- 没有编辑器会话时要求用户打开 Godot，不得改用 `godot-mono`、`--check-only` 或直接 `--script`。

## 测试类型

### GDScript 聚焦测试

`tests/godot/test_*.gd` 覆盖资源契约、组件行为、UI 结构、地图、战斗、背包、制作和迁移后的语言绑定。

- 修改纯数据或算法时，优先运行最接近该模块的测试文件。
- 修改信号顺序、节点生命周期或 UI 行为时，测试必须把节点加入场景树并覆盖真实生命周期。
- 新增公共契约时，添加最小回归测试，避免把多个无关系统塞进同一个测试。
- 运行方式：`test_run(suite=..., test_name=...)`。
- **套件必须在 `tests/` 顶层有同名壳文件**：`test_run` 的发现逻辑只列 `res://tests` 的直接子项、不递归，`tests/godot/` 下的套件全靠顶层壳被发现。壳文件只有两行：

  ```gdscript
  @tool
  extends "res://tests/godot/test_xxx_contract.gd"
  ```

  只把文件放进 `tests/godot/` 会得到 `No suite named '...' is registered (N discovered)`。补壳文件后重新 `filesystem_manage(op="scan")` 即可被发现；重载插件**不会**刷新该缓存。
- **编辑器测试的边界**：`PackedScene.instantiate()` 对非 `@tool` 的生产脚本只会得到占位实例，方法不可调用。这类行为（贴图切换、节点生命周期）不要硬塞进 `test_run`，改为在冒烟阶段用 `game_eval` 断言真实运行期结果；套件侧只保留数据契约与源码形状断言，并在套件注释里写明该限制。

### 场景冒烟测试

当行为依赖 autoload、完整场景树、序列化节点路径或真实输入流程时，使用：

1. `project_run(mode="custom", scene="res://X.tscn")` 启动目标场景。
2. `logs_read(source="game")` 检查脚本、解析和资源错误。
3. 必要时用 `game_eval(code=...)` 断言运行时状态。
4. UI 改动用 `editor_screenshot(source="game")` 检查画面。
5. `project_manage(op="stop")` 停止游戏，不关闭编辑器。

修改主流程时通常还要冒烟测试 `scenes/main_menu_scenes/main_menu.tscn` 或 `scenes/Main.tscn`，以实际入口为准。

## 验证矩阵

| 改动 | 最小验证 |
|---|---|
| 纯 GDScript 数据或算法 | 文件系统扫描 + 对应 `test_run` |
| `.tres` 资源结构 | 对应资源测试 + 使用该资源的场景冒烟 |
| `.tscn` 节点路径或信号 | 目标场景冒烟 + 游戏日志 |
| autoload 或主流程 | 主菜单进入游戏的完整冒烟测试 |
| UI 布局或交互 | 聚焦测试 + 场景截图 |
| 动态 `call` / 字符串信号 | 聚焦测试或 `game_eval` 验证真实调用链 |

## 通过标准

- 测试确实发现并执行了至少一个目标用例。
- 没有本次改动引入的 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或资源加载错误。
- 资源 UID 警告只在涉及本次修改文件时作为失败处理。
- 测试结束后重新检查 `git status`，避免把编辑器产生的无关改写混入提交。
