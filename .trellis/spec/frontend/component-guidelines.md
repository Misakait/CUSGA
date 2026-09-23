# Component Guidelines

Godot UI and scene components use a mix of C# `Control` classes and GDScript scripts. Follow the existing Godot lifecycle and binding patterns.

## C# UI Controls

Use C# `Control` classes when the UI binds tightly to C# gameplay components.

Current examples:

- `InventoryUI` binds `InventoryComponent`, `EquipmentComponent`, and `BattleDeckComponent`, generates slot views once, then rebinds on inventory/equipment/deck changes.
- `CraftingUI` binds `CraftingComponent`, builds recipe buttons dynamically, refreshes ingredient rows, and maps `CraftingFailureReason` to status text.
- `SlotUI` and `EquipmentSlotUI` implement Godot drag/drop overrides and update visuals from `ItemStack.OnStackChanged`.

Pattern:

1. Resolve child controls and exported paths in `_Ready`.
2. Bind gameplay components through explicit `Bind*` methods.
3. Disconnect old component signals before rebinding.
4. Regenerate child view nodes only when capacity or slot count changes.
5. Use `QueueFree` for generated child controls.
6. Hide tooltips and unsubscribe stack events in `_ExitTree`.

For inventory-like repeated controls, synchronize bindings and structure incrementally:

- A `Bind` call should return early when the owner, index, and bound model reference are unchanged. Content changes arrive through the model's change event; reference changes caused by sorting must still perform a full unbind/rebind.
- Capacity growth should instantiate only the missing child views, and capacity reduction should remove only surplus views. Do not release and recreate still-valid controls.
- Keep one-time child configuration such as shared tooltip presenters and shortcut handlers on the creation path, then bind the new views in the normal rebind pass.

Long-lived UI may remain subscribed while hidden, but an expensive signal callback that only maintains presentation should guard with `IsVisibleInTree()`. Mark the presentation dirty while hidden, refresh once from current model state when `VisibilityChanged` reports effective visibility again, and let an explicit open path clear the dirty flag after its own complete refresh. This covers both direct `Hide()` calls and ancestor `CanvasLayer`/`CanvasItem` visibility changes. Do not defer gameplay state mutation.

Keep durable Godot runtime tests for structural UI optimizations. Assert stable child instance IDs across ordinary rebinds, preservation of existing child IDs during capacity growth, correct model references after sorting, and deferred refresh after ancestor visibility is restored.

## Drag And Drop

Inventory/equipment drag data is carried by `DraggableData`. UI controls should call component-level `Can*` methods in `_CanDropData` and component-level mutation methods in `_DropData`.

Do not duplicate inventory/equipment rules in UI code. `SlotUI` delegates to `InventoryComponent.CanReceiveItemFrom` and `MoveItemFrom`; `EquipmentSlotUI` delegates to `EquipmentComponent.CanEquipFromInventory`, `EquipFromInventory`, `CanMoveEquipment`, and `MoveEquipment`.

## GDScript Scene Scripts

Use GDScript when the behavior is primarily scene control, pointer input, animation, map buttons, battle turn flow, or editor tooling.

Current examples:

- `map_button.gd` handles direction buttons, passage guard checks, fade transitions, and map move time.
- `passage_guard_controller.gd` owns guard state, guard roll probability, and async battle requests.
- `battle_manager.gd` owns the battle state machine and delegates C# combat skill execution after target resolution.
- `card_manager.gd` owns card dragging, target highlighting, and input gating during player turns.

Prefer exported fields and `@onready` references for scene dependencies. Guard optional dependencies with null checks and `has_method`/`has_signal` before calling across a dynamic boundary.

## Tooltips

The current tooltip patterns are:

- C# item slots use `ItemTooltipPresenter`.
- `Monster.cs` searches the `tooltip_panel` group and falls back to a valid panel.
- `HoverTooltipComponent.gd` can auto-connect to parent `Control`, `Area2D`, or custom hover signals.

For new tooltip behavior, reuse these patterns instead of introducing a second global tooltip system.
## 用 Button 表达「悬停 / 选中」时的两个陷阱

### 1. Scope / Trigger

