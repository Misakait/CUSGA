# 开发者菜单长按速度倍率

## Goal

让开发者能在游戏内实时调节所有局外长按的等待快慢，调试时不必被长按耗时拖累；同时移除开发者菜单里已不再需要的「每次行动消耗的行动值」调节入口。

## Background（已确认事实，均来自仓库证据）

### 长按时长的当前链路

- 唯一换算入口是 `core/constants/world_interaction_timing.gd:13`：`get_hold_duration_seconds(cost) = cost / GAME_TIME_POINTS_PER_HOLD_SECOND`（常量为 `10.0`，见 `:6`）。
- 该函数只有两个调用方：`core/gameflow/world_hold_interaction_controller.gd:47`（`begin_hold`，所有由行动值决定时长的局外长按）与 `resources/interaction/reusable_gathering_interaction.gd:49`（`get_required_hold_seconds`）。后者在生产代码中**没有调用方**，唯一使用点是 `tests/godot/test_reusable_gathering_interaction.gd:322`。
- 长按还有第二条入口 `world_hold_interaction_controller.gd:54`：`begin_timed_hold(owner, duration_seconds, ...)` 直接按真实秒数计时，唯一生产调用方是 `core/building/building_controller.gd:441`（建筑拆除，秒数取自建筑的 `DemolitionHoldSeconds`）。
- 真正计时的唯一执行点是 `begin_timed_hold` 内的 Tween（`world_hold_interaction_controller.gd:75-77`）；`duration_seconds <= 0` 时走即时回调、不建 Tween（`:61-64`）。
- 覆盖到的长按场景（`docs/游戏机制与玩法内容.md:5`）：地图方向移动、一次性采集、可重复采集、耕种、宝库、首领；棋盘地形卡的长按同样经 `WorldInteractionCoordinator` 进入该控制器（`core/gameflow/world_interaction_coordinator.gd:402`）。

### 行动值消耗的当前链路

- 地图移动：`core/autoloads/time_system.gd:12` 的 `@export var MapMoveTimeCost: int = 10`，由 `SetMapMoveTimeCost`（`:59-65`）写入，并经 `PassTime(MapMoveTimeCost)` 真实扣费。
- 采集等交互：各自资源的 `TimeCost`（如 `resources/interaction/reusable_gathering_interaction.gd:10` 为 20）经装备减免后生效。
- 建筑拆除不消耗行动值（`world_hold_interaction_controller.gd:51` 注释明确它是「不消耗行动值的操作」）。

### 开发者菜单的当前链路

- 场景 `scenes/ui_scenes/dev_settings_ui.tscn`：`CostRow`（`:54`）内含 `CostLabel`（`:59`，文本「每次行动消耗的行动值」）与 `CostSpinBox`（`:63`，1~999，默认 10）；另有 `ResetCostButton`（`:82`，文本「恢复默认」）。
- 脚本 `core/ui/dev/dev_settings_ui.gd`：`DEFAULT_ACTION_COST`（`:16`）、`MAX_ACTION_COST`（`:21`）、`_cost_row`（`:61`）、`_cost_spin_box`（`:63`）、`_reset_cost_button`（`:65`）；配套的 `_configure_cost_spin_box`（`:383`）、`_on_cost_spin_box_value_changed`（`:300`，写 `SetMapMoveTimeCost`）、`_on_reset_cost_button_pressed`（`:293`）、`_sync_from_time_system` 回填（`:370-371`）、`_apply_feature_visibility`（`:415-421`）、`_connect_buttons`（`:431`、`:434`）。
- `@export var ShowRunFeatures`（`:56`）决定局内专属控件可见性，当前包含 `_cost_row` 与 `_reset_cost_button`。
- `core/ui/dev/` 下只有 `dev_settings_ui.gd` 与 `dev_sequence_matcher.gd`；`docs/` 中没有开发者菜单的专门文档（按「开发者设置」「行动值消耗」检索仅命中 `docs/游戏机制与玩法内容.md:5` 的长按规则说明）。

### 受影响的既有契约与工具

- `tests/godot/test_dev_settings_contract.gd` 在 **6 处**锁定行动值消耗控件：必需节点表（`:47`、`:50`）、写入与夹紧断言（`:271-295`）、生产场景节点表（`:395-396`）、场景文本标签断言（`:517-518`）、缓存重挂回回填断言（`:622`、`:636`）、最小节点树构造（`:738-743`）。删除控件必然使这些断言失败，必须在同一改动内更新，否则属于本次引入的回归。
- `tests/godot/test_core_constants_contract.gd:76` 锁定 `MapMoveTimeCost` 默认值 10 —— 本次不动时间系统，该断言不受影响。
- `tests/godot/world_hold_interaction_tests.gd:35-47` 锁定 `get_hold_duration_seconds` 的纯换算（0→0.0、10→1.0、20→2.0、−5→0.0）—— 倍率若不进入该函数即可保持通过。
- `tests/godot/test_reusable_gathering_interaction.gd:322` 断言 `get_required_hold_seconds() == 2.0`，倍率默认 1 时仍成立。
- `core/ui/item_tooltip_presenter.gd:10` 证明项目允许在 `extends RefCounted` 的工具类里使用 `static var` 作为进程内共享状态。

