# 技术设计

## MVC 边界

```text
GameplayPort / HUD 背包按钮
        ↓ 切换请求
InventoryUIController（OpenBackpack 根节点）
        ├─ InventorySectionController → ItemSlot 视图 → InventoryComponent
        ├─ EquipmentSectionController → ItemSlot 视图 → EquipmentComponent
        └─ DeckSectionController → ItemSlot 视图 → BattleDeckComponent
        ↓
AttributeSummaryUI / TooltipPresenter / Crafting 请求
```

- Model：现有玩家组件和 `GameplayPort`。它们拥有库存、装备、卡组、属性和业务校验；UI 不复制容量、堆叠或装备规则。
- View：`OpenBackpack.tscn` 的布局节点、`scenes/ui/item_slot.tscn`、属性摘要和 Tooltip。ItemSlot 提供统一显示配置和拖拽意图入口。
- Controller：根控制器只做打开/关闭、组件绑定、信号生命周期和跨区域快捷操作协调；三个区域控制器只管理自己直接的 `GridContainer`、格子实例和局部刷新。

## 场景与脚本调整

- 将 `OpenBackpack.tscn` 根节点改为可作为居中 UI 使用的 `Control`，保留现有美术节点坐标和 `CloseButton`；为 Item、PlayerShow、Deck 的滚动容器下增加明确的 `GridContainer` 节点。
- 新建 `core/ui/inventory/` 下的根、库存区域、装备区域和卡组区域控制器脚本；脚本通过稳定的公开 `Bind`/`Open`/`Close` 入口交互，不从根 View 硬编码访问区域内部格子子节点以外的细节。
- 扩展 `ItemSlot` 增加显示配置（是否显示数量/价格）和背包拖拽协议适配；`bind()` 的仓库/商店调用保持兼容。对装备区域若需要拖拽，使用 ItemSlot 的统一视图能力承载装备堆叠，同时保留槽位类型标签或由区域 Controller 注入。
- 把 `Main.tscn` 的 `InventoryUI` 外部资源替换为 `OpenBackpack.tscn`，并把实例化字段改为新根控制器需要的 `GameplayPortPath`、`TooltipPanelPath` 等导出值。
- 保留旧场景和旧脚本；测试若仍引用旧路径，新增兼容测试或把测试目标改为新场景，不删除旧实现。

## 数据流与生命周期

1. `_ready()` 解析按钮、区域容器、`GameplayPort` 和 Tooltip，连接背包切换信号并保持隐藏。
2. `Open(inventory)` 从 `GameplayPort.Player` 读取属性、装备和卡组，根 Controller 绑定三个区域 Controller，并让各区域按容量创建或复用格子。
3. 区域 Controller 通过 `GetStackAt` / `GetEquippedStack` 读取 Model，调用 ItemSlot 的 `Bind` 或装备绑定入口刷新 View。
4. Model 发出 `InventoryChanged`、`EquipmentChanged` 等事实信号后，只刷新对应区域并清除可能失效的建筑菜单快照。
5. 物品格子的点击、拖拽、Shift/Alt 只上报 Controller；Controller 再调用 Model 的 `Can*` / `Move*` / `Equip*` 接口。建筑“放置”提交前重新读取槽位，验证物品 Resource 身份后经 `GameplayPort.RequestPlaceBuilding` 发出请求。
6. `_exit_tree()` 断开所有信号，隐藏 Tooltip 和菜单，避免缓存场景重复响应。

## 兼容性和风险控制

- ItemSlot 的显示方法必须保留 `bind(item, amount, price, kind)` 签名和 `slot_clicked` 信号，确保仓库、商店现有脚本不变。
- 新背包场景使用专用 Controller 脚本，避免直接把旧 `inventory_ui.gd` 绑定到 `Node2D` 美术场景；旧实现继续作为回退。
- 由于 `OpenBackpack` 当前是 `Node2D`，若直接挂 `Control` 子树会导致 anchors 和居中布局失效；根节点改为 `Control` 是接入 `CenterOverlay` 的必要兼容调整。
- 装备区域需要同时满足“统一 ItemSlot 展示”和装备槽位类型/拖拽协议，采用 ItemSlot 的显示配置扩展与区域 Controller 传入槽位类型，不改变 EquipmentComponent 的接口。

## 回滚

若新场景冒烟出现资源或交互回归，只回退 `Main.tscn` 的外部资源和实例配置，恢复旧 `inventory_ui.tscn`；新场景及分层脚本保留，便于继续修复。
