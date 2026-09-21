# 开发者设置窗口（LISBAM 入口）

## Goal

让开发者在不重启游戏、不改动任何资源文件的前提下，在运行中的游戏里用一段隐藏按键序列打开一个开发者设置窗口，并立即对当前对局施加调试效果。首批提供两项功能：**下一天**、**行动值消耗**。

## Background（已确认事实）

- 项目为纯 GDScript 的 Godot 4.7 工程；主场景 `res://scenes/Main.tscn`，根节点 `Main`。
- 局外 HUD 结构：`UI/HUDLayer`（CanvasLayer）→ `HUDRoot`（Control）→ `CenterOverlay`（CenterContainer），其中已挂载 `InventoryUI`、`CraftingUI`、`WarehouseUI` 三个居中弹窗。
- 局内战斗**不是**切换 `current_scene`：`core/gameflow/world_interaction_coordinator.gd:30` 定义 `BATTLE_SCENE_PATH`，把 `battle.tscn` 作为 `Main` 的子节点挂载；`scripts/ui_scripts/status_effect_bar.gd:151` 的注释同样说明「局内触发的战斗会把 battle.tscn 挂在世界主场景 Main 之下」。因此 `Main/UI/HUDLayer` 在局外与局内战斗中**都存活**。
- 时间系统：Autoload `TimeSystem`（`core/autoloads/time_system.gd`）。`PhaseLength = 100`，一天 = 白天 + 夜晚 = 2 个阶段 = 200 点。信号 `DayPassed(current_day)`、`DayNightToggled(is_night)`、`TalentSelectionTriggered`、`TimeChanged(...)`；方法 `PassTime(amount)`、`get_CurrentDay()`、`get_PhaseProgress()`、`PassMapMoveTime()`、`SetMapMoveTimeCost(amount)`。`_check_time_transitions` 会在跨阶段时切换昼夜、每跨 2 个阶段天数 +1、天数逢 7 的倍数发 `TalentSelectionTriggered`。
- 行动值来源：`core/constants/time_costs.gd`（`MapMove=10`、`EnterScene=5`、`ChopTree=20`、`PlantSeed=10`，后三者当前无读取方）；地图移动实际读取 `TimeSystem.MapMoveTimeCost`（`@export`，默认 10）；局外交互读取交互资源上的 `TimeCost`（`core/gameflow/world_interaction_coordinator.gd:1061` `_get_interaction_action_point_cost`）。
- 行动值 → 真实长按时长的换算：`core/constants/world_interaction_timing.gd`，`GAME_TIME_POINTS_PER_HOLD_SECOND = 10.0`（10 点 = 1 秒）。
- 本地设置基础设施：Autoload `SettingsManager`（`core/autoloads/SettingsManager.gd`），提供 `get_setting/set_setting/erase_setting`，落盘 `user://settings.cfg`，按「分组 + 键 + 默认值」使用。
- 既有面板 UI 惯例：`scripts/battle_scripts/battle_settings_panel.gd`（按钮切换 `PanelContainer` 的 `visible`，`@onready` 固定子路径）。
- 既有输入惯例：`core/ui/hud/hud_controller.gd` 在 `_input` / `_unhandled_input` 中处理 InputMap 动作，并调用 `get_viewport().set_input_as_handled()`。

## Requirements

### R1 — LISBAM 按键序列入口

- 在游戏内依次按下 `L`、`I`、`S`、`B`、`A`、`M` 六个字母键后打开开发者设置窗口。
- 序列识别必须对玩家正常操作无副作用：不注册为 InputMap 动作、不吞掉不属于序列的按键、不因输入框（如仓库/背包中的文本输入）而误触发。
- 序列中断（按到不匹配的键）后必须能从该键重新开始匹配，不需要玩家手动重置。
- 窗口已打开时再次输入完整序列，应保持窗口打开（幂等），不得重复创建窗口。

### R2 — 开发者设置窗口