## Requirements

### R1 移除开发者菜单的「每次行动消耗的行动值」功能

删除范围**仅限开发者菜单这条调节链路**：

- 场景：`CostRow` 节点（连同其下的 `CostLabel` 与 `CostSpinBox`）。
- 脚本：`DEFAULT_ACTION_COST`、`MAX_ACTION_COST`、`_cost_row`、`_cost_spin_box`、`_configure_cost_spin_box()`、`_on_cost_spin_box_value_changed()`、`_sync_from_time_system()` 中的回填、`_apply_feature_visibility()` 与 `_connect_buttons()` 中的相关引用。

**必须保留** `TimeSystem.MapMoveTimeCost` 与 `SetMapMoveTimeCost`：地图移动仍依赖它们扣费（`scripts/map_scripts/map_button/map_button.gd:108`、`tests/godot/passage_guard_tests.gd:208`、`tests/godot/test_core_constants_contract.gd:76`）。面板不再改写该值，它恒为导出默认 10。

### R2 长按速度倍率的持有与换算

- 新增开发者可调的「长按速度倍率」`k`，默认 `1.0`，即当前行为。
- **语义：k 只缩放等待时长，不改变任何行动值扣费。** k=2 时，原本消耗 10 点、等待 1 秒的交互仍是消耗 10 点，但只等 0.5 秒。这使调试加速与游戏经济（天数推进、资源平衡）完全解耦。
- 换算关系：`实际等待秒数 = 基础秒数 / k`。
- 持有者是 `core/constants/world_interaction_timing.gd` —— 它已经是「行动值与等待时长的换算规则」的承载者，倍率正是这条换算上的一个系数；以 `static var` 提供全局读写入口，面板与运行期都不需要新增 Autoload 或场景路径依赖。
- k 必须恒 `> 0`：写入入口要把非法值（0、负数、NaN）夹紧到下界，否则会得到无穷或负时长的 Tween。

### R3 所有局外长按按倍率缩放

- `world_hold_interaction_controller.begin_timed_hold()` 是唯一的计时执行点，倍率在此统一施加，从而一次覆盖两条入口：`begin_hold`（行动值类：地图移动、采集、耕种、宝库、首领、棋盘地形）与 `begin_timed_hold`（秒数类：建筑拆除）。
- `begin_hold` 传入的仍是不含倍率的基础秒数，**不得与其内部的缩放叠加**，否则会变成 k²。
- `WorldInteractionTiming.get_hold_duration_seconds()` 保持纯换算、不含倍率，既有调用方语义与既有测试都不受影响。
- 缩放后仍为 0 的时长必须继续走即时回调路径（零消耗交互的单击体验不变）。

### R4 开发者菜单新增「长按速度倍率」控件

- `scenes/ui_scenes/dev_settings_ui.tscn` 新增一行：标签「长按速度倍率」+ `SpinBox`，节点命名沿用既有 `GoldRow` / `GoldSpinBox` 的惯例。
- 默认显示 `1`，范围 `0.1 ~ 10`，步进 `0.1`，关闭越界放行（与 `_configure_gold_spin_box` 同一套做法）。
- 控件值变化时写入 R2 的倍率持有者。
- 该行属于局内专属控件，跟随 `ShowRunFeatures` 一同显示/隐藏（长按只发生在局内）。
- 现有 `ResetCostButton`（文本「恢复默认」）改为把倍率写回 `1`。其节点名若随语义调整，必须同步场景与所有引用它的测试。

### R5 契约同步与新增

- 更新 `tests/godot/test_dev_settings_contract.gd` 中上述 6 处断言，使其反映新控件而非被删控件。
- 新增断言覆盖：倍率默认值为 1；控件写入倍率；越界输入被夹紧到 `0.1~10`；「恢复默认」把倍率写回 1；倍率取 2 时实际等待时长减半；倍率取 1 时行为与改动前一致；建筑拆除走的 `begin_timed_hold` 同样受倍率影响。
- 倍率是**进程内静态状态**，任何触碰它的测试都必须在结束时复位为 1，避免污染同进程内其它套件。

### R6 注释与文档同步

- `core/ui/dev/dev_settings_ui.gd` 的类注释与常量注释中凡提到「行动值消耗」控件的表述，需改写为倍率控件。
- `docs/建筑系统.md:50` 若描述了 `begin_timed_hold` 的时长语义，需补上倍率这一层。

## Acceptance Criteria

