# 昼夜动态滤镜 — 执行计划与结果

> 验证约定：所有运行时验证一律走已打开的 Godot 4.7.1 编辑器 MCP（`addons/godot_ai`），禁止 `godot-mono` CLI。
> 开始前先执行 `session_manage(op="list")` 或 `editor_state` 确认编辑器已加载 CUSGA。
>
> **执行状态：阶段 A–G 全部完成。**关键偏差与新增发现见文末「执行摘要」。

## 阶段 A：检索与确认（动手前必须完成）

- [x] A1 用 `grep` 全量检索 `night_background_tint`、`_apply_background_time_tint`、`_on_day_night_toggled`、`ORIGINAL_BACKGROUND_SELF_MODULATE_META`、`_find_background`、`_multiply_color`，确认除 `scripts/map_scripts/UIMapWorldView.gd` 与两个测试文件外无其它引用。
  - 结果：仅命中 `UIMapWorldView.gd` 与两个测试文件；`passage_guard_controller.gd`、`dev_settings_ui.gd` 的同名方法是各自类的私有实现，互不影响。
- [x] A2 用 `grep` 检索 `DayNightToggled` 的所有消费者，确认移除 `UIMapWorldView` 的订阅后，仍由 `scripts/map_scripts/passage_guard_controller.gd:35-45,86` 等既有消费者维持信号语义。
- [x] A3 读取 `tests/godot/passage_guard_tests.gd:270-340` 与 `tests/godot/test_reusable_gathering_interaction.gd:880-915` 的完整上下文，确认改写后的断言可以**保留原有测试意图**（复制房间、不影响同房间其它 Sprite 等）。
- [x] A4 读取 `scenes/Main.tscn` 与 `scenes/battle_scenes/battle.tscn` 的完整节点清单，确认新增节点的插入位置与被提升 `z_index` 的 `Marker2D`。

## 阶段 B：新增滤镜组件（新文件，零破坏面）

- [x] B1 新增 `core/ui/filters/day_night_filter.gd`（`extends ColorRect`）：
  - 顶部集中放置全部 `@export` 参数（`enabled` / `day_color` / `dusk_color` / `night_color` / `dawn_color` / `transition_time`），每个变量独占一段中文注释，说明作用、默认值原因与是否需要运行期修改；
  - `_ready()` 解析 `/root/TimeSystem`，缺节点时 `push_warning` 并保持中性，且**直接吸附**到目标颜色；
  - `_process(delta)` 每帧解析目标颜色并用 `1.0 - exp(-delta / tau)` 做帧率无关指数平滑；
  - 所有公开方法带 `##` 文档注释（参数、返回值、用途）；
  - 复杂处加「为什么这样做」的中文行内注释（为什么选指数平滑而不是 Tween）。
  - **补充**：新增 `_fit_to_viewport()`，用于修复「父级是 `Node2D` 时全屏 `Control` 尺寸退化为 0×0」的静默失效（见文末）。
- [x] B2 新增 `scenes/ui_scenes/day_night_filter.tscn`：
  - 根节点 `DayNightFilter`（`ColorRect`，脚本 `res://core/ui/filters/day_night_filter.gd`），`anchors_preset = 15` 全屏锚定，`mouse_filter = 2`（`MOUSE_FILTER_IGNORE`，**不得拦截输入**），`color = Color(1, 1, 1, 1)`；
  - `CanvasItemMaterial` 子资源赋值给根节点 `material`，`blend_mode = 3`（`BLEND_MODE_MUL`）。
  - **偏差**：设计写的是 `blend_mode = 1`，实际枚举值为 **`3`**（`1` 是 `BLEND_MODE_ADD`），已用 `api_manage(op="get_class")` 核实。
  - **补充**：`z_index = 1500` 内置在组件场景根节点，宿主场景不再写属性覆盖。
- [x] B3 `filesystem_manage(op="scan")` 刷新，确认脚本无解析错误。

## 阶段 C：挂载探索场景

