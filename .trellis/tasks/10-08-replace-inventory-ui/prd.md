# 替换背包界面并分层重构

## Goal

使用 `scenes/inventory/OpenBackpack.tscn` 的当前美术布局替换主场景中的旧 `inventory_ui.tscn`，让玩家继续使用原有背包功能，同时把背包逻辑拆成 MVC 分层脚本。物品、角色装备和出战卡组都必须在新场景各自的 `ScrollContainer` 下动态生成格子，并统一使用 `scenes/ui/item_slot.tscn` 作为物品格子视图。

## Background and confirmed facts

- 主场景当前通过 `scenes/Main.tscn` 实例化 `scenes/inventory/inventory_ui.tscn`，并由 `GameplayPort` 发送背包切换请求。
- 旧背包已经实现玩家库存、装备槽、出战卡组、属性摘要、合成入口、关闭按钮、拖拽、Shift/Alt 快捷转移，以及建筑物品的“放置”菜单。数据和规则由 `InventoryComponent`、`EquipmentComponent`、`BattleDeckComponent`、`AttributeComponent` 与 `GameplayPort` 提供。
- `OpenBackpack.tscn` 已包含 Item、PlayerShow、Deck 三个区域及对应 `ScrollContainer`，但当前三个滚动容器只有空的 HBox/VBox 子节点，根节点是 `Node2D`。
- `scenes/ui/item_slot.tscn` / `scripts/ui_scripts/item_slot.gd` 已被局外仓库和商店使用，入口为 `bind(item, amount, price, kind)`，并包含 `Icon`、`CountLabel`、`NameLabel`、`PriceLabel`。
- 局外仓库已经证明 `item_slot.tscn` 可以通过 `ItemSlot` 数组动态创建并按 `sell` 语义显示数量；背包区域需要继续支持拖拽和快捷操作，因此物品格子需要在不破坏仓库/商店接口的前提下增加背包绑定能力。
- `docs/建筑系统.md` 明确规定背包普通左键菜单、拖拽与 Shift/Alt 快捷键必须互斥，选择“放置”时必须再次校验物品身份。

## Requirements

1. 主场景的背包实例改用 `OpenBackpack.tscn`，打开/关闭请求、合成请求、属性摘要和 Tooltip 依赖继续接通。
2. `Item/ScrollContainer`、`PlayerShow/ScrollContainer`、`Deck/ScrollContainer` 下分别创建物品、角色装备、出战卡组格子；格子数量随组件容量变化，普通刷新复用现有节点。
3. 所有物品格子实例来自 `scenes/ui/item_slot.tscn`。背包区域显示名称和数量并隐藏价格；角色展示区隐藏 `CountLabel`、`PriceLabel`；出战卡组隐藏 `CountLabel`、`PriceLabel`。局外仓库和商店已有的价格/数量语义必须保持不变。
4. 背包功能保持旧行为：库存与卡组拖拽移动、装备拖拽与卸下、Shift 单击移动单个技能堆叠或自动装备、Alt 单击批量移动技能卡、建筑卡左键菜单和二次校验、合成按钮、关闭按钮、属性刷新与 Tooltip。
5. 使用 MVC 多脚本分层：根 Controller 只协调生命周期和依赖；物品、角色装备、出战卡组三个区域 Controller 分别负责本区域格子创建/绑定/刷新；ItemSlot 只负责显示和输入意图；组件继续作为数据和规则 Model 权威。
6. 保留旧场景和旧脚本作为可回退实现，直到新场景通过 Godot 编辑器测试和主场景冒烟；本任务不删除旧资源。
7. 新增或修改的公共 GDScript 方法必须有中文 `##` 文档注释；复杂的信号绑定、二次校验和兼容分支必须写中文行内注释。

## Acceptance Criteria

- [ ] 从 HUD 背包按钮打开的是 `OpenBackpack.tscn`，面板初始隐藏，关闭按钮可再次隐藏。
- [ ] 新场景三个 `ScrollContainer` 下分别出现物品、角色装备和卡组格子；容量变化时节点数量正确且刷新不会无故重建有效节点。
- [ ] 所有三个区域的物品格子均为 `ItemSlot` 实例；角色和卡组格子不显示数量与价格，背包格子不显示价格，仓库/商店旧显示规则不回归。
- [ ] 通过真实运行期验证拖拽、Shift/Alt、建筑“放置”二次校验、合成入口、属性摘要和 Tooltip 没有本次引入的脚本/资源错误。
- [ ] `tests/godot/` 中现有背包相关契约和性能测试迁移或补充到新节点路径后通过；新场景和 `scenes/Main.tscn` 冒烟无 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或本次修改资源加载错误。
- [ ] 关联模块文档及 `docs/游戏机制与玩法内容.md` 已说明新的背包 UI 入口、格子显示规则和 MVC 职责，且与实现一致。

## Out of scope

- 不修改库存容量、装备规则、卡组规则、建筑放置规则、合成配方或 Tooltip 内容。
- 不删除 `scenes/inventory/inventory_ui.tscn`、`core/ui/inventory_ui.gd`、`SlotUI.tscn` 或 `EquipmentSlotUI.tscn`。
- 不重做 OpenBackpack 的美术资源、布局素材或主场景其他 HUD。

## Open questions

无。现有代码和用户已确认的“功能不变”范围足以完成规划。