当用一个 `Button` 同时表达「鼠标悬停」和「已选中」两种状态，并且用 `StyleBoxTexture` + `region_rect` 从一张多帧贴图里取样式时，必须遵守本节契约。触发原因是这两条 Godot 行为都不直观，且错了以后界面「看起来能用」但语义是错的。

### 2. Signatures

```gdscript
# 用 Button 自己的切换态承载「选中」
toggle_mode = true
button_pressed = true          # 选中
button_pressed = false         # 取消选中
```

```ini
; .tscn 里的样式映射
theme_override_styles/normal   = SubResource("StyleBoxTexture_idle")
theme_override_styles/hover    = SubResource("StyleBoxTexture_hover")
theme_override_styles/pressed  = SubResource("StyleBoxTexture_selected")
theme_override_styles/focus    = SubResource("StyleBoxEmpty_focus")
```

### 3. Contracts

- **`focus` 样式会被叠画在按钮之上**，不是替换。若把 `focus` 指向与 `normal` 相同的贴图，按钮会渲染出**双重边框**。鼠标驱动的 UI 应把 `focus` 指向 `StyleBoxEmpty`（保留键盘焦点能力）或把按钮设为 `focus_mode = 0`。
- **`Button.get_draw_mode()` 的优先级是 `disabled > pressed > hover > normal`**。`toggle_mode` 打开且 `button_pressed == true` 时 `status.pressed` 持续为真，因此**已选中的按钮即使被鼠标悬停也仍画 `pressed` 样式**，不会被 `hover` 盖掉。这正是「`pressed` 承载选中态」这一映射成立的前提。
- 装空格子等不可交互的按钮要 `disabled = true`，否则玩家能「选中空气」，并让依赖选中项的动作区出现无意义的可用状态。
- 一张贴图只有两帧（未选中 / 选中）时，若同时要表达悬停与选中，**不要让两者共用同一帧**——玩家会分不出自己「正指着」还是「已经选中」。可行的分工是：悬停只做提亮（`StyleBoxTexture.modulate_color`），把「选中」那一帧严格留给选中态。
- 提亮幅度受帧本身亮度差限制。若素材常态帧亮度 132、选中帧 157，则悬停提亮只能夹在中间（约 1.12 倍），单独提亮边框会几乎看不出来；此时**再对格子内的图标做同倍率提亮**（图标是彩色像素画，同样倍率下肉眼可辨），既保住「悬停只提亮」的语义又让反馈可见。

### 4. Validation & Error Matrix

| 条件 | 症状 | 处理 |
|---|---|---|
| `focus` 样式沿用按钮贴图 | 按钮出现双重边框/重影 | 改用 `StyleBoxEmpty` |
| 悬停与选中共用同一帧 | 无法区分悬停与选中 | 悬停改提亮，选中独占该帧 |
| 已选中按钮被悬停 | 仍画 `pressed` 帧 | 符合预期，无需处理 |
| 空格子未禁用 | 可选中空气，动作区状态失据 | `disabled = true` |
| 提亮幅度设得接近选中帧亮度 | 悬停看起来比选中还亮 | 提亮值应严格低于选中帧亮度 |

### 5. Good / Base / Bad Cases

- Good：格子常态帧、悬停帧（常态 + `modulate_color` 1.12）、选中帧（贴图第二帧）三态亮度形成清晰梯度 132 → 148 → 157，悬停另有图标提亮 1.25 倍。
- Base：只用两帧并把第二帧同时给 `hover` 与 `pressed`，功能正常但玩家无法区分悬停与选中。
- Bad：`theme_override_styles/focus` 指向与 `normal` 相同的贴图，按钮渲染出双重边框。

### 6. Tests Required

- 对运行中的游戏断言三态：`button.is_hovered()` 为真时读取渲染像素，应等于「常态帧颜色 × 提亮倍率」；未悬停邻居应等于常态帧原色；`is_selected()` 为真时应画选中帧。
- 断言空格子 `disabled == true`。
- 断言所有按钮的 `focus` 样式不是按钮贴图（或 `focus_mode == 0`）。

### 7. Wrong vs Correct

#### Wrong

```ini
; focus 与 normal 同一张贴图 → Godot 把 focus 叠画上去 → 双重边框
theme_override_styles/normal = SubResource("StyleBoxTexture_yellow")
theme_override_styles/focus  = SubResource("StyleBoxTexture_yellow")
```

