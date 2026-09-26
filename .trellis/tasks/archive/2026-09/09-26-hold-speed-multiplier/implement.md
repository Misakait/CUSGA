# 执行计划：开发者菜单长按速度倍率

对应 `prd.md`（R1–R6）与 `design.md`。所有验证走已打开的 Godot 4.7.1 编辑器 MCP（`addons/godot_ai`），不使用命令行 Godot。

## 0. 前置检查（未通过则先停下）

- [ ] `session_manage(op="list")` / `editor_state` 确认当前会话是 CUSGA（另一个编辑器 `hsr-kill` 可能同时在线，MCP 默认走 active 会话，必要时先 `session_activate`）。
- [ ] `git status` 记录基线。**本次有一个额外前置：上一个任务 `09-26-skill-card-category-tag` 的改动仍未提交**（`skill_card_data.gd`、`skill_card.gd`、69 个 `resources/skill_cards/*.tres`、2 个测试文件、2 个 spec 文件）。必须先由用户提交或明确要求，否则两个任务的改动会混在同一份未提交变更里。用户既有的 `items/environment/campfire.tres`、`scenes/battle_scenes/battle.tscn` 同样不得覆盖。
- [ ] 记录基线测试结果：`dev_settings_contract`、`world_interaction_coordinator_contract`、`reusable_gathering`、`core_constants_contract` 全绿，作为「改动引入回归」的对照。

## 1. 倍率持有与换算（R2）

- [ ] `core/constants/world_interaction_timing.gd` 新增：下界常量、`static var _hold_speed_multiplier: float = 1.0`、`set_hold_speed_multiplier()`（夹紧 `> 0`，拒绝 0/负数/NaN）、`get_hold_speed_multiplier()`、`scale_hold_seconds()`（`base <= 0` 返回 0）。
- [ ] `get_hold_duration_seconds()` 保持纯换算不动。
- [ ] `filesystem_manage(op="scan")` + 诊断确认无 `Parse Error` / `SCRIPT ERROR`。

## 2. 长按施加倍率（R3）

- [ ] `core/gameflow/world_hold_interaction_controller.gd` 的 `begin_timed_hold()`：把 `duration_seconds` 换成缩放后的有效时长，零时长仍走即时回调。
- [ ] `begin_hold()` 保持传入 `WorldInteractionTiming.get_hold_duration_seconds(cost)`（基础秒数），**不得**在此再乘/除一次倍率。
- [ ] 用 `rg` 确认没有第二处施加倍率的地方。

## 3. 开发者菜单改造（R1 + R4）

- [ ] 场景 `scenes/ui_scenes/dev_settings_ui.tscn`：删除 `CostRow`（连同 `CostLabel`、`CostSpinBox`）；新增 `HoldSpeedRow`（`HoldSpeedLabel` 文本「长按速度倍率」+ `HoldSpeedSpinBox`，min 0.1 / max 10 / step 0.1 / value 1）；`ResetCostButton` 重命名为 `ResetHoldSpeedButton`（文本保持「恢复默认」）。
- [ ] 脚本 `core/ui/dev/dev_settings_ui.gd`：删除 `DEFAULT_ACTION_COST`、`MAX_ACTION_COST`、`_cost_row`、`_cost_spin_box`、`_configure_cost_spin_box()`、`_on_cost_spin_box_value_changed()` 及 `_sync_from_time_system()` 里的 `MapMoveTimeCost` 回填。
- [ ] 新增倍率常量（默认 1.0 / 下界 0.1 / 上界 10.0）、`_hold_speed_spin_box`、`_hold_speed_row` 引用、`_configure_hold_speed_spin_box()`、`_on_hold_speed_spin_box_value_changed()`、`_on_reset_hold_speed_button_pressed()`、`_sync_hold_speed_from_multiplier()`。
- [ ] `_apply_feature_visibility()` 的 `run_only_rows` 与 `_connect_buttons()` 的接线同步；`_on_close_button_pressed()` 的焦点释放改指新输入框。
- [ ] 确认面板已完全不引用 `SetMapMoveTimeCost`。

