# 快捷装备与技能卡交互 Design

## Boundaries

- `InventoryComponent` 提供背包之间“移动到第一个可用槽”和“批量移动匹配物品”的组件级能力。
- `EquipmentComponent` 提供“从背包快速装备到最佳槽位”的组件级能力。
- `SlotUI` 只识别 Shift / Alt 左键点击，并把意图交给 `InventoryUI`。
- `InventoryUI` 根据来源是玩家背包还是出战卡组，决定调用卡组移动、批量移动或快速装备。
- `EquipmentSlotUI` 维持现有拖拽行为，本任务不增加装备槽点击卸下。

## Data Flow

1. 玩家在 `SlotUI` 上点击。
2. `SlotUI._GuiInput` 判断鼠标左键和修饰键，并触发 C# 回调。
3. `InventoryUI` 读取该槽绑定的 `InventoryComponent`、槽位索引和当前 `ItemStack`。
4. 背包技能卡 Shift 点击调用 `InventoryComponent.TryMoveStackToFirstAvailableSlot(_battleDeck, index)`。
5. 卡组技能卡 Shift 点击调用 `_battleDeck.TryMoveStackToFirstAvailableSlot(_playerInventory, index)`。
6. 卡组 Alt 点击调用 `_battleDeck.MoveAllMatchingStacksTo(_playerInventory, item => item is SkillCardData)`。
7. 背包技能卡 Alt 点击调用 `_playerInventory.MoveAllMatchingStacksTo(_battleDeck, item => item is SkillCardData)`。
8. 背包装备 Shift 点击调用 `_equipment.EquipFromInventoryToBestSlot(_playerInventory, index)`。

## Compatibility

- 组件方法复用现有 `MoveItemFrom`、`CanReceiveItemFrom` 和 `EquipFromInventory`，避免新建第二套搬运语义。
- 批量移动只选择空槽或可合并槽，避免不同物品之间发生意外交换。
- `BattleDeckComponent` 的自动扩容仍由组件自己的容量钩子处理。
- UI 回调绑定在生成 `SlotUI` 时完成，重新生成槽位后自动绑定新实例。

## Trade-offs

- 多槽位装备采用确定性顺序：优先空槽，再替换已有槽。这样不需要弹出选择 UI，符合“快捷”操作语义。
- 批量卸下遇到背包容量不足时移动可放下的部分，而不是全量失败；这与现有背包 `AddItem` 的部分成功语义一致。

## Rollback

- 回滚可集中撤销 `InventoryComponent`、`EquipmentComponent`、`SlotUI`、`InventoryUI` 和测试文件修改。
- 没有资源、场景结构或存档数据迁移。