#### Correct

```ini
theme_override_styles/normal = SubResource("StyleBoxTexture_yellow")
theme_override_styles/focus  = SubResource("StyleBoxEmpty_focus")
```

## 复用战斗卡面：组件默认状态也是接口的一部分

### 1. Scope / Trigger

在非战斗界面里复用 `scenes/skill_card_scenes/SkillCard.tscn`（开局技能卡抽取，以及未来的卡牌浏览 / 奖励展示界面等）时。

### 2. Signatures

```gdscript
# core/gameflow/run_start_skill_card_draft.gd
var card_view: Node2D = CardScenePrefab.instantiate() as Node2D
slot.add_child(card_view)
card_view.position = CARD_SLOT_SIZE * 0.5
card_view.call("init_card_data", card)

# 必须显式对齐锁定态：SkillCard.tscn 的 LockColor 默认 visible = true
if card_view.has_method("unlock"):
	card_view.call("unlock")
```

### 3. Contracts

- `SkillCard.tscn` 里的 `LockColor`（`ColorRect`，210×150，黑色 alpha 0.31）在场景文件里**没有** `visible = false`，即新实例默认带着锁定遮罩。它由 `skill_card.gd` 的 `lock()` / `unlock()` 控制，而 `is_lock` 的默认值是 `false`——**场景默认状态与脚本默认语义并不一致**。
- 战斗语境下这个不一致由控制层补齐：`scripts/card_scripts/card_manager.gd` 会按 `control_lock` 状态对每张卡调用 `lock()` 或 `unlock()`。非战斗复用点**没有**这层控制层，必须自己调用 `unlock()`。
- 应调用公开协议 `unlock()`，**不要**直接写 `$LockColor.visible = false`：后者把卡面内部节点结构固化到调用方，卡面改结构时会静默失效。
- 也不要把 `SkillCard.tscn` 的 `LockColor` 默认值改成隐藏来"顺手修好"——那会改动战斗侧首帧表现（锁定态卡牌在第一次 `lock()` 之前不显示遮罩）。
- 用 `has_method("unlock")` 守卫：卡面场景由 `CardScenePrefab` 导出配置，可被替换成不含该协议的视图。

### 4. Validation & Error Matrix

| 现象 | 真实原因 | 处理 |
|---|---|---|
| 非战斗界面每张卡都被半透明黑块盖住，叠加背景遮罩后近乎全黑屏 | 漏调 `unlock()`，`LockColor` 保持场景默认的可见 | 挂载卡面后显式 `unlock()` |
| 换自定义卡面视图后抛 `Invalid call` | 新视图没有 `unlock` 协议而守卫缺失 | 调 `unlock` 前先 `has_method` 判断 |

### 5. Good / Base / Bad Cases

- Good：`_attach_card_view()` 在 `init_card_data` 之后以 `has_method("unlock")` 守卫调用。
- Base：卡面仅作展示、不需要任何交互时也要走同样的解锁步骤——`LockColor` 与交互无关，它是纯视觉状态。
- Bad：断言"界面引用了 `SkillCard.tscn`"就认为复用正确——那只证明引对了文件，证明不了对齐了状态。

### 6. Tests Required

- 桩卡面必须**复刻 `LockColor` 结构**（同样的尺寸与默认可见性），否则"漏调 `unlock`"这类缺陷在测试里不可见；断言点应落在"遮罩已隐藏且 `unlock()` 恰好被调用一次"。
- 运行期还需一次 `game_eval` 读真实卡面实例的 `LockColor.visible`——业务数据断言（抽了几张、进背包几张）**无法**发现全黑屏。

### 7. Wrong vs Correct

#### Wrong

```gdscript
slot.add_child(card_view)
card_view.call("init_card_data", card)   # 5 张卡各带一块默认可见的 LockColor → 近乎黑屏
```

#### Correct

```gdscript
slot.add_child(card_view)
card_view.call("init_card_data", card)
if card_view.has_method("unlock"):
	card_view.call("unlock")             # 对齐到「非锁定」状态
```

## 卡牌视觉参数必须只有一份来源

### 1. Scope / Trigger