- [x] C1 在 `scenes/Main.tscn` 根 `Main` 下实例化 `day_night_filter.tscn`，命名 `DayNightFilter`（`z_index = 1500` 由组件自带，高于世界最高的 1000：`core/board/board_card_view.gd:190`、`scripts/loot_scripts/loot_view.gd:193`）。
- [x] C2 `scene_save()` 保存，重新打开确认节点存在且属性正确。
- [x] C3 实测 1：`project_run` 该场景 → `logs_read(source="game")` 无 `SCRIPT ERROR`；白天画面为中性白（`color == Color(1,1,1,1)`、目标色同为中性）。
- [x] C4 实测 2：用 `game_eval` 把 `TimeSystem` 推到夜晚，确认滤镜色收敛到 `Color(0.61, 0.68, 0.83)`；再置纯黑滤镜采样世界像素，确认世界被压暗。
- [x] C5 实测 3：纯黑滤镜下世界采样点（`(1600,900)`、`(2300,1300)` 等）全部变黑，确认探索世界层（含 `z_index = 1000` 的卡牌与掉落物）被滤镜压住。
- [x] C6 实测 4：`map_control` 小地图面板**未被压暗**（纯黑滤镜下 `PanelContainer` 区域最大亮度仍为 `0.349`、943 个亮像素），说明 `CanvasLayer(layer = 0)` 依然绘制在默认 canvas 之上。
  - **兜底方案未启用**：`map_control.tscn` 与 `UI/HUDLayer` 的 `layer` 属性全部保持原值，改动面比设计预期更小。
- [x] C7 实测 5：纯黑滤镜下 HUD 文字最大亮度 `0.349`、背包按钮 `0.306`，与白天一致，确认夜间 HUD 不被压暗。
- [x] C8 `project_manage(op="stop")` 结束运行。

## 阶段 D：挂载战斗场景

- [x] D1 在 `scenes/battle_scenes/battle.tscn` 根 `Battle` 下实例化 `day_night_filter.tscn`，命名 `DayNightFilter`（`z_index = 1500` 由组件自带）。
- [x] D2 把 `Button`（`Marker2D`）与 `UI`（`Marker2D`）的 `z_index` 提升为 `2000`（高于滤镜；子节点默认 `z_as_relative`，无需逐个改）。
- [x] D3 `scene_save()` 保存。
- [x] D4 实测 1：`project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")`，`logs_read(source="game")` 无 `SCRIPT ERROR`。
- [x] D5 实测 2：夜晚下背景 / 怪物卡 / 手牌 / 玩家角色变暗（世界采样点在纯黑滤镜下全黑；夜晚世界像素 = 白天原色 × 滤镜色），而 `HpBar` / `HpText` / `PlayerAttributePanel`（`1.0`）、`TurnEnd`（`0.875`）保持明亮。
- [x] D6 实测 3：在 `CombatFeedbackLayer`（`layer = 20`）下挂探针 `Label`，纯黑滤镜下其最大亮度为 `1.0`，确认浮字层不被压暗。
- [x] D7 实测 4：卡牌悬停 `z_index = 2` 远低于滤镜 `1500`，且同属默认 canvas，由「世界采样点在纯黑滤镜下全黑」间接确认不会浮出滤镜层。
- [x] D8 `project_manage(op="stop")` 结束运行。

## 阶段 E：移除既有夜晚变暗（破坏性改动）

- [x] E1 按 `design.md` 第 3.1 节清单删除 `scripts/map_scripts/UIMapWorldView.gd` 中的夜间变暗代码，**保留** `_exit_tree()` 对 `map_world_model.current_room_changed` 的断开逻辑。
- [x] E2 删除后 `filesystem_manage(op="scan")` + 编辑器诊断，确认无解析错误、无「方法不存在」类运行期错误。
- [x] E3 读取改写后的 `UIMapWorldView.gd` 全文，确认无残留死代码、无未使用变量、中文注释仍然完整；文件头补充了「昼夜表现由滤镜承担」的说明注释。

## 阶段 F：测试与文档

