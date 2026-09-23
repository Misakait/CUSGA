# 技术设计：抽卡界面悬停与选中动效照搬战斗系统

## 1. 现状

### 战斗系统（被照搬的一方）

`scripts/card_scripts/card_manager.gd`：

| 位置 | 内容 |
| --- | --- |
| `:35-42` | `@export` 视觉参数：`card_normal_scale = (1,1)`、`card_hover_scale = (1.05,1.05)`、`scale_tween_duration = 0.08` |
| `:69-72` | `click_selected_card_lift_distance = 36.0`、`click_selected_card_lift_duration = 0.12` |
| `:1019-1021` | `connect_card_signals()` 把卡面的 `hovered` / `hovered_off` 接到 `CardManager` |
| `:1045-1063` | `highlight_card(card, hovered)`：Tween 卡面 `scale`，`z_index` 1↔2，**不改颜色** |
| `:789-797` | `_animate_click_mode_card_selection()`：`position = hand_position + (0, -36)`，`TRANS_QUAD` + `EASE_OUT`，0.12s |

关键语义：**缩放属于悬停、位移属于选中**。`:67-68` 的注释写明抬升距离"独立于悬停缩放，确保玩家即使移开鼠标也能识别待确认卡牌"——所以选中的卡在鼠标移开后会缩回 `1.0`，但**仍然保持抬升**。

### 抽卡界面（被改造的一方）

`core/gameflow/run_start_skill_card_draft.gd`：

- `_show_cards()`（`:359-380`）为每张卡建 `Button` 占位，卡面 `Node2D` 挂在占位中心。
- `_refresh_selection_view()`（`:443-455`）直接给**占位**设 `slot.modulate = SELECTED_TINT / UNSELECTED_TINT` 与 `slot.scale = SELECTED_SCALE(1.06) / ONE`：既变色、又缩放，且没有位移与悬停反馈。

差异清单：① 缩放对象是占位而非卡面；② 数值是 1.06 而非 1.05；③ 有多余的颜色变化；④ 没有位置抬升；⑤ 没有悬停反馈；⑥ 数值硬编码在抽卡脚本里，与战斗各写一份。

## 2. 设计

### 2.1 共享来源：`core/card_visual_config.gd`

新建只含 `const` 的脚本，作为卡牌视觉数值的唯一来源：

```gdscript
class_name CardVisualConfig
extends RefCounted

const CARD_NORMAL_SCALE: Vector2 = Vector2(1.0, 1.0)
const CARD_HOVER_SCALE: Vector2 = Vector2(1.05, 1.05)
const SCALE_TWEEN_DURATION: float = 0.08
const CARD_Z_INDEX_NORMAL: int = 1
const CARD_Z_INDEX_HOVER: int = 2
const CLICK_SELECTED_LIFT_DISTANCE: float = 36.0
const CLICK_SELECTED_LIFT_DURATION: float = 0.12
```

`card_manager.gd` **保留全部 `@export` 名与类型**，只把默认值改为引用这些常量：

```gdscript
@export var card_normal_scale: Vector2 = CardVisualConfig.CARD_NORMAL_SCALE
@export var card_hover_scale: Vector2 = CardVisualConfig.CARD_HOVER_SCALE
@export var scale_tween_duration: float = CardVisualConfig.SCALE_TWEEN_DURATION
@export var click_selected_card_lift_distance: float = CardVisualConfig.CLICK_SELECTED_LIFT_DISTANCE
@export var click_selected_card_lift_duration: float = CardVisualConfig.CLICK_SELECTED_LIFT_DURATION
```

- **可行性已验证**：探针脚本 `@export var probe: String = preload(...).CONST` 解析后 `diagnostics: []`，GDScript 允许导出默认值引用另一脚本的常量。
- **为什么保留导出**：`tests/godot/target_selection_visual_tests.gd:106` 会执行 `card_manager.set("scale_tween_duration", 0.0)`；移除导出会让该测试失效。保留导出同时保留"测试把动画时长置零以短路动画"的能力。
- **依赖方向**：`card_manager.gd` → `card_visual_config.gd` 单向；配置脚本不引用任何游戏脚本，无循环。
- **场景覆盖**：`grep` 全部 `.tscn` 确认没有任何场景覆盖这些导出，因此改默认值等价于改实际生效的值。

### 2.2 抽卡界面的动效

在 `run_start_skill_card_draft.gd` 中：