需要让**第二个界面**复用战斗卡牌的手感（悬停缩放、置顶、选中抬升）时。触发原因是这类数值天然会被复制粘贴；两份副本一旦漂移，玩家就会在两个界面里感受到不同手感，而任何单侧改动都不会有人发现。

### 2. Signatures

```gdscript
# core/card_visual_config.gd —— 唯一来源，只有常量
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

```gdscript
# 消费方用 preload 常量访问，不依赖全局 class_name 的注册时机
const CARD_VISUALS := preload("res://core/card_visual_config.gd")

@export var card_hover_scale: Vector2 = CARD_VISUALS.CARD_HOVER_SCALE
```

### 3. Contracts

- 共享来源只放 `const`，且继承 `RefCounted` 而不是 `Node`：它不需要进场景树，也不该被实例化出状态。
- 消费方**保留原有 `@export` 的名字与可写性**，只把默认值换成引用常量。移除导出是破坏性改动：既有测试会用 `set("scale_tween_duration", 0.0)` 把动画时长置零以短路动画。
- GDScript **允许** `@export` 的默认值引用另一脚本的常量（已用探针验证解析无诊断）。因此不必退而使用"两边各写一份字面量 + 测试比对"的做法。
- 依赖方向必须单向：配置脚本不得 `preload` 任何游戏脚本，否则形成循环。
- 消费方用 `preload` 常量而不是 `class_name` 全局标识符：`class_name` 的注册依赖编辑器扫描时机，新建脚本后未 `scan` 时会在别的脚本里解析失败。
- 悬停与选中是**两种独立表现**：悬停改缩放与 `z_index`，选中改位置。选中的卡在鼠标移开后缩回常态、但**保持抬升**——这是刻意的，正是为了让"已选"在移开鼠标后依然可辨认。
- 悬停**不改颜色**：用 `modulate` 染色表达悬停会与"选中"抢语义，也与战斗侧不一致。

### 4. Validation & Error Matrix

| 现象 | 真实原因 | 处理 |
|---|---|---|
| 两个界面手感不一致 | 数值被复制成两份，其中一份被改过 | 提取到共享配置，两边 `preload` 同一份 |
| 新建配置脚本后消费方报 `Identifier not found` | `class_name` 尚未注册（编辑器还没扫描） | 改用 `preload` 常量，或先 `filesystem_manage(op="scan")` |
| 移除 `@export` 后既有测试报 `Invalid set index` | 测试依赖导出的可写性 | 保留导出名与类型，只换默认值的来源 |
| 悬停时卡面变色、与选中分不清 | 用 `modulate` 表达悬停 | 悬停只改缩放与层级 |
| 未入场景树的节点上创建 Tween 报错 | `Node.create_tween()` 要求节点在树内 | 显式分叉：树内走 Tween，树外直接落终值 |

### 5. Good / Base / Bad Cases

- Good：`card_manager.gd` 与 `run_start_skill_card_draft.gd` 都 `preload("res://core/card_visual_config.gd")`，改动只落在一处。
- Base：只有一处使用这些数值时，留在原脚本的 `@export` 里即可，不必提前抽取。
- Bad：在第二个界面里复制一份 `1.05 / 0.08 / 36.0` 并写注释"与战斗保持一致"——注释不会阻止漂移。

### 6. Tests Required

- 源码形状断言：两边都引用共享配置，且消费方仍保留原有 `@export` 名。
- 数值快照断言：共享配置里的值等于既有的战斗取值（1.0 / 1.05 / 0.08 / 36.0 / 0.12），防止"重构顺手改了手感"。
- 行为断言：悬停后卡面 `scale` 与 `z_index` 达到战斗的目标值、`modulate` 保持白色；选中后位置抬升恰好 `CLICK_SELECTED_LIFT_DISTANCE`，取消后回到基准。
- 运行期还需验证 Tween 的动画过程——编辑器里未入树的夹具只能断言终态。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 第二个界面：复制数值，靠注释维持一致
const HOVER_SCALE: Vector2 = Vector2(1.05, 1.05)   # 与战斗保持一致（希望如此）
```

#### Correct

```gdscript
const CARD_VISUALS := preload("res://core/card_visual_config.gd")
# 悬停与选中共用同一份数值来源
_tween_scale(card_view, CARD_VISUALS.CARD_HOVER_SCALE)
```
