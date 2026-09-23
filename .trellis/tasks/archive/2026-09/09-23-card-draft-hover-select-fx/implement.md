# 执行计划：抽卡界面悬停与选中动效照搬战斗系统

## 0. 开工前检查

- 已完成调研：战斗侧参数与实现位置（`card_manager.gd:35-42`、`:69-72`、`:1045-1063`、`:789-797`）；`grep` 全部 `.tscn` 确认无场景覆盖这些导出；`target_selection_visual_tests.gd:106` 依赖 `scale_tween_duration` 可写。
- 已验证 GDScript 允许 `@export` 默认值引用另一脚本常量（探针解析 `diagnostics: []`，探针已删除）。
- 验证一律走编辑器 MCP（`test_run` / `project_run` + `game_eval`）；本次无 `.cs` 改动，`dotnet build` 门禁不适用。
- 抽卡界面的悬停效果必须在**暂停态**下验证（界面本身就让游戏处于 `paused`）。

## 1. 执行步骤

### S1 建立共享视觉配置

- 新增 `core/card_visual_config.gd`：`class_name CardVisualConfig` + `extends RefCounted`，只放 `const`；中文注释写明"卡牌视觉数值的唯一来源，战斗与抽卡界面共同读取"。
- 改 `card_manager.gd` 的 5 个 `@export` 默认值为引用该常量：保留名字、类型、`@export_group` 与原有注释，只**追加** `【修订说明】` 说明来源与为何保留导出。
- 验证：`test_run(suite="target_selection_visual_tests")` 以及手牌 / 战斗相关套件全绿。

### S2 抽卡界面接入动效

- `run_start_skill_card_draft.gd`：
  - 顶部 `const CARD_VISUALS := preload("res://core/card_visual_config.gd")`。
  - 新增 `_slot_card_views` / `_card_view_base_positions`，在 `_show_cards()` 与 `_attach_card_view()` 中填充。
  - 占位 `Button` 连接 `mouse_entered` / `mouse_exited` → `_apply_card_hover(index, hovered)`。
  - 新增 `_apply_card_hover`、`_set_card_view_lifted(index, lifted)` 等私有方法，统一持有 Tween 创建与参数读取。
  - `_refresh_selection_view()` 改为调用位移方法，移除 `modulate` 与 `slot.scale` 赋值。
  - 删除 `SELECTED_TINT` / `UNSELECTED_TINT` / `SELECTED_SCALE` 与 `_on_slot_resized` / `pivot_offset` 相关代码。
- 验证：契约套件新增用例先红后绿。

### S3 浮窗接入

- 新增 `@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")`，在依赖解析里取节点（允许为空）。
- 悬停显示 / 移出隐藏；`has_method` 守卫 + `push_warning` 降级。
- `scenes/ui_scenes/TooltipPanel.tscn` 根节点加 `process_mode = 3`。
- 验证：运行期悬停后断言浮窗 `visible == true` 且标题 / 描述文本正确，移出后隐藏。

### S4 契约测试

新增到 `tests/godot/test_run_start_skill_card_contract.gd`：

1. 悬停：桩卡面 `scale` 到 `CARD_HOVER_SCALE`、`z_index == 2`；移出回落 `CARD_NORMAL_SCALE`、`z_index == 1`。
2. 选中：卡面 `position` 相对基准上移 `CLICK_SELECTED_LIFT_DISTANCE`；取消回到基准。
3. 悬停 / 选中全程 `modulate == Color(1,1,1,1)`（不得再有变色）。
4. 浮窗：桩浮窗收到 `show_tooltip`（含正确卡名 / 描述）与 `hide_tooltip`。
5. 共享来源：读两边源码文本，断言 `card_visual_config.gd` 的常量值与 `card_manager.gd` 对应 `@export` 默认值一致——任何一处被单独改动都会失败。
6. 形状：`card_manager.gd` 仍保留 5 个 `@export` 名（防止后人"顺手"删导出而破坏既有测试契约）。
7. `TooltipPanel.tscn` 含 `process_mode = 3`。

### S5 运行期验证

1. `project_run(mode="custom", scene="res://scenes/Main.tscn")`。
2. `game_eval`：卡面初始 `scale == (1,1)`、`z_index == 1`、`modulate` 白。
3. `warp_mouse()` + `get_viewport().push_input(ev, true)` 悬停卡槽 → 等 Tween 结束 → 断言 `scale ≈ (1.05,1.05)`、`z_index == 2`、`modulate` 仍白、浮窗 `visible == true` 且文案正确。
4. 点击选中 → 断言 `position.y` 减少 36（容差 1px）；再次点击 → 回到基准位置。
5. 断言全程 `get_tree().paused == true`（证明效果在暂停下成立）。
6. 像素采样 `nonblack_ratio > 0` 确认画面正常。
7. `project_manage(op="stop")` 收尾。

### S6 全量回归与文档

- 全量 `test_run`：相对基线 372 passed / 2 个既有失败无新增红灯。
- `docs/游戏机制与玩法内容.md`：在「开局技能卡抽取」一节补悬停 / 选中表现与数值来源。
- `临时反馈文档.md`：追加学习反馈摘要 + Git 提交描述 + 时间戳。

## 2. 回滚点

见 `design.md` 第 4 节（R1–R4，相互独立）。

## 3. 完成判据

- PRD 的 9 条验收标准全部可复现通过（含暂停态下的运行期证据）。
- 新增契约用例全绿；全量套件无新增红灯。
- 战斗侧悬停 / 选中行为与改动前逐字一致（只换了数值来源，取值不变）。
