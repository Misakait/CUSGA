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
- **套件必须覆写 `suite_name()`**：`McpTestSuite.suite_name()` 的默认返回值是 `"unnamed"`，不覆写就会以 `unnamed` 注册，`test_run(suite="xxx")` 永远报 `No suite named 'xxx' is registered`。此时错误信息里的 `suites_available` 会含一个 `unnamed` 条目——那通常就是刚写的套件，不要被它误导成「发现被截断」。正确形状：

  ```gdscript
  ## 提供 GodotAI 使用的稳定套件名称。
  func suite_name() -> String:
  	return "xxx_contract"
  ```

  名字与文件名去掉 `test_` 前缀后一致，便于按套件名过滤。
- **`tests/godot/` 下并非每个文件都是套件**：其中十多个是 `extends SceneTree` 的独立运行脚本（如 `world_hold_interaction_tests.gd`、`passage_guard_tests.gd`），它们不注册为 `McpTestSuite`，`test_run` 永远发现不到，而项目又禁止用命令行 `--script` 运行（无法加载 autoload）。**改动波及这些文件里的断言时，不要声称已通过测试**：把相关断言等价复刻进一个可运行的套件，或在场景冒烟里用 `game_eval` 实证。
- **编辑器测试的边界**：`PackedScene.instantiate()` 对非 `@tool` 的生产脚本只会得到占位实例，方法不可调用。这类行为（贴图切换、节点生命周期）不要硬塞进 `test_run`，改为在冒烟阶段用 `game_eval` 断言真实运行期结果；套件侧只保留数据契约与源码形状断言，并在套件注释里写明该限制。
- **`find_symbols` / `resource_manage(op="load")` 不是解析检查**：两者都会命中 GDScript 的缓存解析结果。实测出现过 `find_symbols` 正常返回全部函数、`resource_manage(op="load")` 返回合法 GDScript，而文件里实际存在 `Identifier "point" not declared in the current scope.` 的情况。该错误只在 `project_run` 里以 `Could not resolve class "res://..."` 的形式暴露，且报错行指向**引用方**的 `extends` 行，极易被误判成缓存问题。**判断脚本能否解析，只认游戏运行或扫描后的 `logs_read(source="editor")`。**
- **否定断言不要用 `contains()` 匹配标识符**：脚本里解释「不要写 X」的注释本身包含 X，会让 `assert_false(source.contains("X"))` 直接失败。改成只看真正的声明行：

  ```gdscript
  func _has_declaration_line(text: String, keyword: String) -> bool:
  	for line: String in text.split("\n"):
  		if line.strip_edges().begins_with(keyword):
  			return true
  	return false
  ```

- **套件失效时会静默退化为「零断言」**：`building_system_tests.tscn` 曾因夹具缺少一个信号而在 `_ready()` 抛错，整个场景中断，**一项断言都不执行**，但运行时只看到一条普通错误。改动这类自包含场景后，必须确认日志里出现了它的汇总行（例如 `[BuildingSystem] 建筑测试：72 项断言，14 项失败`），看不到汇总行就等于没跑过。

### 场景冒烟测试

当行为依赖 autoload、完整场景树、序列化节点路径或真实输入流程时，使用：

1. `project_run(mode="custom", scene="res://X.tscn")` 启动目标场景。
2. `logs_read(source="game")` 检查脚本、解析和资源错误。
3. 必要时用 `game_eval(code=...)` 断言运行时状态。
4. UI 改动用 `editor_screenshot(source="game")` 检查画面。
5. `project_manage(op="stop")` 停止游戏，不关闭编辑器。

修改主流程时通常还要冒烟测试 `scenes/main_menu_scenes/main_menu.tscn` 或 `scenes/Main.tscn`，以实际入口为准。

### `game_eval` 的已知陷阱

冒烟阶段用 `game_eval` 断言运行期状态时，以下几点直接决定成败：

- **不要用 `get_tree()`**：在 eval 的执行上下文里它返回 `null`，`get_tree().process_frame` 会触发 `Invalid access to property or key 'process_frame' on a base object of type 'null instance'` 并让游戏进入 break。改用 `Engine.get_main_loop() as SceneTree`，再经 `tree.root` 取节点。
- **`await` 只在主循环推进时可用**：游戏窗口被后台化或最小化时主循环会冻结（`game_manage(op="debug_status")` 的 `loop_live` 为 false、`tree_paused` 为 true），此时任何 `await ...process_frame` 都会挂到 `EVAL_HUNG`，`editor_screenshot` 也会返回 `stale_frame: true`。
- **eval 里的运行时错误会冻结游戏**：出错后 helper 仍在注册但不再服务，后续 eval 只能拿到 `EVAL_GAME_NOT_READY`。恢复方式是 `project_manage(op="stop")` 后重新 `project_run`；`game_manage(op="resume")` 对这种冻结无效。
- **验证计时或动画时长用 `Tween.custom_step(delta)`**：同步 eval 执行期间场景树不会推进帧，因此在一次 eval 内 `custom_step` 的推进量完全可控，可以精确断言「推进 0.4 秒时仍在进行、推进到 0.6 秒时已完成」，既不受帧率抖动影响，也是窗口被后台化时唯一可行的办法。
- **UI 布局用几何数据核验**：当前模型可能无法读取 `editor_screenshot` 返回的图片；此时用 `get_global_rect()` / `size` 断言控件已真实布局（尺寸非零、落在视口内、相对顺序正确），比目视截图更客观。

### 全局静态状态

- 组件用 `static var` 承载跨场景生效的配置（例如 `WorldInteractionTiming` 的长按速度倍率）时，它是**进程内共享状态**，测试之间会残留。所有写入它的用例必须在结束前复位到默认值，套件里同时要有一条断言覆盖默认值本身。

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
