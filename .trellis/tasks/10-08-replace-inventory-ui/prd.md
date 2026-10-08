# 替换背包界面并分层重构

## Goal

使用 `scenes/inventory/OpenBackpack.tscn` 的当前美术布局替换主场景中的旧 `inventory_ui.tscn`，让玩家继续使用原有背包功能，同时把背包逻辑拆成 MVC 分层脚本。物品、角色装备和出战卡组都必须在新场景各自的 `ScrollContainer` 下动态生成格子，并统一使用 `scenes/ui/item_slot.tscn` 作为物品格子视图。

## Background and confirmed facts

- 主场景现已实例化 `scenes/inventory/OpenBackpack.tscn`，并由 `GameplayPort` 发送背包切换请求。
- 旧背包已经实现玩家库存、装备槽、出战卡组、属性摘要、合成入口、关闭按钮、拖拽、Shift/Alt 快捷转移，以及建筑物品的“放置”菜单。数据和规则由 `InventoryComponent`、`EquipmentComponent`、`BattleDeckComponent`、`AttributeComponent` 与 `GameplayPort` 提供。
- `OpenBackpack.tscn` 的 Item、PlayerShow、Deck 三个 `ScrollContainer` 已有对应的动态格子控制器；根节点为 `Control`，`mouse_filter = STOP` 会消费界面空白点击。
- `scenes/ui/item_slot.tscn` / `scripts/ui_scripts/item_slot.gd` 已被局外仓库和商店使用，入口为 `bind(item, amount, price, kind)`，并包含 `Icon`、`CountLabel`、`NameLabel`、`PriceLabel`。
- `item_slot.tscn` 现已在新背包、局外仓库和商店复用；背包格子有选中按钮状态与悬停提示，但各区域尚未保证单选。
- `docs/建筑系统.md` 明确规定背包普通左键菜单、拖拽与 Shift/Alt 快捷键必须互斥，选择“放置”时必须再次校验物品身份。
- `ClickWalkState` 在 `_unhandled_input()` 接收未被界面消费的左键；设置页通过 `SettingsManager` 保存偏好。

## Requirements

1. 主场景的背包实例改用 `OpenBackpack.tscn`，打开/关闭请求、合成请求、属性摘要和 Tooltip 依赖继续接通。
2. `Item/ScrollContainer`、`PlayerShow/ScrollContainer`、`Deck/ScrollContainer` 下分别创建物品、角色装备、出战卡组格子；格子数量随组件容量变化，普通刷新复用现有节点。
3. 所有物品格子实例来自 `scenes/ui/item_slot.tscn`。背包区域显示名称和数量并隐藏价格；角色展示区隐藏 `CountLabel`、`PriceLabel`；出战卡组隐藏 `CountLabel`、`PriceLabel`。局外仓库和商店已有的价格/数量语义必须保持不变。
4. 背包功能保持旧行为：库存与卡组拖拽移动、装备拖拽与卸下、Shift 单击移动单个技能堆叠或自动装备、Alt 单击批量移动技能卡、建筑卡左键菜单和二次校验、合成按钮、关闭按钮、属性刷新与 Tooltip。
5. 使用 MVC 多脚本分层：根 Controller 只协调生命周期和依赖；物品、角色装备、出战卡组三个区域 Controller 分别负责本区域格子创建/绑定/刷新；ItemSlot 只负责显示和输入意图；组件继续作为数据和规则 Model 权威。
6. 保留旧场景和旧脚本作为可回退实现，直到新场景通过 Godot 编辑器测试和主场景冒烟；本任务不删除旧资源。
7. 新增或修改的公共 GDScript 方法必须有中文 `##` 文档注释；复杂的信号绑定、二次校验和兼容分支必须写中文行内注释。
8. 背包打开期间，格子外的界面空白点击不得触发鼠标移动；关闭背包后世界点击仍正常。
9. 物品、角色装备、出战卡组各自最多一个深色选中格子。点击同区域另一格会取消前一格的变深状态；再次点击当前格子取消选中并关闭提示；空格子也可选中，但无物品信息。
10. 选中有物品的格子时在格子旁固定显示现有 Tooltip 名称和描述；悬停另一个未点击的格子时，同时显示随鼠标移动的悬停信息。鼠标移开只关闭悬停面板，固定信息仍在。同区域点击另一个格子时单选切换，旧固定面板关闭并显示新选中信息。同格再次点击关闭后，须移出再重新进入才能恢复该格悬停提示。普通物品不得显示“暂无可用操作”菜单。设置页增加持久化开关，默认开启，只控制选中后的自动信息，悬停行为不受影响。

## Acceptance Criteria

- [ ] 从 HUD 背包按钮打开的是 `OpenBackpack.tscn`，面板初始隐藏，关闭按钮可再次隐藏。
- [ ] 新场景三个 `ScrollContainer` 下分别出现物品、角色装备和卡组格子；容量变化时节点数量正确且刷新不会无故重建有效节点。
- [ ] 所有三个区域的物品格子均为 `ItemSlot` 实例；角色和卡组格子不显示数量与价格，背包格子不显示价格，仓库/商店旧显示规则不回归。
- [ ] 通过真实运行期验证拖拽、Shift/Alt、建筑“放置”二次校验、合成入口、属性摘要和 Tooltip 没有本次引入的脚本/资源错误。
- [ ] `tests/godot/` 中现有背包相关契约和性能测试迁移或补充到新节点路径后通过；新场景和 `scenes/Main.tscn` 冒烟无 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或本次修改资源加载错误。
- [ ] 关联模块文档及 `docs/游戏机制与玩法内容.md` 已说明新的背包 UI 入口、格子显示规则和 MVC 职责，且与实现一致。
- [ ] 背包内三个区域的格子外空白点击都不让人物移动；关闭背包后点击世界仍可移动。
- [ ] 三个区域分别只能有一个深色选中格子，切换格子、清空物品和关闭重开背包时选中与提示状态一致。
- [ ] 默认开启时选中有物品格子显示信息；悬停仍显示信息；关闭开关后选中不自动显示而悬停仍显示；重启游戏后开关值保留。

## Out of scope

- 不修改库存容量、装备规则、卡组规则、建筑放置规则、合成配方或 Tooltip 内容。
- 不删除 `scenes/inventory/inventory_ui.tscn`、`core/ui/inventory_ui.gd`、`SlotUI.tscn` 或 `EquipmentSlotUI.tscn`。
- 不重做 OpenBackpack 的美术资源、布局素材或主场景其他 HUD。
- 不修改角色移动状态机、物品内容或仓库/商店格子选择规则。

## Key decisions

- 用户确认新开关在没有本地偏好时默认开启。
- 每个区域独立单选，不要求三个区域之间互斥；背包选中使用独立固定 Tooltip 实例，悬停继续使用 HUD 共享 Tooltip 实例，两者可同时显示。
