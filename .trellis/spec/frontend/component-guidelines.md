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