- 新增 `_slot_card_views: Array[Node2D]` 与 `_card_view_base_positions: Array[Vector2]`，与 `_slot_views` 同索引。
- **悬停**：占位 `Button` 的 `mouse_entered` / `mouse_exited` → `_apply_card_hover(index, hovered)`：对**卡面**做 `scale` Tween（`CARD_HOVER_SCALE` ↔ `CARD_NORMAL_SCALE`，时长 `SCALE_TWEEN_DURATION`）+ `z_index`（`CARD_Z_INDEX_HOVER` / `CARD_Z_INDEX_NORMAL`），并显示 / 隐藏浮窗。
- **选中**：`_refresh_selection_view()` 改为对**卡面**做 `position` Tween：选中 → 基准位置 `+ Vector2(0, -CLICK_SELECTED_LIFT_DISTANCE)`；取消 → 回基准位置。缓动 `TRANS_QUAD` + `EASE_OUT`，时长 `CLICK_SELECTED_LIFT_DURATION`。
- 删除 `SELECTED_TINT` / `UNSELECTED_TINT` / `SELECTED_SCALE` 三个常量与 `slot.modulate`、`slot.scale` 赋值；`_on_slot_resized` 与 `pivot_offset` 不再需要（缩放改为以卡面原点为中心，而原点本来就在卡槽中心），一并移除。
- 位移以**基准位置数组**为基准，而不是读当前 `position`，避免反复悬停/点击累积偏移——与战斗 `:786` 注释同一考虑。

### 2.3 悬停触发来源

战斗靠卡面 `Area2D` 的 `mouse_entered` / `mouse_exited` 发 `hovered` 信号。抽卡界面里卡面被占位 `Button` 覆盖，`Button`（`MOUSE_FILTER_STOP`）会优先消费 GUI 事件，`Area2D` 收不到。因此改用占位 `Button` 自己的 `mouse_entered` / `mouse_exited` 驱动**相同的视觉效果**：视觉一致，仅触发来源不同。`SkillCard` 的 `hovered` 信号在该界面保持未连接（也就不引入对 `CardManager` 的依赖）。

### 2.4 浮窗

- 抽卡界面新增 `@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")`（`HUDRoot/SkillCardDraftScreen` → `HUDRoot/TooltipPanel`，与 `inventory_ui.gd:25`、`warehouse_ui.gd:15` 的既有范式同级）。
- 悬停调用 `show_tooltip(DisplayName, DisplayDescription)`，移出调用 `hide_tooltip()`；用 `has_method` 守卫，缺失时 `push_warning` 降级（浮窗不是开局必需依赖，不应阻断抽卡）。
- 文案取卡数据的 `DisplayName` / `DisplayDescription`，与卡面自身显示的文字同源。
- **`TooltipPanel` 必须无视暂停**：它的延迟显示与跟随鼠标都在 `_process`，渐现是 Tween，暂停下全部停摆。因此给 `scenes/ui_scenes/TooltipPanel.tscn` 根节点设 `process_mode = 3`（与 `pause_menu.tscn`、`talent_screen.tscn` 同一先例）。这是第三处既有文件改动，语义为"纯反馈浮层不受游戏暂停影响"。
- 层级：`TooltipPanel._ready()` 已设 `top_level = true` 与 `z_index = 100`；虽然它在 `HUDRoot` 下的顺序早于抽卡界面，但这两个设置保证它仍画在抽卡界面之上，无需改动。

## 3. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 改 `card_manager.gd` 伤到战斗行为 | 只改 5 个 `@export` 的默认值，取值与改动前逐字相同；导出名 / 类型 / 可写性不变；`target_selection_visual_tests` 与全量套件回归 |
| `TooltipPanel` 设 ALWAYS 影响全局 | 语义上纯反馈浮层不应被暂停冻结；暂停菜单是全屏遮罩，实际不会误触发悬停提示 |
| 悬停信号被 `Button` 吃掉导致无反馈 | 改用 `Button` 自身的 `mouse_entered` / `mouse_exited`，运行期用真实 GUI 事件验证 |
| 抬升后卡面与标题重叠 | 卡槽顶部 y=262，抬升 36 → 226；标题约在 y≈200–230，属轻微接近但不遮挡卡面主体；运行期用矩形 / 像素断言确认仍在视口内 |

## 4. 回滚单元

| 序号 | 回滚单元 | 影响面 |
| --- | --- | --- |
| R1 | 新增 `core/card_visual_config.gd` + `card_manager.gd` 的 5 个默认值改动 | 战斗视觉数值（取值不变，回滚后行为完全相同） |
| R2 | 抽卡脚本的悬停 / 选中动效 | 仅抽卡界面表现 |
| R3 | 浮窗接入（`TooltipPanelPath` + 显示 / 隐藏调用） | 仅抽卡界面表现 |
| R4 | `TooltipPanel.tscn` 的 `process_mode = 3` | 全局浮窗在暂停下的可用性 |

R1 单独保留不改变任何既有行为；R2 / R3 / R4 互不依赖。