## 4. 契约同步与新增（R5）

- [ ] `tests/godot/test_dev_settings_contract.gd` 6 处更新：`REQUIRED_VBOX_ROWS`（`CostRow`→`HoldSpeedRow`、`ResetCostButton`→`ResetHoldSpeedButton`）、原写入与夹紧测试改写为倍率版、`run_only_names`、场景文本标签断言（`每次行动消耗的行动值`→`长按速度倍率`）、缓存重挂回断言改为回填倍率、最小节点树构造改挂新节点名。
- [ ] 新增断言：倍率默认 1；控件写入倍率；越界夹紧到 0.1~10；「恢复默认」写回 1；`scale_hold_seconds` 在 k=2 时把 1.0 秒缩到 0.5；k=1 时恒等；`get_hold_duration_seconds` 的既有纯换算（0/10/20/−5）复刻进来。
- [ ] 所有触碰倍率的测试在结束前把倍率复位为 `1.0`。
- [ ] 不新建任何 `.cs` 文件。

## 5. 注释与文档（R6）

- [ ] `dev_settings_ui.gd` 类注释与常量注释中提到「行动值消耗」控件的表述改写为倍率控件。
- [ ] `docs/建筑系统.md:50` 补上倍率对 `begin_timed_hold` 时长的影响。

## 6. 验证（必做，顺序执行）

| 目的 | 命令 |
|---|---|
| 刷新脚本 | `filesystem_manage(op="scan")` |
| 面板契约（含新增倍率断言） | `test_run(suite="dev_settings_contract")` |
| 协调器长按入口 | `test_run(suite="world_interaction_coordinator_contract")` |
| 采集链路 | `test_run(suite="reusable_gathering")` |
| 时间常量 | `test_run(suite="core_constants_contract")` |
| 运行期真实生效 | `project_run(mode="main")` → LISBAM 打开面板 → `game_eval` 设倍率并读回实际 Tween 时长与行动值扣费 → `project_manage(op="stop")` |
| 面板可操作 | 同上冒烟中 `editor_screenshot(source="game")` 确认新行显示正常 |

- 阻塞判定：出现 `SCRIPT ERROR`、`Parse Error`、`Failed to load script`、本次改动引入的资源加载错误，或任一上述套件失败，都视为未完成。
- 测试结束后只 `project_manage(op="stop")`，**不关闭 Godot 编辑器**。

## 7. 收尾

- [ ] 重新 `git status`，确认本次改动只含：`world_interaction_timing.gd`、`world_hold_interaction_controller.gd`、`dev_settings_ui.gd`、`dev_settings_ui.tscn`、`test_dev_settings_contract.gd`、（如动了）`docs/建筑系统.md`。
- [ ] 确认用户既有改动与上一个任务的改动都保持原样、未被覆盖。
- [ ] 核对 `dev_settings_ui.tscn` 的 diff 形态只有预期的节点增删，没有编辑器整份重写。

## 风险文件与回滚点

| 文件 | 风险 | 回滚 |
|---|---|---|
| `scenes/ui_scenes/dev_settings_ui.tscn` | MCP 改场景后编辑器重写整份文件 | `git checkout --` 单文件 |
| `core/ui/dev/dev_settings_ui.gd` | 删控件时漏改一处引用 → 解析错误 | `git checkout --` 单文件 |
| `core/gameflow/world_hold_interaction_controller.gd` | 二次缩放导致 k² | `git checkout --` 单文件 |
| `core/constants/world_interaction_timing.gd` | 破坏纯换算契约 | `git checkout --` 单文件 |
| `tests/godot/test_dev_settings_contract.gd` | 节点名与场景不一致 | `git checkout --` 单文件 |

## `task.py start` 前检查

- [ ] `prd.md` 无阻塞开放问题，验收标准可观测。
- [ ] `design.md`、`implement.md` 已就绪（复杂任务三件套齐全）。
- [ ] 用户已明确批准最新一版规划摘要。
- [ ] 上一个任务 `09-26-skill-card-category-tag` 的改动已提交或已获用户明确指示如何处理。