- [x] F1 改写 `tests/godot/passage_guard_tests.gd`：原 `_test_map_instantiator_dims_loaded_backgrounds_without_touching_other_sprites` 改为 `_test_map_instantiator_keeps_room_sprite_colors_untouched`，断言「地图实例化器不修改任何 Sprite 颜色」并额外断言旧私有入口已不存在；`_test_background_resolver_uses_map_instantiator_current_scene` 的夜间语义迁移为中性的 `Color(0.8, 0.8, 0.8)`。
- [x] F2 改写 `tests/godot/test_reusable_gathering_interaction.gd`：`test_current_map_background_resolver_contract` 同上迁移（保留「复制背景忠实保留 `self_modulate`」的原意图）。
- [x] F3 `test_run()` 全量运行：440 通过 / 12 失败 / 39 跳过。12 个失败经 `git status` 核对，涉及的源文件均不在本次改动范围内，属既有失败（详见 `design.md` §6.3）。
- [x] F4 复核其余契约测试：`time_panel_ui_contract`、`dev_settings_contract`、`run_start_skill_card_contract` 等均通过；`world_interaction_coordinator_contract` 的 3 条失败涉及 `_run_screen_transition` 等既有入口，与本次改动无关。
- [x] F5 同步 `docs/游戏机制与玩法内容.md`：在「探索与战斗场景切换」下新增「昼夜屏幕滤镜」小节（作用范围、三段颜色与含义、`transition_time`、层级安排、移除房间背景自变暗的原因），数值与脚本默认值逐项一致。
- [x] F6 `grep` 检索 `docs/`、`MD/` 中描述「夜晚背景变暗」的段落，确认无遗漏需要修正的描述。
- [x] F7（新增）新建 `tests/godot/test_day_night_filter_contract.gd` 与转发壳 `tests/test_day_night_filter_contract.gd`，锁定颜色曲线、过渡收敛、缺 `TimeSystem` 降级、`Node2D` 父级自愈四条边界，4/4 通过。

## 阶段 G：收尾验证

- [x] G1 端到端冒烟：探索场景（夜晚）→ 通过真实遭遇入口 `RequestPassageGuardEncounter` 进入战斗 → 战斗结束返回探索；`MapSystem` 恢复可见、战斗实例移除、滤镜保持正确颜色，全程日志无 `SCRIPT ERROR`。进入战斗时滤镜 `current == target`，确认无初帧渐变或闪烁。
- [x] G2 `git status` 复核：改动仅限 `scenes/Main.tscn`、`scenes/battle_scenes/battle.tscn`、`scripts/map_scripts/UIMapWorldView.gd`、两个既有测试文件，以及新增的组件与测试文件；未覆盖用户已有改动。
- [x] G3 输出「学习反馈摘要」+「Git 提交描述」，追加写入 `临时反馈文档.md`（AGENTS.md 规范三、四、五）。

## 验证命令速查

| 目的 | 命令 |
|---|---|
| 刷新脚本 | `filesystem_manage(op="scan")` |
| 运行测试 | `test_run()` ；结果复查 `test_manage(op="results_get")` |
| 场景冒烟 | `project_run(mode="custom", scene="res://...")` |
| 日志 | `logs_read(source="game")` / `logs_read(source="editor")` |
| 运行期改时间 | `game_eval(code="...")`（例如调用 `/root/TimeSystem` 的 `PassageGuard`/`RestoreSnapshot`） |
| 画面确认 | `game_eval` + 视口像素采样（本项目把「从 Variant 推断类型」警告视为错误，eval 代码必须写显式类型） |
| 停游戏 | `project_manage(op="stop")` |

## 风险与回滚点

| 位置 | 风险 | 结果 / 回滚动作 |
|---|---|---|
| C6 | 提升 `map_control` / `HUDLayer` 的 `layer` 改变既有观感 | **未触发**：实测小地图面板未被压暗，`layer` 全部保持原值 |
| D2 | 提升战斗 `Marker2D` 的 `z_index` 影响既有叠放观感 | 已实测：滤镜之下的世界照常变暗、`UI`/`Button` 保持明亮，既有节点路径未变 |
| E1 | 删除 `UIMapWorldView` 逻辑后出现死引用 | 已按 A1 检索结果删除，`scan` 无解析错误 |
| F1 / F2 | 改写测试断言削弱既有契约 | 保留了原测试的其余断言，只迁移「谁负责变暗」这一条 |
| **新增** | 全屏 `Control` 挂在 `Node2D` 下静默失效 | 已用 `_fit_to_viewport()` 自愈并由契约测试锁定 |

## 完成判据

全部达成 `prd.md` 的 AC1–AC7：`test_run()` 中本次相关套件全绿、探索与战斗冒烟无 `SCRIPT ERROR`、机制文档与脚本默认值一致、端到端流程（探索 → 战斗 → 返回）通过。
