# 背包新场景调查

- `scenes/Main.tscn` 当前实例化 `scenes/inventory/inventory_ui.tscn`，挂载在 `CenterOverlay/InventoryUI`。
- `scenes/inventory/OpenBackpack.tscn` 提供 Item、PlayerShow、Deck 三个视觉区，每个区有 ScrollContainer，但原场景只有 HBox/VBox 空容器，根节点为 Node2D。
- `scenes/ui/item_slot.tscn` 的 ItemSlot 目前提供统一显示、`bind(item, amount, price, kind)` 与 `slot_clicked`，局外仓库依赖该兼容签名。
- 旧 `core/ui/inventory_ui.gd` 集中实现组件绑定、槽位复用、拖拽、Shift/Alt、建筑菜单、合成请求和属性绑定；这些行为将迁移到新 Controller，旧实现保留回退。
- Model 公开接口包括 InventoryComponent 的容量/堆叠/跨库存移动、EquipmentComponent 的装备和卸下校验、BattleDeckComponent 的库存移动接口，以及 GameplayPort 的背包/建筑/合成请求。

# 依赖与风险

- `Main.tscn` 的新实例必须继续使用 `GameplayPortPath = NodePath("../../../../../Gameplay/GameplayPort")`。
- ItemSlot 扩展必须保留仓库/商店已有 `bind` 语义和 `slot_clicked` 信号。
- 新 GridContainer 继续使用 `%SlotGrid`、`%EquipmentSlotGrid`、`%DeckSlotGrid` 唯一名称，兼容现有性能测试与新场景契约。
- 空的背包/装备格仍需接收拖拽，因此 ItemSlot 不能把绑定到库存/装备的空格禁用。
