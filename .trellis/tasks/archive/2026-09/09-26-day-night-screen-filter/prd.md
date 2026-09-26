# 昼夜动态滤镜与平滑过渡

## Goal

在游戏画面上新增一层由 `TimeSystem` 时间状态驱动的**世界层滤镜**：白天近乎清透、黄昏转暖、夜晚明显变暗偏冷、黎明转淡青，并随时间平滑过渡，消除当前「瞬间切换」的突兀感。

玩家价值：让「白天 / 夜晚」在视觉上立刻可感知，强化昼夜循环带来的节奏感与氛围，而不牺牲 HUD/UI 的可读性。

## Background（已确认事实，含 file:line 锚点）

- **时间权威**：`core/autoloads/time_system.gd`。`PhaseLength = 100`（第 9 行）；`IsNight` 为布尔（第 28 行）；信号 `DayNightToggled(is_night)`（第 15 行）与 `TimeChanged(total_time_passed, current_day, is_night, phase_progress, phase_length)`（第 21 行，第 105 行发出）；`get_PhaseProgress()` 返回阶段内进度 `0..99`（第 39-40 行）。
- **时间是行为驱动的离散推进，没有逐帧实时流逝**：`PassTime` 的调用点为 `scripts/map_scripts/map_button/map_button.gd:268`、`scripts/map_scripts/DoorController.gd:268-269`、`core/gameflow/world_interaction_coordinator.gd:685`、`core/building/building_service.gd:87`、`core/ui/dev/dev_settings_ui.gd:272`。因此「随时间变化」在本项目中表现为「每次行动结算后时间点跳变」，平滑过渡必须能吸收这种跳变。
- **现有昼夜视觉表现只有一处，且无过渡**：`scripts/map_scripts/UIMapWorldView.gd:18` 的 `night_background_tint = Color(0.45, 0.45, 0.55, 1.0)`，在 `DayNightToggled` 时对每个活跃房间的 `Background` 精灵做一次 `self_modulate` 颜色乘算（`_apply_background_time_tint`，第 212-217 行）。它只影响房间背景贴图，不影响玩家、卡牌、建筑、战斗场景与任何 UI。
- **既有测试锁定了上述行为**：`tests/godot/passage_guard_tests.gd:302,321,322,326`、`tests/godot/test_reusable_gathering_interaction.gd:893,906`；其中 `passage_guard_tests.gd:302` 明确要求「夜晚战斗背景应当保留地图背景的变暗效果」。
- **场景结构**：探索主场景 `scenes/Main.tscn`，根节点 `Main`（第 58 行），UI 位于 `UI/HUDLayer`（第 131-133 行）；战斗是**独立场景** `scenes/battle_scenes/battle.tscn`，根节点 `Battle`（`Node2D`）。
- **两个场景的「世界 vs UI」边界机制不同**：探索侧 UI 全在 `CanvasLayer` 内（`UI/HUDLayer` 默认为 layer 1、`MapSystem/CanvasLayer` 在 `scenes/map_scenes/map_control.tscn` 中显式 `layer = 0`）；战斗侧 HUD **不是 `CanvasLayer`**，与怪物卡、手牌、背景同在默认 canvas，只能靠 `z_index` 划分。
- **世界内容的 `z_index` 事实**：探索世界最高为 `1000`（`core/board/board_card_view.gd:190`、`scripts/loot_scripts/loot_view.gd:193`）；战斗背景为 `-1000`（`battle.tscn:480`），战斗卡牌为 `1` / `2`（`core/card_visual_config.gd:27,30`）；战斗浮字层 `CombatFeedbackLayer` 是 `CanvasLayer`，`layer = 20`。
- **全屏覆盖先例**：`scenes/ui_scenes/ScreenTransitions.tscn` + `scripts/anim/ScreenTransitions.gd`，Autoload 常驻，`CanvasLayer layer=20` + 全屏 `ColorRect`，`process_mode = 3`（`scenes/ui_scenes/ScreenTransitions.tscn:45,49`）；`scenes/player_scenes/PlayerChar.tscn:12-36` 则示范了在 2D 表现层用材质覆盖的做法。
- **渲染后端为 `gl_compatibility`**：`project.godot` 中 `renderer/rendering_method="gl_compatibility"`（并非 Forward+），滤镜技术选型必须在该后端下可用。
- **Autoload 是本项目承载跨场景常驻逻辑的既有方式**：`project.godot` 的 `[autoload]` 已注册 `GlobalEventBus`、`SceneManager`、`ScreenTransitions`、`TimeSystem` 等。

## Requirements