- [x] 开发者菜单不再存在「每次行动消耗的行动值」标签与输入框；面板运行期不再调用 `SetMapMoveTimeCost`。
- [x] `TimeSystem.MapMoveTimeCost` 仍存在且默认 10，地图移动扣费与既有相关测试不受影响。
- [x] 开发者菜单出现「长按速度倍率」一行，默认 1，可调范围 0.1~10，步进 0.1。
- [x] 倍率取 2 时，一次原本 1 秒的长按在运行期约 0.5 秒完成，且该交互的行动值扣费与倍率取 1 时相同。
- [x] 倍率取 1 时，所有长按时长与改动前完全一致。
- [x] 倍率对 `begin_hold` 与 `begin_timed_hold` 两条入口都生效（含建筑拆除）。
- [x] 「恢复默认」按钮把倍率写回 1。
- [x] 受影响套件（`dev_settings_contract`、`reusable_gathering`、`core_constants_contract` 等）无本次引入的失败，无 `SCRIPT ERROR` / `Parse Error`。
- [x] 场景冒烟运行无新增报错，开发者菜单可正常打开与操作。

## 验收证据

### 编辑器套件（`test_run`）

| 套件 | 结果 | 说明 |
|---|---|---|
| `dev_settings_contract` | 17/17 | 含新增的倍率换算与控制器接线断言 |
| `core_constants_contract` | 7/7 | `MapMoveTimeCost` 默认值仍为 10 |
| `reusable_gathering` | 57/58 | 唯一失败是既有的「普通生产物品资产数量必须保持为 103」（实际 102），其收集范围 `res://items` 与本次改动无交集 |
| `world_interaction_coordinator_contract` | 5/9 | 3 个失败全部断言 `core/gameflow/world_interaction_coordinator.gd` 的源码文本（屏幕转场、战斗背景解析器），该文件不在本次改动范围内，属既有失败 |

`tests/godot/world_hold_interaction_tests.gd` 是 `extends SceneTree` 的独立脚本，**不注册为 `McpTestSuite`**，`test_run` 无法执行它（项目也禁止用命令行 `--script` 跑）。它锁定的 `get_hold_duration_seconds` 纯换算断言已在 `dev_settings_contract` 内等价复刻，确保真正被执行而不是口头声称覆盖。

### 运行期实证（`project_run` + `game_eval`）

在真实 `scenes/Main.tscn` 进程内用 `Tween.custom_step()` 精确推进虚拟时间：

| 观测 | 结果 | 含义 |
|---|---|---|
| 倍率 1、10 点行动值：0.9s 未完成 / 1.1s 完成 | ✓ | 与改动前一致（1.0 秒） |
| 倍率 2、同样 10 点行动值：0.4s 未完成 / 0.6s 完成 | ✓ | 等待精确减半到 0.5 秒 |
| 倍率 2、`begin_timed_hold(1.0s)`：0.6s 完成 | ✓ | 第二条入口（建筑拆除）同样受缩放 |
| 倍率 3、`begin_hold(cost=0)`：不建立长按 | ✓ | 零消耗交互保持即时单击 |
| `MapMoveTimeCost` | 10 | 倍率未改动任何扣费基数 |
| 倍率 3 下 `get_hold_duration_seconds(10)` | 1.0 | 纯换算与倍率彻底解耦 |

### 面板端到端（真实场景节点）

| 观测 | 结果 |
|---|---|
| `%HoldSpeedSpinBox` 默认值 / min / max / step | 1 / 0.1 / 10 / 0.1 |
| `allow_greater` / `allow_lesser` | false / false |
| 标签与按钮文案 | 「长按速度倍率」/「恢复默认」 |
| 控件设为 4 后的生效倍率与 1 秒实际时长 | 4 / 0.25 秒 |
| 先改倍率为 2 再打开面板时控件显示 | 2（按生效值回填） |
| 「恢复默认」后的倍率与控件值 | 1 / 1 |
| 场景中是否仍存在 `CostRow` / `CostSpinBox` | 否 / 否 |
| 控件几何（布局、顺序、是否在视口内） | 已真实布局、天数→倍率→金币、在视口内 |

`editor_screenshot(source="game")` 已抓到实时帧（`stale_frame: false`）；因当前模型不支持图像输入，画面核验改用控件几何数据完成。

## Out of Scope

- 不修改 `TimeSystem` 的时间流逝、天数推进与 `PassTime` 扣费规则。
- 不改变任何交互的行动值消耗数值（`MapMoveTimeCost` 与各资源 `TimeCost` 保持原值）。
- 不把倍率接入存档 —— 开发者菜单其余项同样不持久化，倍率是本次会话内的调试开关。
- 不改动长按圆环 HUD 的绘制与视觉表现。
- 不改动战斗内卡牌的点击/按下逻辑（它们不经过 `WorldHoldInteractionController`）。