- 窗口为叠加在画面上的浮层，**不暂停游戏**（`get_tree().paused` 保持 `false`），游戏逻辑继续运行。
- 窗口必须可关闭，并提供明确的当前值反馈：面板需显示当前天数与当前行动值消耗，供开发者确认操作已生效。
- 窗口位置与风格应与既有 HUD 浮层一致（`Main/UI/HUDLayer` 下），不遮挡 HUD 关键信息到不可用的程度。
- 面板必须可扩展：后续新增开发者功能时，只需追加一个条目，不改动序列识别与开关逻辑。

### R3 — 功能一：下一天

- 点击「下一天」后，游戏时间推进到第二天的开始（白天阶段起点），并触发时间系统原本就会发出的全部信号。
- 推进必须复用 `TimeSystem` 的既有推进路径（`PassTime`），不得直接改写 `_current_day` 等内部状态，以免昼夜、天赋选择、天气等依赖信号的系统被跳过。
- 推进后窗口上显示的天数必须立即更新为新的天数。

### R4 — 功能二：行动值消耗

- 提供一个可调数值控件，用于设置地图移动的行动值消耗，默认值 `10`。
- 取值必须实时写入 `TimeSystem.MapMoveTimeCost`，使后续地图移动的长按时长立即按新值换算（`core/constants/world_interaction_timing.gd`）。
- 非法输入（非整数、零、负数、超出合理上界）必须被拒绝或夹紧到合法范围，且不得把 `TimeSystem.MapMoveTimeCost` 置为非法值。
- 控件需提供恢复默认值（`10`）的途径。
- **不持久化**：设定值只影响当前会话，不得写入 `user://settings.cfg` 或任何本地文件；重启游戏后回到默认 `10`。

## Acceptance Criteria

- [ ] 在游戏内依次按下 `L`、`I`、`S`、`B`、`A`、`M` 后，开发者设置窗口出现；窗口打开时游戏**没有**暂停。
- [ ] 未输入完整序列（例如只按 `L`、`I`）时窗口不出现；按错键后继续输入完整序列仍能打开窗口。
- [ ] 窗口可关闭；关闭后可再次用同一序列打开，且不会出现重复窗口。
- [ ] 点击「下一天」后 `TimeSystem.get_CurrentDay()` 增加 1，`DayPassed` 信号按既有规则发出，窗口显示的天数同步更新。
- [ ] 「行动值消耗」控件默认显示 `10`；修改为合法值后 `TimeSystem.MapMoveTimeCost` 立即等于该值，且随后的地图移动长按时长按 `行动值 / 10` 秒换算。
- [ ] 在「行动值消耗」输入非法值时，`TimeSystem.MapMoveTimeCost` 保持原值不被破坏。
- [ ] 修改「行动值消耗」后重启游戏，`TimeSystem.MapMoveTimeCost` 回到 `10`，且 `user://settings.cfg` 中不出现本次改动写入的键。
- [ ] 局外游玩与局内战斗两种状态下，序列入口均可用（`Main/UI/HUDLayer` 在这两种状态下都存活）。
- [ ] 主场景 `res://scenes/Main.tscn` 与 `res://scenes/battle_scenes/battle.tscn` 通过 `project_run` 冒烟启动后，`logs_read(source="game")` 中不出现 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
- [ ] 新增脚本符合项目注释规范（中文注释、公开 API 有文档注释），且不破坏现有测试（`test_run`）。

## Out of Scope

- 不新增除「下一天」「行动值消耗」以外的开发者功能（但面板结构需支持后续追加）。
- 不改动战斗内 ATB 的 `action_value`（`scripts/battle_scripts/battle_manager.gd` 中的行动值总量），本任务的「行动值」仅指局外时间点数消耗。
- 不改动 `core/constants/time_costs.gd` 中的常量契约。
- 不为主菜单（`res://scenes/main_menu_scenes/main_menu.tscn`）提供入口——它不是「游戏内」。
- 不做按键序列的可配置化（序列固定为 `LISBAM`）。
- 不把开发者设置接入 `SettingsManager`（已确认不持久化）。
