# 执行计划 — 开发者设置窗口（LISBAM 入口）

## 0. 前置条件

- Godot 编辑器已打开本项目（`CUSGA`，4.7.1）。开始前先跑一次 `editor_state` 确认 `readiness = ready`；若 `session_active` 为假，请用户打开 Godot，**不要**退回命令行。
- 记录改动前的干净基线：`git status --porcelain`。
- 本任务不涉及 C#，无需 `dotnet build`。

## 1. 实施清单（按序执行）

### 步骤 1 — 序列匹配器（纯逻辑，无场景依赖）

- [ ] 新建 `core/ui/dev/dev_sequence_matcher.gd`：`class_name DevSequenceMatcher extends RefCounted`，实现 `push_letter` / `get_progress` / `reset`。
- [ ] 中文文档注释覆盖公开方法，说明参数与返回值（`AGENTS.md` §2 要求）。
- [ ] 落盘后跑 `filesystem_manage(op="scan")` 刷新全局类缓存，确认 `DevSequenceMatcher` 已注册。

**验证**：步骤 5 的 `test_run` 覆盖本文件的全部匹配分支。

### 步骤 2 — 面板场景

- [ ] 新建 `scenes/ui_scenes/dev_settings_ui.tscn`，按 `design.md` §3 的结构搭建：根 `Control`（`visible = false`、`mouse_filter = IGNORE`）+ 居中 `PanelContainer` + 标题 / 天数标签 / 行动值 `SpinBox` / 三个按钮。
- [ ] 按钮 `focus` 样式设为 `StyleBoxEmpty`（`frontend/component-guidelines.md` 的双重边框陷阱）。
- [ ] `SpinBox` 设 `min_value = 1`、`max_value = 999`、`step = 1`。

### 步骤 3 — 面板控制器

- [ ] 新建 `core/ui/dev/dev_settings_ui.gd`，实现：
  - `_unhandled_input` 中的序列监听（不吞键、不过滤非字母键的进度）；
  - `_resolve_letter`（`physical_keycode` 优先，`unicode` 回退，忽略 `echo`）；
  - `_get_points_to_next_day` 与「下一天」按钮处理（走 `TimeSystem.PassTime`）；
  - 行动值 `SpinBox` 的 `value_changed` → `TimeSystem.SetMapMoveTimeCost`，以及「恢复默认」按钮；
  - `_ready` 连接 `TimeSystem.TimeChanged`，`_exit_tree` 断开；
  - 关闭按钮 → 隐藏面板并 `release_focus()`。
- [ ] 用 `get_node_or_null("/root/TimeSystem")` 解析 Autoload，缺失时 `push_error` 并禁用功能（符合 `frontend/quality-guidelines.md` 的场景安全要求）。

### 步骤 4 — 挂载到主场景

- [ ] 在 `scenes/Main.tscn` 的 `UI/HUDLayer/HUDRoot` 下新增 `DevSettingsUI` 实例（**纯增量**，不触碰既有节点段）。
- [ ] `scene_save` 落盘。

### 步骤 5 — 运行期测试

- [ ] 新建 `tests/godot/dev_settings_tests.gd`，覆盖：
  - `LISBAM` 六键依次送入 → 返回 `true`；
  - 只送 `LIS` → 返回 `false`，`get_progress() == 3`；
  - `L L I S B A M` → 仍返回 `true`（错键后从该键重新开始）；
  - `L X I S B A M` → 返回 `false`；
  - `_get_points_to_next_day` 在 `total` 为 0 / 50 / 150 / 200 时分别得到 200 / 150 / 50 / 200。

**验证**：`test_run(suite="dev_settings")`。

### 步骤 6 — 场景冒烟与交互断言

- [ ] `project_run(mode="custom", scene="res://scenes/Main.tscn")` → `logs_read(source="game")`，确认无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
- [ ] `project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")` → 同样确认无脚本错误（覆盖局内战斗路径）。
- [ ] 用 `game_eval` 在运行中的游戏里断言：
  - 依次发送六次 `InputEventKey`（`physical_keycode` = `KEY_L/I/S/B/A/M`）后，`DevSettingsUI.visible == true`；
  - 点击「下一天」后 `TimeSystem.get_CurrentDay()` 增加 1；
  - 设置 `SpinBox.value = 25` 后 `TimeSystem.MapMoveTimeCost == 25`；
  - `get_tree().paused == false`（确认未暂停）。
- [ ] `editor_screenshot(source="game")` 目视确认面板渲染正常。
- [ ] `project_manage(op="stop")` 结束游戏。

### 步骤 7 — 收尾检查

- [ ] `test_run` 跑既有相关 suite，确认无回归。
- [ ] `git status --porcelain` 与基线对比，还原 Godot 编辑器造成的非预期改动（`.cs` 缩进重排、`CUSGA.csproj` SDK 版本）。
- [ ] 确认新增文件都在预期路径，`scenes/Main.tscn` 的 diff 只有新增节点段。

## 2. 验证命令汇总

| 目的 | 命令 |
|---|---|
| 刷新全局类缓存（新增 `class_name` 后必做） | `filesystem_manage(op="scan")` |
| 运行期测试 | `test_run(suite="dev_settings")` |
| 主场景冒烟 | `project_run(mode="custom", scene="res://scenes/Main.tscn")` + `logs_read(source="game")` |
| 战斗场景冒烟 | `project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")` + `logs_read(source="game")` |
| 运行中状态断言 | `game_eval(code=...)` |
| UI 目视确认 | `editor_screenshot(source="game")` |
| 结束游戏 | `project_manage(op="stop")` |
| 改动面复核 | `git status --porcelain` |

**不作为门禁的手段**：`--check-only --script`（引用 Autoload 必然报 `Identifier not found`，项目既有脚本同样如此）、`godot-mono --build-solutions`（本机 CLI 版本不符，直接 abort）。详见 `frontend/quality-guidelines.md`。

## 3. 高风险文件与回滚点

| 文件 | 风险 | 回滚方式 |
|---|---|---|
| `scenes/Main.tscn` | 主场景，改坏会导致游戏无法启动 | 删除新增的 `DevSettingsUI` 节点段；改动为纯增量，不影响既有节点 |
| `core/ui/dev/dev_settings_ui.gd` | 序列监听若吞键会破坏既有输入 | 不调用 `set_input_as_handled()`；回滚 = 删除文件与场景节点 |
| `core/ui/dev/dev_sequence_matcher.gd` | 新增 `class_name` 需刷新缓存 | 删除文件；若残留缓存则 `filesystem_manage(op="scan")` |

## 4. `task.py start` 之前的复查项

- [ ] `prd.md`、`design.md`、`implement.md` 三者对 R1–R4 的描述一致，且 `prd.md` 已无未决 Open Questions。
- [ ] 用户已对最终规划摘要给出**明确批准**（创建任务的同意与最初的实现请求都不构成批准）。
- [ ] 编辑器会话可用（`editor_state` 为 `ready`）。
- [ ] 基线 `git status --porcelain` 已记录。