- **R1 作用范围**：新增一层全屏滤镜，**探索场景与战斗场景的世界层都生效，HUD/UI 不受影响**。实现须在 `gl_compatibility` 下正常工作。两个场景的边界机制不同（探索靠 `CanvasLayer`，战斗靠 `z_index`），组件本身不得硬编码任何场景层级假设。
- **R2 时间驱动**：滤镜外观必须由 `TimeSystem` 的公开状态（`IsNight` + `PhaseProgress`）推导，**按阶段进度连续插值**：白天阶段随进度由中性渐入暖黄黄昏，夜晚阶段由冷蓝夜色渐入淡青黎明。推导规则集中在单一组件内；全部可调参数以 `@export` 暴露在脚本顶部，不得出现散落的魔法数字。
- **R3 平滑过渡**：滤镜值必须平滑跟随目标值而非直接赋值，使时间推进造成的进度跳变表现为可见渐变。**过渡必须对连续多次时间推进保持正确**：不得因上一次过渡未完成而累积出错误终点或卡在中途。过渡时长可配置。
- **R4 取代既有实现**：**新滤镜统一接管夜晚视觉，移除 `UIMapWorldView` 的 `night_background_tint` 瞬间变暗逻辑**；随之必须改写 `tests/godot/passage_guard_tests.gd` 与 `tests/godot/test_reusable_gathering_interaction.gd` 中依赖背景 `self_modulate == Color(0.45, 0.45, 0.55, 1.0)` 的断言，并同步改写 `docs/游戏机制与玩法内容.md` 的对应描述。原设计意图「夜晚战斗背景保留变暗效果」在改造后由滤镜在战斗场景生效来承载，不得因此丢失。
- **R5 无副作用**：滤镜只改变画面表现，不得影响时间推进、昼夜玩法规则（夜晚遭遇倍率、通道驻守）、战斗结算，也**不得拦截或改变玩家输入**（覆盖层必须忽略鼠标）。
- **R6 与既有全屏层协调**：滤镜层不得盖住 `ScreenTransitions` 的过场黑幕，也不得让过场漏出色差。
- **R7 参数前置**：全部可调数值（四段颜色、过渡时间、开关）集中在组件脚本顶部以 `@export` 暴露，支持在检查器中直接调试，并逐个附中文注释说明作用、取值范围与默认值原因。

## Acceptance Criteria

- [ ] **AC1**：白天阶段存在中性滤镜状态 —— 白天清晨时画面与当前版本无可察觉差异。
- [ ] **AC2**：夜晚阶段画面明显变暗且偏冷（`night_color` 可通过 `@export` 调整，默认整体亮度约为原始的 50%，与既有 `0.45/0.45/0.55` 的手感接近）。
- [ ] **AC3**：时间推进引起的阶段进度变化表现为可观察的渐变过渡，而不是瞬间跳变；在过渡进行中再次推进时间不会留下错误终点；天亮与天黑两个方向的过渡都成立。
- [ ] **AC3b**：同一昼夜周期内画面是连续的 —— 白天阶段随时间逐渐转暖变暗，夜晚阶段随时间逐渐转亮偏青，跨越阶段边界（黄昏→入夜、黎明→清晨）时不出现阶跃。
- [ ] **AC4**：夜晚时 HUD/UI 可读性保持 —— 探索场景的时间面板、血条、背包按钮、Tooltip 与白天亮度一致；战斗场景中血量条及其文字、能量条、属性面板、`TurnEnd`/`DrawCard` 按钮、设置面板、浮字层与白天亮度一致。
- [ ] **AC5**：`tests/godot/` 全量通过 —— 被改写的 `passage_guard_tests.gd` 与 `test_reusable_gathering_interaction.gd` 断言按 R4 迁移后通过，其余测试不得因本次改动失败。
- [ ] **AC6**：探索场景（`scenes/Main.tscn`）与战斗场景（`scenes/battle_scenes/battle.tscn`）冒烟运行，`logs_read(source="game")` 无 `SCRIPT ERROR`、无本次改动引入的资源加载错误；场景切换过程中滤镜不发生误过渡与闪烁。
- [ ] **AC7**：`docs/游戏机制与玩法内容.md` 中的昼夜表现描述与最终实现一致，并记录具体数值（四段颜色默认值、过渡时间），且明确记录「房间背景自变暗已移除」及其原因。
- [ ] **AC8**：滤镜覆盖层不拦截输入 —— 探索中卡牌拖拽、建筑交互与战斗中的按钮点击在滤镜启用后行为不变。

## Key Decisions

| 编号 | 决策 | 理由 |
|---|---|---|
| D1 | 滤镜作用于**探索 + 战斗的世界层**，HUD/UI 保持明亮 | UI 可读性优先；两个场景都在世界层需要夜色氛围 |
| D2 | **由新滤镜统一接管夜晚视觉，移除 `UIMapWorldView` 的瞬间变暗** | 避免两套真相与双重变暗，调参集中在一处；代价是必须改写两个测试文件与机制文档 |
| D3 | **按阶段进度连续插值（黄昏 / 黎明渐变）**，而非只在切换时做一次固定过渡 | 更贴合「随时间动态改变」的诉求；代价是每次行动后画面都会微调，验收需覆盖连续性 |
| D4 | **黄昏暖黄 + 夜晚冷蓝 + 黎明淡青**三段色调 | 与连续插值配套，一眼可辨「时间在走」；代价是参数比单一冷色多 |
| D5 | 战斗场景中**仅 Control UI 保持明亮**，世界 `Node2D`（背景、怪物卡、手牌、玩家）全部变暗 | 与场景树的架构划分一致（`Node2D` 是世界，`Control` 是 UI），且与探索侧观感统一 |

技术方案的选型与回落方案见同目录 `design.md`；执行顺序与验证清单见 `implement.md`。

## Out of Scope

- 不引入逐帧实时流逝的时钟（`TimeSystem` 保持行为驱动语义）。
- 不改造昼夜玩法规则与数值（夜晚遭遇倍率、通道驻守生成、天赋触发周期等）。
- 不为纯 UI 场景（`main_menu`、`Warehouse`、`Shop`，见 `core/autoloads/SceneManager.gd:7-11`）添加滤镜 —— 它们没有「世界层」。
- 不重做房间背景的美术配色（仅移除其自变暗逻辑）。
- 不新增滤镜的独立设置界面；运行期调试依赖组件的 `@export enabled` 开关与开发者面板既有能力。
