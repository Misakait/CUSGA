# C# 到 GDScript 迁移设计

## 总体策略

迁移采用“先建立等价 GDScript、再切换引用、最后删除 C#”的单模块闭环。每个模块先保留原实现作为行为对照，完成场景、Resource、测试和运行验证后才进入下一模块。

## 依赖分层

1. 常量、枚举、值对象和纯公式。
2. Godot `Resource` 数据类及其 `.tres` / `.res` 资产。
3. 纯逻辑服务和效果对象。
4. `Node` 组件、实体和 Autoload。
5. UI、场景控制器、地图和战斗流程。
6. 工程配置清理与 C# 文件删除。

当前项目有 200 个 C# 文件（其中 `.godot` 临时生成文件不属于项目源码；项目自有代码主要位于 `core/`、`entities/`、`resources/`、`tests/`），约 90 个现有 GDScript。高风险边界包括 Resource 脚本 UID、C# Autoload、场景导出字段、C# 与 GDScript 信号封送和动态 `Call`。

## 第一阶段：局外长按交互

范围：

- `core/gameflow/WorldHoldInteractionController.cs` → `core/gameflow/world_hold_interaction_controller.gd`
- `core/ui/hud/WorldHoldProgressIndicator.cs` → `core/ui/hud/world_hold_progress_indicator.gd`
- `scenes/Main.tscn` 对应脚本资源引用
- `tests/godot/world_hold_interaction_tests.gd` 测试入口和 API 名称
- `core/gameflow/WorldInteractionCoordinator.cs` 将强类型控制器字段改为 `Node`，通过稳定的 GDScript 方法名调用

兼容约束：

- `progress_indicator_path` 默认值必须保持 `../../../UI/HUDLayer/HUDRoot/WorldHoldProgressIndicator`。
- 零或负行动值直接调用完成回调；正值时长严格为 `max(cost, 0) / 10.0`。
- 开始新长按先取消旧状态；指定 owner 只能取消自身；完成前清空 Tween、owner、回调和圆环。
- 圆环仍使用目标 Sprite2D/Control 的屏幕空间右下角，目标无效时回退到鼠标位置。

## 后续阶段边界

后续先迁移 `core/constants` 与纯公式，再迁移 `resources/item`、`resources/interaction` 等 Resource 数据，随后迁移组件和 Autoload。暂不在第一阶段修改战斗公式、存档格式、节点结构或 UI 视觉参数。

## 装备组件并行边界

- `entities/components/equipment_component.gd` 先作为不挂载生产场景的并行实现，接受旧 C# 或新 GDScript ItemStack 的稳定属性与方法协议。
- EquipmentData/ToolData 字段必须经 `equipment_data_compat.gd` 读取；槽位和套装值使用 `equipment_types.gd` 的固定整数协议。
- `EquipmentChanged` 与 PascalCase 公共方法名保持不变。C# `TryGetEquippedStack(slot, out stack)` 无法由 GDScript 原样表达，并行实现以“返回堆叠或 null”表示同一查询结果；C# UI 迁移前不得替换玩家场景脚本。
- 属性和标签结算继续调用同级 `AttributeComponent` / `TagComponent` 的稳定方法；套装统计、拖拽交换、采集增益和火把倍率不得删减。
- 回滚点为删除并行脚本及其 GodotAI 契约测试；`EquipmentComponent.cs`、玩家场景、C# UI 和工具生产资产继续保留。

## DraggableData 并行边界

- `core/ui/draggable/draggable_data.gd` 只保存拖拽来源、槽位和堆叠引用，不执行库存或装备规则；`Can*` 与实际移动仍由对应组件负责。
- 六个 PascalCase 字段及默认值保持 C# 协议。来源组件以 `Node` 接受旧 C# 或并行 GDScript 实现，堆叠以 `RefCounted` 保留两种语言对象的引用身份，装备槽继续使用稳定整数值。
- 新脚本不声明 `class_name`，避免与 C# `DraggableData` 冲突。`SlotUI.cs`、`EquipmentSlotUI.cs` 及其场景在对应 UI 链迁移前继续创建和识别旧 C# 载荷。
- 回滚点为删除并行脚本、UID 和聚焦测试段；本批不切换生产场景、UI 脚本或存档格式。

## ItemTooltipPresenter 并行边界

- `core/ui/item_tooltip_presenter.gd` 继续只把 ItemStack / ItemData 转为标题和描述，并调用现有 TooltipPanel 的 `show_tooltip_now`、`hide_tooltip`；不持有或修改库存状态。
- C# 的两个 `Show` 重载在 GDScript 中合并为 `Show(Variant)`，先区分直接 Resource 与堆叠，再经 `item_data_compat.gd` 读取两种语言的物品字段；空值、空堆叠和无效物品继续隐藏提示框。
- C# ItemStack 的非导出公共属性不保证出现在 `get_property_list()`，并行 Presenter 以两种实现共同保留的 `Clear`、`SetItem`、`Duplicate` 方法协议识别堆叠，再读取 `IsEmpty` 与 `Item`。
- `Empty()` 缓存空 Presenter，保持旧静态空对象的共享语义。生产 `InventoryUI`、`WarehouseUI`、`SlotUI`、`EquipmentSlotUI` 在各自迁移前继续使用 C# Presenter。

## EquipmentSlotUI 并行边界

- `core/ui/equipment_slot_ui.gd` 保持 `EquipmentSlotUI.tscn` 的既有子节点路径、16 个槽位中文文案、图标/数量刷新、提示框和拖拽预览参数。
- UI 只通过 `CanEquipFromInventory`、`EquipFromInventory`、`CanMoveEquipment`、`MoveEquipment` 委托规则和状态修改；拖拽载荷按旧 C# / 新 GDScript 脚本路径识别，不在视图内复制装备判断。
- C# `TryGetEquippedStack(slot, out stack)` 不能由 GDScript 以单参数调用；并行 UI 优先接受未来无 out 的 `GetEquippedStack(slot)` 桥，并兼容当前 GDScript `TryGetEquippedStack(slot)`。生产 C# EquipmentComponent 与 C# InventoryUI 未切换前继续使用旧 C# EquipmentSlotUI。
- `EquipmentChanged` 后的槽位重绑仍由外层 InventoryUI 负责，单个槽位不私自订阅组件或重算状态；ItemStack 自身有 Godot 信号时只刷新当前视觉。

## SlotUI 并行边界

- `core/ui/slot_ui.gd` 保持 `SlotUI.tscn` 的 ItemIcon / AmountLabel 节点路径、等宽尺寸、公开 SlotIndex / Inventory / CurrentStack、提示框和拖拽预览参数。
- `SlotShortcutKind` 明确固定为 ShiftClick=0、AltClick=1；GDScript 用 Callable 替代 C# `Action<SlotUI, SlotShortcutKind>`，Alt 优先于 Shift，并只处理按下的左键。
- 库存互移继续调用目标 InventoryComponent 的 `CanReceiveItemFrom` / `MoveItemFrom`，装备卸下继续调用来源 EquipmentComponent 的 `CanUnequipToInventory` / `UnequipToInventory`；视图不复制容量、标签或装备规则。
- 新 UI 接受旧 C# / 新 GDScript DraggableData 和 ItemStack 的稳定字段。没有 Godot ItemStack 信号的旧对象在 Bind 时刷新，后续组件变化仍由外层 InventoryUI / WarehouseUI 统一重绑。

## WarehouseUI 并行边界

- `core/ui/warehouse/warehouse_ui.gd` 保持生产场景的 `SlotPrefab`、`GameplayPortPath`、`TooltipPanelPath` 序列化键和既有必需节点路径，不改变两栏仓库布局或关闭按钮样式。
- `WarehouseRequested`、玩家 `InventoryChanged` 与仓库 `InventoryChanged` 通过 Godot 信号名动态连接；公开 `Open` / `Close` 方法继续使用 PascalCase，库存参数以 `Node` 接受旧 C# 或并行 GDScript 组件。
- 父面板只按容量生成槽位、设置共享 Presenter 并统一重绑；堆叠展示、快捷输入和拖放规则仍由 SlotUI 与库存组件负责。相同容量刷新必须复用既有槽位节点。
- `warehouse_ui.tscn` 与 `SlotUI.tscn` 暂时继续引用 C#。GDScript WarehouseUI 不能把新 Presenter 传给强类型 C# SlotUI；必须等 InventoryUI 迁移后统一切换共享 SlotUI 场景，避免破坏另一位父 UI。
- 回滚点为删除并行 WarehouseUI 脚本、UID 和聚焦测试段；旧 `WarehouseUI.cs`、生产场景和 C# SlotUI 完整保留。

## InventoryUI 并行边界

- `core/ui/inventory_ui.gd` 保持生产场景的 `SlotPrefab`、`EquipmentSlotPrefab`、`GameplayPortPath`、`TooltipPanelPath` 四个序列化键，以及背包、装备、出战卡组和属性摘要的既有节点路径。
- `InventoryToggleRequested`、`InventoryChanged`、`EquipmentChanged` 通过稳定 Godot 信号名动态连接；父面板只负责三组槽位的创建、复用、重绑与快捷请求转发，不复制库存、装备或卡组规则。
- Shift 单击继续在背包、出战卡组与最佳装备槽之间移动单个堆叠；Alt 单击继续批量移动技能卡。合成按钮必须先关闭背包，再调用 GameplayPort 的 `RequestOpenCrafting`，保持旧 UI 切换顺序。
- 新父面板使用 Callable 配置 GDScript SlotUI，并通过动态方法读取 Inventory、BattleDeck 和 Equipment。生产 `InventoryUI.cs` 仍强类型实例化两个 C# 槽位类型，因此 `inventory_ui.tscn`、`SlotUI.tscn`、`EquipmentSlotUI.tscn` 必须等待玩家三组件与共享 UI 链一同就绪后再统一切换。
- 回滚点为删除并行 InventoryUI 脚本、UID 和新增聚焦测试段；旧 `InventoryUI.cs`、生产场景、Crafting 和玩家组件完整保留。

## HUD 背包与合成输入桥边界

- `core/ui/hud/hud_controller.gd` 保持 `GameplayPortPath`、`BackpackButtonPath` 两个 PascalCase 序列化键；合成仍在 `_input` 阶段处理，背包仍在 `_unhandled_input` 阶段处理。
- 两个快捷键继续忽略键盘 echo，并严格保持“先调用 GameplayPort，再把输入标记为 handled”的时序。HUDController 只校验背包按钮路径，不重复连接按钮事件。
- `core/ui/hud/backpack_button.gd` 继续只调用 `RequestToggleInventory`，不持有 InventoryUI 或 InventoryComponent。GameplayPort 暂时仍可为 C#，通过稳定方法名维持跨语言边界。
- Main 场景可以直接切换这两个叶子 UI 脚本；旧 C# 文件和 UID 保留为对照与最终清理输入。回滚点为把 Main 的两条 ext_resource 恢复到旧 C# 路径并删除新脚本、UID 和测试段。

## AttributeSummaryUI 并行边界

- `core/ui/attribute_summary_ui.gd` 保持公开 `Bind`、生产场景全部唯一节点名、详情弹窗和 AttributeChanged / AvailablePointsChanged 刷新时机。
- 15 个 AttributeType 继续使用 C# `Attributes.cs` 的固定整数顺序 0..14；GDScript 通过 Node、稳定信号名和 `GetEffectiveValue(int)` 读取现有 C# AttributeComponent，不承担属性计算。
- 普通数值继续使用整数或最多一位小数；百分比乘以 100 后保持最多一位小数；穿透继续显示为“固定值 | 比率%”。空绑定时全部显示 `-`。
- 生产 `InventoryUI.cs` 仍以 `GetNode<AttributeSummaryUI>` 强类型获取该视图，因此 `AttributeSummaryUI.tscn` 暂时继续引用 C#。回滚点为删除并行脚本、UID和独立测试入口，不影响生产场景。

## HealthBarUI 生产迁移边界

- `core/ui/hud/health_bar_ui.gd` 保持 `GameplayPortPath` 的 PascalCase 序列化键、`%HealthBar` / `%HealthLabel` 节点路径，以及“当前值 / 上限”的文本格式。
- 视图继续从现有 GameplayPort 的 `PlayerHealth` 获取生命组件，只依赖 `ValueChanged`、`CurrentValue`、`MaxValue` 稳定协议；生命上限、伤害、恢复与死亡规则仍由原组件负责。
- 重复绑定同一组件不重复连接，切换组件先解除旧信号，退出场景树时清理当前连接；不把生命状态复制进 UI。
- Main 场景只切换 HealthBarUI 这一叶子脚本。旧 `HealthBarUI.cs` 与 UID 保留到最终清理；回滚点为恢复 Main 的旧 ext_resource 并删除新脚本、UID 和聚焦测试入口。

## TimePanelUI 生产迁移边界

- `core/ui/hud/time_panel_ui.gd` 保持 `%DayLabel`、`%PhaseLabel`、`%TimeLabel`、`%PhaseProgress` 节点路径，以及“第 N 天”“白天/夜晚”“进度 / 长度”文案格式。
- 视图继续从 `/root/TimeSystem` 读取 `CurrentDay`、`IsNight`、`PhaseProgress`，并订阅五参数 `TimeChanged`；不修改时间流逝、昼夜切换、天数增长或天赋触发规则。
- C# `PhaseLength` 是不能通过 Autoload 实例动态读取的静态常量。TimeSystem 单独迁移前，视图以同值常量 100 完成初始刷新；后续信号刷新始终使用信号携带的 `phaseLength`，聚焦测试锁定两条路径。
- Main 场景只切换 TimePanelUI 这一叶子脚本。旧 `TimePanelUI.cs` 与 UID 保留到最终清理；回滚点为恢复 Main 的旧 ext_resource 并删除新脚本、UID 和聚焦测试入口。

## LootTable 并行边界

- `resources/loot/loot_table.gd` 保持 `Drops` 序列化键、0..100 浮点掷骰、小于等于命中、包含两端的整数数量范围、yieldGrowth 加成及最终数量非正过滤。
- Drops 使用 `Array[Resource]`，同时接受旧 C# 与新 GDScript LootDrop 字段协议；物品保持原 Resource 引用，生成结果使用已验证的并行 `resources/item/item_stack.gd`。
- 新脚本不声明 `class_name`，避免与 C# `LootTable` 全局类型冲突。C# LootComponent、GatheringInteraction、ReusableGatheringInteraction 与 MonsterData 仍要求 C# LootTable / ItemStack，因此 62 个生产资产暂不切换。
- 回滚点为删除并行脚本、UID 和 reusable_gathering 中的聚焦测试；旧 C# LootTable、全部生产资产和消费者保持不变。

## LootComponent 并行边界

- `entities/components/loot_component.gd` 保持 `DropTable` 序列化键和公开 `TriggerDrop(Vector2, int)` 方法，只负责调用掉落表并广播 `on_entity_dropped`。
- DropTable 使用通用 Resource，可接受旧 C# LootTable 或并行 GDScript LootTable；结果保持原 Array 与堆叠对象身份，组件不复制概率、数量或库存规则。
- `/root/GlobalEventBus` 与信号名、参数顺序保持不变。生产 `Monster.cs` 仍以 `GetNodeOrNull<LootComponent>` 强类型读取组件，因此怪物场景继续挂载 C#。
- 回滚点为删除并行脚本、UID 和独立聚焦测试；旧 `LootComponent.cs`、Monster 与场景不修改。

## FactionComponent 生产迁移边界

- `entities/components/faction_component.gd` 只保存 `Faction`，并固定 Hostile=0、PlayerSummon=1、Neutral=2，与 C# `MonsterFaction` 序列化整数一致。
- `Monster.cs` 的组件成员降为 Node，仍从 `Components/FactionComponent` 获取，并在 Initialize 中通过稳定 `Faction` 属性写入相同整数；不改变 MonsterData、目标选择或战斗规则。
- `monster.tscn` 只切换 FactionComponent 的脚本和 metadata UID，节点名、唯一名称、父子结构及默认值 0 保持不变。
- 旧 `FactionComponent.cs` 与 UID 保留到最终清理。回滚点为恢复 Monster 的强类型字段/赋值、场景旧 ext_resource 和 metadata，并删除新脚本及测试。

## LootComponent 生产切换边界

- 在并行契约通过后，`Monster.cs` 的私有 Loot 成员降为 Node，仍从 `Components/LootComponent` 获取，并通过稳定 `TriggerDrop` 方法维持死亡时序。
- `monster.tscn` 只切换 LootComponent 的脚本和 metadata UID；场景原本未序列化 DropTable，新组件继续保持 null 和空表短路，不在语言迁移中改变掉落初始化。
- MonsterData 虽有 LootTable，但现有 Monster.Initialize 没有写入组件；这是既有链路风险，本批只记录而不修复。
- 旧 `LootComponent.cs` 与 UID 保留到最终清理。回滚点为恢复 Monster 私有强类型字段/调用和场景旧引用。

## TagComponent 并行边界

- `entities/components/tag_component.gd` 保持 `AddTag`、`RemoveTag`、`HasTag`、`GetTagStack` 四个 PascalCase 方法，以及 StringName 标签和正整数叠层语义。
- 空标签继续忽略；重复添加逐层增加；移除只递减一层并在小于等于零时删除；缺失标签查询返回 0。
- Player、EquipmentComponent、TagTalentEffect 与旧 C# PassageGuardProbabilityProvider 仍有强类型边界，因此 `player.tscn` 暂不切换；GDScript Equipment / PassageGuard 已能通过同名方法兼容新实现。
- 回滚点为删除并行脚本、UID 和独立聚焦测试；旧 C# 文件、玩家场景和调用方保持不变。

## TagComponent 生产切换边界

- `scenes/player_scenes/player.tscn` 只把 `Components/TagComponent` 的脚本切换为已验证的 `entities/components/tag_component.gd`，节点名、路径、父子结构和零标签初始状态保持不变。
- `Player.TagComponent` 与 `EquipmentComponent` 的私有标签引用降为 `Node`；装备、套装与天赋继续通过 `AddTag` / `RemoveTag` 稳定方法名操作同一组件，不迁移或复制装备、套装、天赋规则。
- 保留的 C# `PassageGuardProbabilityProvider` 以 `Node` 接受旧 C# 或新 GDScript 标签组件，先确认 `HasTag` 方法存在再动态调用；缺少协议时按“没有所需标签”安全退化。
- 旧 `TagComponent.cs` 与 UID 保留到最终清理。回滚点为恢复四个 C# 消费者的强类型声明/调用、玩家场景旧 ext_resource，并保留现有 GDScript 并行实现和契约测试。

## DebugLoadout 生产迁移边界

- `debug_loadout_data.gd` 保持五个 PascalCase 序列化字段，四组条目数组放宽为 `Array[Resource]`，允许旧 C# 和新 GDScript 条目在迁移期共存。
- 固定物品条目继续实例化保留的 C# `ItemStack` 并传入原 C# ItemData Resource；动态装备条目继续实例化 C# `EquipmentData` / `ToolData`，避免当前 C# InventoryComponent、BattleDeckComponent 和 EquipmentComponent 的强类型参数失配。
- `debug_loadout_seeder.gd` 只通过稳定节点路径、属性名和 PascalCase 方法调用玩家组件；清空顺序、填充顺序、初始属性条件、16 个装备槽与 ApplyOnce 时序保持不变。
- `.tres` 中六个旧 `TargetGatheringTag = null` 归一为等价的空 StringName，继续生成普通装备，不改变工具判断。
- 旧四个 C# DebugLoadout 文件和 UID 保留。回滚点为恢复 `default_inventory_loadout.tres` 的三个旧脚本引用与 Main 的旧 Seeder 引用；新 GDScript 与测试可保留为并行实现。

## AttributeSummaryUI 生产切换边界

- `scenes/inventory/AttributeSummaryUI.tscn` 只把根节点脚本切换为已验证的 `attribute_summary_ui.gd`，36 个节点、唯一名称、样式、文案和弹窗结构保持不变。
- `InventoryUI.cs` 的摘要视图字段降为 `Node`，仍从 `%AttributeSummaryUI` 获取同一节点，并在原 Open 时序通过 `Bind` 方法名传入同一个 AttributeComponent。
- 新视图继续只依赖 `GetEffectiveValue(int)`、AttributeChanged 和 AvailablePointsChanged；15 个 AttributeType 整数、格式规则和属性计算均未改动。
- 旧 `AttributeSummaryUI.cs` 与 UID 保留。回滚点为恢复 InventoryUI 的字段、节点获取和 Bind 强类型调用，以及场景旧脚本引用。

## 共享背包 UI 链生产切换边界

- `InventoryUI`、`WarehouseUI`、`SlotUI` 与 `EquipmentSlotUI` 必须作为一个共享链切换；两个父面板都实例化同一个 `SlotUI.tscn`，不能混用 C# Presenter/DraggableData 与 GDScript 槽位。
- 四个生产场景只替换脚本引用，继续保留原导出字段、节点路径、信号名、快捷键、拖放委托、关闭按钮样式和属性摘要绑定时序。
- `EquipmentComponent.GetEquippedStack(EquipmentSlot)` 是只读跨语言桥，返回原 ItemStack 或 null，解决 GDScript 无法调用 C# `out` 参数的问题；装备规则、槽位字典和信号仍由原组件负责。
- 普通槽、装备槽和父面板继续通过 Node、PascalCase 方法及 Godot 信号与现有 C# Inventory、BattleDeck、Equipment、ItemStack 和 ItemData 交互，不复制业务数据或规则。
- 旧四个 C# UI 文件与 UID 继续保留。回滚点为恢复三个已跟踪 inventory 场景和仓库场景的旧脚本引用，并移除 `GetEquippedStack` 桥；不删除已经验证的并行 GDScript。

## VaultInteraction 生产迁移边界

- `vault_interaction.gd` 保持唯一序列化字段 `TimeCost=20`，继续按“pass_time → enter_vault”顺序描述密库交互，不读取或修改玩家、地形状态。
- `TerrainInteractionExecutor` 只新增 `enter_vault` 描述到既有 `EnterVaultOp` 的映射；时间推进、GameplayPort 仓库请求、Inventory 和 WarehouseUI 规则均不搬入 Resource。
- 正耗时交互会收到长按开始时的第三个耗时快照参数。新脚本为兼容统一调用签名而接收该参数，但保持旧 VaultInteraction 行为，仍使用自身 `TimeCost`。
- 火山地图只替换密库子资源脚本并移除旧自定义类型 metadata，CardId、CardName、CardIcon、地形池和布局配置保持不变。
- 旧 `VaultInteraction.cs`、UID、TerrainInteraction 基类和 `EnterVaultOp` 保留。回滚点为恢复火山场景旧脚本/metadata、移除执行器映射和新脚本。

## BossInteraction 生产迁移边界

- `boss_interaction.gd` 保持 `TimeCost=20` 与原 `MonsterData` Resource 引用，继续按“pass_time → spawn_monster → remove_source_card”顺序描述 Boss 交互。
- `TerrainInteractionExecutor` 只新增 `spawn_monster` 与 `remove_source_card` 描述映射，分别复用既有 `MonsterSpawnOpOp` 和 `RemoveSourceCardOp`；遭遇请求、战斗切换、怪物生成与源卡移除仍由原 C# TerrainOp 和 GameplayPort 执行。
- 正耗时交互会收到第三个耗时快照参数。新脚本接收但忽略该参数，保持旧 BossInteraction 始终使用自身 `TimeCost` 的行为。
- Boss 房间和雪原只替换 Boss 子资源脚本并移除旧自定义类型 metadata；MonsterData 继续使用原 C# Resource，CardId、名称、图标、地图布局与怪物数值均不修改。
- 旧 `BossInteraction.cs`、UID、`MonsterSpawnOp.cs` 与 `RemoveSourceCardOp.cs` 保留。回滚点为恢复两个地图场景的旧脚本/metadata、移除执行器的两个映射分支和新脚本。

## GatheringInteraction 生产迁移边界

- `gathering_interaction.gd` 保持 `TimeCost=20`、`GatheringTag` 与 `DropTable` 三个序列化字段；DropTable 继续引用原 C# LootTable，物品 Resource 和 C# ItemStack 生成边界不变。
- 操作顺序严格保持“pass_time → mark_harvested → 可选 spawn_loot → check_gathering_encounter → remove_source_card”。掉落只在构建操作时 `IsHarvested=false` 才滚动；已采集输入仍保留时间、标记、遭遇检查和移除行为。
- `TerrainInteractionExecutor` 只新增 `mark_harvested` 到既有 `MarkHarvestedOp` 的映射；时间、掉落生成、遭遇请求和棋盘移除继续由原 C# TerrainOp 与端口执行。
- 3 个直接地形卡、6 个群系 Profile 和沙漠地图共 10 个生产资产统一切换新脚本；`create_terrain_profiles.gd` 同步使用新路径，防止重新生成时写回 C#。
- 正耗时入口的第三个快照参数被接收但忽略，保持一次性采集使用自身 `TimeCost` 的旧行为。旧 `GatheringInteraction.cs` 与 UID 保留；回滚点为恢复 10 个资产和生成器旧路径、移除执行器映射和新脚本。

## FarmingInteraction 并行迁移边界

- `farming_interaction.gd` 保持唯一序列化字段 `TimeCost=20`，继续按“pass_time → 未占用时 open_farming_panel”顺序描述农场交互；已占用地形仍结算时间但不打开面板。
- `TerrainInteractionExecutor` 只新增 `open_farming_panel` 到既有 `OpenFarmingPanelOp` 的映射；GameplayPort 的 `FarmingPanelRequested` 信号、TerrainInstance 与农场 UI 规则均不搬入 Resource。
- 正耗时入口的第三个快照参数被接收但忽略，保持旧 FarmingInteraction 使用自身 `TimeCost` 的行为。
- 当前仓库没有场景或 Resource 引用 `FarmingInteraction.cs`，因此本批只完成并行实现和真实执行器边界验证，不虚构生产资产。旧 C# 文件与 UID 保留；回滚点为删除新脚本、测试段及执行器映射。

## TalentCard 生产迁移边界

- `talent_card.gd` 只负责展示 TalentData、播放原悬浮动画并转发点击；天赋池、随机抽取、效果应用、暂停恢复与全局事件仍由 C# TalentManager、Player、TimeSystem 和 GlobalEventBus 负责。
- 场景继续使用 `_titleLabel`、`_descLabel`、`_clickArea`、`_texture` 四个序列化键，保持原节点结构、底部中心缩放轴心、1.05 倍悬浮动画与 `OnCardClicked` 信号名。
- C# TalentManager 把实例类型降为 `Control`，通过 `Initialize` 与 `OnCardClicked` 稳定协议传递同一个 C# TalentData Resource；TalentData、TalentEffect 与效果数组不在本批迁移。
- 旧 `TalentCard.cs` 与 UID 保留。回滚点为恢复 `talent_card.tscn` 的旧脚本引用，以及 TalentManager 的强类型实例化、直接 Initialize 和 C# 事件订阅。

## TalentManager 生产迁移边界

- `talent_manager.gd` 保持 AllTalentsPool、CardScenePrefab、CardsContainer 三个序列化字段、每轮 Fisher-Yates 洗牌、最多三张卡、已选移除和空池短路行为。
- Manager 继续订阅 C# TimeSystem 的 TalentSelectionTriggered，暂停 SceneTree 后展示卡片；点击后向 GlobalEventBus 广播同一个 C# TalentData Resource，再隐藏并恢复运行。
- TalentData、TalentEffect、Player 的效果应用和两个 Autoload 均保持原实现；GDScript Manager 只以 `Array[Resource]` 承接旧 C# TalentData，不解释或复制效果数组。
- 旧 `TalentManager.cs` 与 UID 保留。回滚点为恢复 `talent_screen.tscn` 的旧脚本和 `Array[Object]` 序列化声明；新卡片视图仍可由旧 Manager 通过稳定协议使用。

## TalentData 与 TalentEffect 兼容边界

- `talent_data.gd` 保持 TalentName、Description、TalentTexture、Effects 四个字段；Effects 以 `Array[Resource]` 同时承接旧 C# 与新 GDScript 效果，顺序和 Resource 身份不变。
- `talent_effect.gd` 保留 Apply(Node) 协议。当前 4.7.1 编辑器对路径继承的抽象实现不能稳定实例化具体脚本，因此基类用明确 `push_error` 模拟抽象故障；两个具体效果都提供完整 Apply，不以空函数替代功能。
- 属性效果保持 TargetAttribute 0..14、BonusValue 和直属 `AttributeComponent` 查找；标签效果保持 TagToGrant、空标签短路和 Player.TagComponent 的 AddTag 调用。
- C# Player 的事件参数降为 Resource，从 Effects 数组过滤 Resource 并动态调用 Apply；旧 C# TalentData / TalentEffect 与新 GDScript 实现均可进入同一生产事件链。
- 当前没有生产 `.tres` 或场景引用三类天赋数据脚本，因此新 Resource 先作为并行实现；旧四个 C# 文件与 UID 保留。回滚点为恢复 Player 的 TalentData 强类型回调并删除新脚本/测试。

## MonsterSkillPreview 与 MonsterSkillComponent 生产迁移边界

- `monster_skill_preview.gd` 只保存旧 C# 预览值对象的展示快照；`monster_skill_component.gd` 只负责读取 `SkillSet.Skills`、筛选有效技能、选择随机技能和生成预览，不迁移 `CombatSkillData`、效果执行或战斗结算。
- `Monster.cs` 的 `SkillComponent` 使用 `Node` + `Initialize` / `GetCombatSkills` / `GetRandomCombatSkill` 协议；返回值在 C# 端重新过滤为 `CombatSkillData`，从而保持 BattleManager 与其他调用方的原签名。
- 旧 `MonsterSkillPreview.cs` 与 `MonsterSkillComponent.cs` 保留为兼容垫片；`monster.tscn` 仅切换技能组件脚本，技能集合和技能条目资产仍沿已经迁移的 GDScript Resource 路径加载。

## CurrentMapBackgroundResolver 并行实现边界

- `current_map_background_resolver.gd` 只实现背景节点查找与复制：优先读取 `MapInstantiator.current_scene`，再按子节点回退；复制结果固定命名为 `MapBackground`、`z_index=-1`、`z_as_relative=false`。
- 并行验证阶段的 `WorldCombatScenePresenter` 曾继续静态使用 `CurrentMapBackgroundResolver.cs`；生产切换现已按下方独立边界改为可验证的 GDScript 实例工厂，并在 C# 侧以 `RefCounted`/稳定方法协议调用，没有恢复跨语言强类型构造。
- PassageGuard 与 reusable_gathering 只验证新脚本的背景契约，不把战斗过场、视图隐藏、场景实例化复制进 Resource/Resolver。
- 生产切换回滚点为恢复 Presenter 原调用并保留并行脚本；C# 类型表或 Main helper 未刷新时不得扩大到战斗链。

## Crafting 数据 Resource 并行迁移边界

- 新增 `crafting_ingredient.gd`、`crafting_recipe.gd` 与 `recipe_book_data.gd`，保留 `RequiredItem`、`Amount`、`RecipeName`、`Inputs`、`OutputItem`、`OutputAmount` 和 `Recipes` 的原 PascalCase 序列化字段与默认值。
- `RequiredItem`、`OutputItem` 以及 `Inputs`/`Recipes` 使用通用 `Resource` 协议，允许新 GDScript 数据与旧 C# ItemData/CraftingRecipe 在同一消费边界共存；不改变 CraftingService 的库存扣除、数量校验或信号行为。
- 本批不切换 `player.tscn`、两个现有配方 `.tres` 或 `CraftingComponent.cs`；生产配方继续由 C# 类型加载，新脚本仅作为等价并行实现和后续兼容桥输入。
- 回滚点为移除三个新 GDScript Resource 及其聚焦断言；旧 C# 文件、UID、场景和配方资产无需回滚。

## CraftingService 并行迁移边界

- 新增 `core/crafting/crafting_service.gd`，保留 `CanCraft`、`MaxCraftableQuantity`、`TryBuildRequirements`、`HasRequiredMaterials` 与消耗后空间预检的原规则；`TryCraftWithReason` 返回与 C# `CraftingFailureReason` 相同的整数码，`TryCraft` 通过 `LastFailureReason` 提供无 `out` 的 GDScript 入口。
- 虚拟库存只复制槽位中的物品引用和数量，仍按“从后往前扣材料、先填同物品堆叠、再填空槽位”计算，不触碰真实库存直到所有预检通过；实际扣除/加入继续委托 `TryRemoveItems` 与 `AddItem`。
- 服务通过 `CanStore`、`ItemCnt`、`Slots` 等稳定 Node 方法承接并行 GDScript Inventory；C# CraftingComponent、CraftingService、CraftingUI 与生产配方仍保留，尚未切换运行时所有权。
- 回滚点为移除新服务和聚焦断言；不修改任何场景、配方资产或 C# 文件。

## CraftingComponent 并行迁移边界

- 新增 `entities/components/crafting_component.gd`，保留 `RecipeBook`、`Inventory`、`Recipes`、`CanCraft`、`MaxCraftableQuantity`、`TryCraft`、`CraftingCompleted` 与 `CraftingFailed` 的 PascalCase 运行时协议；组件只编排服务，不复制库存规则。
- `RecipeBook` 与 `Recipes` 使用通用 `Resource`/`Array` 读取，同时承接旧 C# RecipeBookData/CraftingRecipe 和新 GDScript Resource；`CraftingFailureReason` 保持 0..4，`TryCraftWithReason` + `LastFailureReason` 替代 GDScript 无法原样表达的 C# `out` 参数。
- 本批不切换 `player.tscn`、`GameplayPort.cs` 或 `CraftingUI.cs`，因为它们仍持有 C# 强类型 CraftingComponent 信号/属性；新组件通过独立 Node 夹具验证，避免生产场景出现半切换边界。
- 回滚点为移除并行组件、UID 和新增契约测试；旧 C# 组件、场景、配方资产和 UI 无需恢复。

## CraftingUI 生产迁移边界

- `core/ui/crafting/crafting_ui.gd` 保留 `GameplayPortPath`、RecipeGrid、材料列表、数量 SpinBox、状态文本和 Close/Open 方法；界面只通过动态信号与组件方法协议工作，不复制 CraftingService 规则。
- UI 同时接受旧 C# CraftingComponent 和并行 GDScript CraftingComponent：新组件使用 `TryCraftWithReason`，旧组件使用 `TryCraft` 后按材料/空间协议推断原因；配方、物品图标和描述均通过 Resource 字段读取。
- `scenes/crafting/crafting_ui.tscn` 切换为 GDScript 脚本，但 `player.tscn`、GameplayPort.cs、旧 CraftingComponent.cs 和生产配方资产继续保留；因此 UI 已生产切换，合成组件仍是 C# 生产所有者。
- 回滚点为恢复 `crafting_ui.tscn` 的 C# 脚本引用并删除新 UI/契约测试；不需要改动玩家节点结构或信号名称。

## CraftingComponent 生产切换边界

- `player.tscn` 的 `CraftingComponent` 节点切换为 `entities/components/crafting_component.gd`；节点名、`RecipeBook` 序列化字段、配方顺序和同级库存路径保持不变。
- `GameplayPort.cs` 同时保留旧 `CraftingToggleRequested`/`CraftingOpenRequested` 强类型信号，并新增 Node 参数的 `CraftingNodeToggleRequested`/`CraftingNodeOpenRequested`；旧 C# 组件仍走原信号，新 GDScript 组件走动态信号。
- `crafting_ui.gd` 同时连接和解除两组信号，统一委托到相同的 Open/Toggle 处理函数；不复制合成规则，也不改变 HUD 输入动作。
- 旧 `CraftingComponent.cs`、`CraftingService.cs` 和 UID 继续保留。回滚只需恢复 `player.tscn` 的组件脚本，并可移除两条 Node 信号与对应 UI 连接。

## Crafting 配方 Resource 生产切换边界

- 新增 `torch_recipe_gd.tres` 与 `stone_axe_recipe_gd.tres`，完整保留两张配方的名称、两项材料、材料数量、输出物品和默认产出数量 1。
- 玩家内嵌配方书改用 `recipe_book_data.gd`，生产配方改用 `crafting_recipe.gd`/`crafting_ingredient.gd`；材料与输出继续引用现有 C# ItemData 资源，物品链不在本批切换。
- 原 `torch_recipe.tres`、`stone_axe_recipe.tres` 和全部 C# 配方脚本继续作为兼容输入保留，聚焦测试继续验证其可加载性。
- 回滚只需恢复玩家场景的配方书/配方引用；不会改变库存、物品资产、配方数值或存档格式。

## ShopService 并行迁移边界

- 新增 `core/shop/shop_service.gd`，只迁移商店纯规则：可购买判断、卖价回退、总价溢出检查、容量/余额校验、原子买卖和 `ShopFailureReason` 0..6。
- GDScript 服务通过 `Gold`、`TrySpend`、`Add`、`CanAddItem`、`AddItem`、`TryRemoveItem`、`ItemCnt` 稳定协议访问钱包与库存，允许旧 C# PlayerWallet/InventoryComponent 和并行 GDScript 节点共存；不复制 ShopTradeBridge 的目录筛选或 UI 信号。
- `TryBuyWithReason`/`TrySellWithReason` 将 C# `out` 原因转换为整数返回和 `LastFailureReason`；显式目录价格使用 `CanBuyWithPrice`/`TryBuyWithPrice` 与 `CanSellWithPrice`。
- 本批不切换 `ShopTradeBridge.cs`、钱包 Autoload、商店 UI 或生产交易场景；回滚点为移除并行服务、UID 和聚焦测试，旧 C# 规则不受影响。

## ShopTradeBridge 并行迁移边界

- 新增 `core/shop/shop_trade_bridge.gd`，保持 `Catalog`、`IsPurchasable`、`GetBuyPrice`、`GetSellPrice`、`GetGold`、`GetItemCount`、`BuildStockList`、`CanBuy`、`CanSell`、`TryBuyWithReason` 与 `TrySellWithReason` 的 PascalCase 边界。
- 目录解析规则保持旧实现：显式 `Goods` 按原顺序保留，`AlsoIncludeEveryPricedItem` 开启时才追加自身买价为正的物品，自动项按 `CardId` 升序并按 Resource 身份去重；显式无买价商品使用 `DefaultBuyPrice`，卖价仍按买价折半回退。
- Bridge 只通过 `Node`/`Resource` 的稳定属性和方法访问旧 C# PlayerWallet/InventoryComponent 或未来 GDScript 实现，并把带目录价格的买卖委托到 `shop_service.gd`；旧 C# `ShopTradeBridge.cs` 继续拥有 `Shop.tscn` 生产节点。
- 本批不切换 `Shop.tscn`、`shop_control.gd`、PlayerWallet、GlobalWarehouse 或 ItemData/ItemStack 生产类型。回滚点为移除新 Bridge、UID 和契约测试，不需要恢复任何场景资产。

## ShopTradeBridge 生产切换边界

- `scenes/Shop/Shop.tscn` 的 `ShopTradeBridge` 节点仅替换脚本 ext_resource 与 UID，节点名、Catalog 资源、Canvas/UI 结构和所有序列化值保持不变。
- `scripts/shop/shop_control.gd` 继续通过既有 PascalCase 方法和 `Array[ItemData].assign` 消费 Bridge；新 Bridge 返回的商品 Resource 身份与 C# ItemData 保持不变，PlayerWallet/GlobalWarehouse 仍是旧 C# Autoload。
- 旧 `core/shop/ShopTradeBridge.cs` 不删除，作为兼容垫片保留；若新脚本无法加载，回滚只需恢复场景 ext_resource 到旧 C# UID，不涉及目录或 UI 资产。
- 本批不迁移 `ShopService.cs`、PlayerWallet、GlobalWarehouse、ItemData/ItemStack、商店 UI 或交易数值；生产切换只验证桥接节点和已有 UI 调用链。

## PlayerWallet 并行迁移边界

- 新增 `core/autoloads/player_wallet.gd`，保持 `SettingsSection`、`SettingsKey`、`DefaultGold=1200`、`Gold`、`GoldChanged`、`TrySpend` 和 `Add` 的公开协议与 C# 实现一致。
- GDScript 钱包只通过 `SettingsManager` 的 `get_setting`、`set_setting`、`erase_setting` 动态方法读写存档，并保留开发期 `PersistAcrossRuns=false`、非负校验、int 上限钳制和失败不发信号规则。
- `PlayerProgression.cs` 仍把 `/root/PlayerWallet` 强转为 `IPlayerWallet`，因此本批不改 `project.godot` 的 Autoload；旧 `PlayerWallet.cs` 继续拥有生产节点，GDScript 只作为并行实现。
- 回滚点为移除新脚本、UID 和契约测试，不改变存档键、Autoload 注册或 C# 调用方。

## PlayerProgression 并行迁移边界

- 新增 `core/progression/player_progression.gd`，保留仓库与带入栏的等级、容量、费用表、最大等级、具名升级方法和 `UpgradeChanged` 信号。
- GDScript 通过 `Gold`/`TrySpend`、`SetCapacity` 及 SettingsManager 动态协议访问旧 C# 或未来 GDScript 钱包、仓库和设置节点；升级数值与存档键不变。
- `project.godot` 仍注册 `PlayerProgression.cs`，因为旧 C# `IPlayerWallet` 强类型边界尚未降型；新脚本只作为经过契约验证的并行实现，不替换生产 Autoload。
- 回滚点为移除新脚本、UID 和测试段，不触碰旧 Autoload、存档键或仓库场景。

## PlayerProgression 生产切换边界

- 仅把 `project.godot` 的 `PlayerProgression` Autoload 从 `PlayerProgression.cs` 切换到 `core/progression/player_progression.gd`；节点名称、存档键、公开方法和信号保持不变。
- 新脚本通过 `TrySpend` 与 `SetCapacity` 动态协议继续消费旧 C# `PlayerWallet` 和 `GlobalWarehouse`，因此不要求本批切换其他 Autoload；旧 C# 文件保留为兼容垫片。
- 回滚点是将 Autoload 路径恢复到 `PlayerProgression.cs`，不改升级数据、仓库场景或 UI 调用方。

## PlayerWallet 生产切换边界

- 仅把 `project.godot` 的 `PlayerWallet` Autoload 从 `PlayerWallet.cs` 切换到 `core/autoloads/player_wallet.gd`；`Gold`、`GoldChanged`、`TrySpend`、`Add`、默认值 1200 和存档键保持不变。
- 生产消费者均通过动态 Node/信号协议读取钱包；旧 C# `PlayerWallet.cs`、`IPlayerWallet` 和商店 C# 服务继续保留为兼容输入，不要求本批重新编译 C# 程序集。
- 回滚点是将 Autoload 路径恢复到 `PlayerWallet.cs`；测试中的临时扣款在同一运行内退款，不污染存档。

## TimeSystem 并行迁移边界

- 新增 `core/autoloads/time_system.gd`，保持 `PhaseLength=100`、`MapMoveTimeCost=10`、`PassTime`、`PassMapMoveTime`、`SetMapMoveTimeCost` 以及四个信号的顺序和参数。
- 并行脚本通过动态属性 `_get` 暴露 `TotalTimePassed`、`CurrentDay`、`PhaseProgress`，可被现有 GDScript UI/地图协议读取；C# `TimeSystem.Instance` 消费者仍要求旧 Autoload，因此本批不切生产路径。
- 回滚点为移除新脚本、UID 和契约测试，不修改 `project.godot`、TimeSystem.cs 或时间存档/场景结构。

## GameplayPort 并行迁移边界

- 新增 `core/application/gameplay_port.gd`，保留六个导出路径、六个请求信号和 PascalCase 请求方法；`Player`、库存、卡组、生命、合成与仓库均通过 `Node`/`Variant` 动态协议解析。
- 生产 `GameplayPort.cs`、`Main.tscn` 和所有 C# 强类型消费者暂不切换；新门面只作为后续 GlobalWarehouse/Inventory 生产切换前的可逆边界，保持现有节点结构、路径值、信号参数和调用顺序。
- 测试夹具可在未加入 SceneTree 时直接调用 `_ready`；绝对 `/root/EncounterManager` 仅在 `is_inside_tree()` 时解析，避免编辑器测试夹具产生无效绝对路径错误，生产场景内仍保留全局管理器查找语义。
- 回滚点为移除 `gameplay_port.gd`、UID、测试包装器和契约测试；不修改 `GameplayPort.cs`、`Main.tscn`、仓库资产或存档格式。

## GlobalWarehouse 生产切换边界

- `global_warehouse.tscn` 的节点结构、Autoload 名称、容量与仓库拖拽来源标识保持不变，仅将脚本替换为 `warehouse_inventory_component.gd`。
- `GameplayPort.cs` 同时保留强类型 `WarehouseRequested(InventoryComponent, InventoryComponent)` 与新增动态 `WarehouseNodeRequested(Node, Node)`；GDScript 仓库只走动态信号，旧 C# 仓库继续走旧信号。
- `warehouse_ui.gd` 同时监听两条信号，库存操作继续通过 `Capacity`、`GetStackAt`、`InventoryChanged` 等稳定动态协议完成；旧 C# 组件和 UI 保留为兼容输入。
- 回滚只需恢复场景 ext_resource，必要时移除动态信号连接；不改容量、槽位、存档字段或节点路径。

## Inventory 动态兼容边界

- `GameplayPort.cs` 同时缓存通用 `PlayerInventoryNode` 与可选的旧 `InventoryComponent`；旧 C# 玩家库存继续发 `InventoryToggleRequested(InventoryComponent)`，未来 GDScript 玩家库存改发 `InventoryNodeToggleRequested(Node)`，两条信号只负责转发同一个库存节点。
- `inventory_ui.gd` 同时连接和解除旧强类型信号与新增 Node 信号，并将两者收敛到原 `_handle_inventory_toggle_request`；槽位生成、卡组、装备、快捷移动和属性摘要逻辑不因兼容层而复制或改写。
- 仓库请求仅在玩家库存和全局仓库都仍是旧 C# `InventoryComponent` 时发 `WarehouseRequested`；任一端为 GDScript 时统一发 `WarehouseNodeRequested(PlayerInventoryNode, GlobalWarehouseNode)`，允许两端按不同批次迁移。
- 本批不切换 `player.tscn` 的 InventoryComponent，也不迁移 ItemStack、Player、BattleDeck、Equipment 或库存规则。回滚点为移除 `InventoryNodeToggleRequested`、通用库存缓存和 InventoryUI 的动态连接，生产场景无需恢复资产引用。

## Player 库存 Node 访问边界

- `Player.cs` 的玩家库存字段降为 `Node`，仍按固定路径 `Components/InventoryComponent` 解析；玩家生命、饱食、属性、装备、卡组和根脚本均不迁移。
- `TryAddItemToInventory(ItemStack)` 继续接受旧 C# ItemStack，保持世界掉落与 GameplayPort 的公开签名；内部只通过 `AddItem(Item, Amount)` 动态协议读取未放入数量，因此当前 C# 库存和未来 GDScript 库存行为一致。
- 本批不切换 `player.tscn` 的库存脚本，也不修改 ItemStack、Equipment、BattleDeck、拖拽或库存规则。回滚点为恢复 `InventoryComponent` 字段、强类型 `GetNode` 和直接 `AddItem` 调用。

## Equipment 消费者 Node 边界

- `Player.Equipment` 降为 `Node`，生产路径仍为 `Components/EquipmentComponent`；装备组件继续独占装备槽、套装、属性和标签结算。
- 地形执行、一次性/可重复采集及长按耗时只调用 `GetNightEncounterChanceMultiplier`、`GetGatheringYieldBonus`、`GetGatheringTimeReduction` 三个稳定方法，缺失节点或方法时分别回退到中性倍率 1、额外产量 0 和时间减免 0。
- 旧 C# InventoryUI 仅作为兼容垫片保留，通过可选转换继续绑定旧 C# EquipmentComponent；生产 GDScript InventoryUI 已按 Node 协议工作。
- 本批不切换 `player.tscn` 的装备脚本，不改 EquipmentSlot 枚举、ItemStack、EquipmentData、套装数值或装备信号。回滚点为恢复 Player 强类型属性及五个 C# 消费者的直接方法调用。

## EquipmentComponent 生产切换边界

- `player.tscn` 的 `EquipmentComponent` 节点仅替换为 `equipment_component.gd`，节点名、两个导出字段、EquipmentSlot 0..15、`EquipmentChanged` 信号和所有装备/卸下方法保持不变。
- GDScript 组件通过兼容读取器同时接受旧 C# 与 GDScript ItemStack/EquipmentData/ToolData；新增 `GetEquippedStack(slot)` 保留旧 C# 为无 `out` 调用提供的公开入口，`TryGetEquippedStack(slot)` 继续兼容既有 GDScript 调用。
- 属性与标签效果仍写入同级 AttributeComponent/TagComponent，套装阶级和采集查询继续由装备组件拥有。旧 `EquipmentComponent.cs` 与 UID 保留；回滚点仅为恢复玩家场景脚本引用。
- 强制生产场景加载时发现 Main 对 Inventory/Crafting/Warehouse 子场景仍保存旧 C# 脚本覆盖；该覆盖与已完成 UI 迁移矛盾，因此只移除三处覆盖及对应外部资源，保留 Main 其余改动。

## 玩家 Inventory / BattleDeck 物品链生产切换边界

- 玩家普通库存和出战卡组作为同一双向移动链同时切换到 `inventory_component.gd` / `battle_deck_component.gd`，避免留下“GDScript 卡组 + C# 库存”无法互传不同 ItemStack 类型的半切换状态。
- `Player.BattleDeck` 与 `GameplayPort.PlayerBattleDeck` 降为 Node；`GameplayPort.GetPlayerSkillCards()` 从任一语言卡组的 `GetSkillCards` 数组过滤 C# `SkillCardData`，继续向战斗信号和通道驻守流程提供原强类型数组、顺序和 Resource 身份。
- `Player.TryAddItemToInventory(ItemStack)` 保留旧 C# ItemStack 入口并把 Item/Amount 委托给 GDScript 库存；InventoryUI、WarehouseUI、CraftingComponent、EquipmentComponent 与 DebugLoadout 已使用 Node/动态协议，双向库存移动继续由共享 GDScript 基类负责。
- 旧 `InventoryComponent.cs`、`BattleDeckComponent.cs`、UID 和对照测试不删除。回滚点为同时恢复玩家场景两个脚本引用及 Player/GameplayPort/WorldInteractionCoordinator 的卡组强类型访问，不能只回退其中一端。

## GameplayPort 生产切换边界

- `Main.tscn` 的 `Gameplay/GameplayPort` 仅把脚本切换到 `core/application/gameplay_port.gd`；六个导出路径、玩家与组件节点身份、PascalCase 方法和请求信号名称保持不变，旧 `GameplayPort.cs` 与 UID 继续作为兼容垫片保留。
- GDScript 端口同时公开旧强类型信号名与新增 Node 信号名，并按组件脚本语言只发其中一组，避免 Inventory/Crafting/Warehouse UI 双订阅后收到重复请求；农场请求继续传递原地形引用，库存加入继续委托 Player。
- 生产 `EncounterManager` 位于 Main 的 `Gameplay` 子树而非 `/root`。Godot 无法把 GDScript 的 `Array[MonsterData]` 安全隐式封送给 C# 泛型数组，因此端口优先调用同级 `WorldInteractionCoordinator.ScaleEncounterMonsters`；协调器以非泛型 Array 接收、逐项过滤为 `Array<MonsterData>`，再委托原 EncounterManager，避免复制倍率逻辑。卡组同样显式过滤，合法 Resource 的顺序和身份不变。
- `WorldInteractionCoordinator` 与 `TerrainInteractionExecutor` 只以 `Node` 持有 GameplayPort，并通过稳定 PascalCase 方法、属性和 `EncounterRequested` 信号工作；C# 消费者收到 GDScript 数组后显式逐项过滤，不依赖隐式泛型转换。
- 本批不迁移战斗实现、ItemData、SkillCardData、MonsterData、TimeSystem 或任何 Autoload。回滚点为同时恢复 Main 的 `GameplayPort.cs` 引用，以及两个 C# 消费者的强类型字段、事件订阅和直接调用。

## LootTable 生产切换边界

- 65 个怪物、地形和地图生产资产统一把内嵌掉落表脚本切换为 `resources/loot/loot_table.gd`，并同步 `create_terrain_profiles.gd`，防止重新生成时写回旧 C# 路径；`Drops`、概率、数量范围、顺序和物品 Resource 身份不变。
- `MonsterData.LootTable` 放宽为通用 `Resource`，只负责让 C# MonsterData 承接 GDScript 掉落表；EncounterMonsterScaler 继续原样复制同一资源，掉落随机规则仍只存在于 LootTable。
- 棋盘掉落、WorldInteractionCoordinator 与 Player 的拾取入口仍接收 C# `ItemStack`，因此生产 GDScript LootTable 暂时创建保留的 `ItemStack.cs`，并只接受当前 C# `ItemData` 派生资产。该兼容输出必须保留到棋盘堆叠边界单独迁移。
- 旧 `LootTable.cs`、UID、旧 C# GatheringInteraction/ReusableGatheringInteraction 和对照测试继续保留。回滚点为恢复 65 个资产及生成器的脚本/UID，并把 `MonsterData.LootTable` 恢复为强类型；本批不修复既有 MonsterData 到 LootComponent 未绑定风险，也不迁移 ItemData、棋盘或战斗。

## 棋盘掉落 ItemStack 通用协议边界

- `LootBoardCardState`、`BoardCardView`、`BoardController`、`WorldInteractionCoordinator` 与 `Player.TryAddItemToInventory` 统一以 `RefCounted` 保存或传递堆叠，通过 `Item`、`Amount`、`IsEmpty`、`SetItem` 和 `Clear` 读取协议，同时接受旧 C# 与生产 GDScript ItemStack。
- GDScript 掉落数组进入 C# 时统一使用非泛型 `Godot.Collections.Array`。`SpawnLootOp` 保留 `Array<ItemStack>` 构造函数承接旧 C# GatheringInteraction，并显式复制到非泛型数组；另一个非泛型构造函数承接 GDScript 操作描述，避免泛型数组隐式封送。
- `ItemStackProtocol` 先以稳定方法门控对象，再读取三个属性；不得使用 `GetPropertyList()` 判断 C# 计算属性，因为未导出的公共属性不保证出现在属性列表中。无效对象在地形执行器和棋盘批量入口被过滤，不产生空掉落卡。
- `resources/loot/loot_table.gd` 改为创建 `resources/item/item_stack.gd`，概率、数量、额外产量、非正过滤和 Item Resource 身份不变。旧 `ItemStack.cs`、`LootTable.cs`、调试装载工厂与 C# 交互继续保留为兼容输入。
- 回滚点为恢复棋盘/Player 的 ItemStack 强类型签名、SpawnLootOp 泛型字段及 LootTable 的 C# ItemStack 输出；必须整体回滚，不能只恢复输出或单个消费者。本批不迁移 ItemData 资产、ItemsControl、技能卡、战斗、StartingStats、Autoload 或 AttributeModifierData。

## ResourceCardData 生产切换边界

- `resources/item/card/resource_card_data.gd` 等价继承生产 `resources/item/item_data.gd`；旧 `ResourceCardData.cs` 本身没有新增字段或行为，因此迁移只改变资源脚本继承来源，不复制库存、掉落、配方或 UI 逻辑。
- `branch.tres`、`charcoal.tres`、`stone.tres`、`torch.tres` 与 `axe.tres` 五个资源卡资产切换到 GDScript，同时移除旧 `script_class="ResourceCardData"` 与 `metadata/_custom_type_script` 标记；资产 UID、`CardId`、显示字段、图标和资源引用保持不变。
- 资源卡继续通过通用 ItemData Resource 协议被配方、掉落、库存、商店和 UI 消费；继承默认值保持 `MaxStackSize = 99`、`BuyPrice = 0`、`SellPrice = 0` 与空 `ItemTags`。
- 旧 `ResourceCardData.cs` 与 UID 保留为兼容输入和回滚垫片。回滚只需恢复五个资产的旧脚本与类标头，不需要修改调用方、数值或序列化字段。
- 本批不迁移 `SkillCardData`、`CombatSkillData`、战斗执行、StartingStats、Autoload 或 AttributeModifierData；技能卡必须另行设计动态 Resource 与保留 C# 战斗执行之间的兼容边界。

## SkillCardData 动态兼容边界

- 新增并行 `resources/item/card/skill_card_data.gd`，继承生产 `item_data.gd`，保留 `Skill`、`cost`、`CardTags`、实际堆叠上限 1、显示字段回退、标签换行、元素读取和 `ApplyEffect`；`Skill` 继续引用保留的 C# `CombatSkillData`，显示回退读取其导出字段 `CardName` / `Description` / `CardIcon`，效果结算仍由其 `Execute(SkillExecutionContext)` 完成。
- `base_card_data.gd` 与 `item_data.gd` 只增加可覆写的显示值/实际堆叠读取钩子，使派生技能卡能够等价实现 C# 虚属性；普通 ItemData 与 ResourceCardData 的返回值不变。
- 玩家卡组到战斗场景的数据流统一使用 `Resource` / `Array[Resource]`：生产 GDScript GameplayPort、保留 C# GameplayPort、WorldInteractionCoordinator、WorldCombatScenePresenter、BattleManager、DeckManager 与 SkillCard 节点不再要求具体 `SkillCardData` 运行时类型。
- 动态过滤只接受具备 `ApplyEffect` 稳定方法的 Resource；展示和结算继续读取 `Skill`、`DisplayName`、`DisplayDescription`、`DisplayTag`、`cost` 与 `ApplyEffect`，不复制 `CombatSkillData` 的目标、效果或伤害规则。
- 本批不替换 `resources/skill_cards/`、怪物/战斗资源、`battle.tscn` 内嵌技能卡或卡表生成脚本；旧 `SkillCardData.cs`、CombatSkillData、SkillExecutionContext、BattleDeckComponent.cs 与 InventoryUI.cs 均保留。回滚点为恢复上述入口的 SkillCardData 强类型并移除并行脚本及聚焦断言。

## SkillCardData 生产资产切换边界

- 将 `resources/skill_cards/` 下 69 个技能卡 Resource 统一切换到 `resources/item/card/skill_card_data.gd`，移除旧 `script_class="SkillCardData"` 与指向 C# UID 的 `_custom_type_script`；各资产 UID、CardId、CardName、Description、CardIcon、Skill、cost、CardTags 和未显式写出的默认值均保持不变。
- `scenes/battle_scenes/battle.tscn` 的两个内嵌技能卡同步使用 GDScript，保留其 CombatSkillData、DamageEffect、数值、标签和子资源身份；只替换技能卡包装脚本及对应元数据。
- 怪物和 CombatSkill 资源中仅声明但未被引用的旧 SkillCardData Script ext_resource 一并移除，避免生产旧路径扫描误报；不得删除任何实际使用的 CombatSkillData、CardEffect、DamageEffect 或 SkillCard `.tres` 引用。
- `card_table/export_current_cards.py` 的生成模板改写新 GDScript 路径与 UID，并停止生成旧 C# `script_class` / `_custom_type_script`，防止后续同步重新引入旧依赖。
- 旧 `SkillCardData.cs` 与 UID、C# BattleDeckComponent/InventoryUI 兼容输入、CombatSkillData 和 SkillExecutionContext 继续保留。回滚点为同时恢复 69 个资产、battle 内嵌脚本、冗余 ext_resource 与生成模板，不能只回退单侧。

## EquipmentData / ToolData 生产切换边界

- `items/tool/Ax.tres` 与 `Pickaxe.tres` 仅把包装脚本切换到 `tool_data.gd`，保持资产 UID、价格、标签、槽位、采集标签、时间减免、CardId、名称、图标和描述不变；旧 `ToolData.cs` 与 `EquipmentData.cs` 继续作为兼容输入保留。
- Debug 动态装备工厂同时改为创建 `equipment_data.gd` / `tool_data.gd` 和生产 `item_stack.gd`，因为玩家 InventoryComponent、EquipmentComponent 与 ItemStack 链已经生产切换；槽位整数、CardId 格式、属性范围、RollRandomStats 时序和工具判定条件不变。
- 生产装备组件继续经 `equipment_data_compat.gd` 读取 C# / GDScript Resource；旧 C# ItemStack、EquipmentComponent、Debug 工厂与测试对照不删除。回滚点为同时恢复两张 ToolData 资产和 Debug 工厂的三种 C# 脚本预加载，不能留下半切换输出。
- 本批不把其他普通工具资产改造成装备，不迁移 AttributeModifierData、套装数据、属性组件或装备规则；没有 `ValidSlots` / 采集字段的普通物品继续保持 ItemData。

## CurrentMapBackgroundResolver 生产切换边界

- `WorldCombatScenePresenter` 通过固定脚本路径加载 `current_map_background_resolver.gd`，以 Script 的 `new` 动态工厂创建 `RefCounted`，再调用稳定的 `DuplicateCurrentBackground(mapSystem)` 方法；背景查找与复制规则只由 GDScript Resolver 持有。
- C# Presenter 继续拥有战斗场景实例化、过场、世界视图显隐和 battle_ended 生命周期；本批不修改怪物/卡组数组、战斗效果、场景节点结构或背景视觉值。
- 旧 `CurrentMapBackgroundResolver.cs` 保留为兼容垫片。脚本加载、实例创建或方法协议无效时只记录明确错误并跳过背景，不阻断原战斗流程；回滚点为恢复 Presenter 的静态 C# 调用。

## TimeSystem 生产 Autoload 切换边界

- `project.godot` 只把 `TimeSystem` Autoload 从旧 C# UID 切换到 `res://core/autoloads/time_system.gd`（资源 UID `uid://dd7cqlb6a72pe`）；`PhaseLength=100`、`MapMoveTimeCost=10`、四个信号、方法名、参数和触发顺序保持不变。
- 生产 C# 消费者统一从 `/root/TimeSystem` 获取 `Node`，通过 `TotalTimePassed`、`CurrentDay`、`IsNight`、`PhaseProgress`、`PassTime` 和信号协议工作。地形操作通过 `WorldInteractionContext` / `TerrainInteractionBuildContext` 注入同一节点，不再读取 `TimeSystem.Instance`。
- 旧 `TimeSystem.cs`、UID、TimePanelUI/TalentManager/ReusableGathering C# 兼容文件继续保留；兼容文件也改用 Node 协议，避免将来被旧场景加载时依赖失效静态单例。EncounterManager 允许测试显式注入时间节点，但生产仍解析同一个 Autoload。
- 回滚点为同时恢复 `project.godot` 的旧 UID 以及生产消费者的静态 C# 读取；不能只回退 Autoload 单侧。本批不改变时间存档格式、地图移动顺序、采集冷却、昼夜、七日天赋或战斗实现。

## BoardCardView 生产切换边界

- `scenes/board_card_scene/BoardCardView.tscn` 只把视图脚本切换为 `core/board/board_card_view.gd`；Area2D、Title、Amount、Icon、CollisionShape2D 节点结构、卡牌缩放与动画时长保持不变。
- GDScript 视图保留 `Clicked`、`Pressed`、`Released`、`HoverStarted`、`HoverEnded` 信号，以及 `Bind`、`RefreshView`、`GetCardData`、`GetCardDisplayName`、`GetLootStackOrNull`、`GetTerrainInstanceOrNull`、`PlayScatterFrom`、`PlayFlyTo` 和禁用视觉入口。地形通过 `TerrainInstance/TerrainData` 协议读取，掉落通过 `ItemStack.Item/Amount/IsEmpty` 协议读取，保留旧 C# 与生产 GDScript 对象身份。
- `BoardController`、`WorldInteractionCoordinator` 与 `TerrainInteractionExecutor` 的视图边界降为 `Node2D`，通过稳定方法和 Godot 信号连接；控制器仍拥有卡牌集合、棋盘状态、散射位置和移除时序，未迁移 `BoardCardState`、`RoomTerrainStore` 或战斗流程。
- `board_card_view.gd` 使用 `@tool` 仅为了让编辑器契约测试实例化同一生产脚本；不增加编辑器专用分支。旧 `BoardCardView.cs`、UID、BoardCardState 与其 C# 调用保留为兼容/回滚输入。回滚点是恢复场景旧脚本并将三个消费者的 `Node2D` 协议签名恢复为 C# 类型，不能只回退场景一侧。

## EncounterManager 跨语言编译边界与 PassageGuardMonsterResolver 批次

- `WorldInteractionCoordinator` 与 `TerrainInteractionExecutor` 不再在编译期引用 `EncounterManager` 具体 C# 类型，统一以 `Node` 持有同级管理器节点，并通过 `ScaleEncounterMonsters`、`ResolveGatheringEncounter` 方法协议调用；兼容程序集刷新期间和后续 GDScript 管理器。
- 倍率桥先把动态怪物数组过滤为 `Array<MonsterData>`，再传给管理器并重新过滤返回值；缺少方法或返回值类型不符时回退到过滤后的原数组，不复制倍率规则、不改变地形方差或按日成长。
- 遭遇结算仍优先接受现有 C# `GatheringEncounterResult` `RefCounted` 身份；管理器缺失时返回 `None`，不触发战斗。旧 `EncounterManager.cs`、结果类型与场景节点路径继续保留为兼容输入。
- `PassageGuardMonsterResolver` 的 GDScript 实现继续负责无向边缓存、房间清理、Encounter `Monsters` 读取和 MonsterData 身份；旧 C# Resolver 保留，控制器和测试使用 GDScript 路径。

## BoardCardState 生产切换边界

- 新增 `core/board/board_card_state.gd` 作为 `BoardCardState` 的等价临时状态对象，保留 terrain/loot 类型、TerrainInstance/TerrainData、ItemStack/Item/Amount/IsEmpty 身份与数量显示判断。
- `BoardController` 只通过脚本方法协议创建和消费状态，继续拥有卡牌集合、网格去重、视图实例化和信号生命周期；旧 `BoardCardState.cs`、`LootBoardCardState`、`TerrainBoardCardState` 保留为兼容垫片和回滚输入。
- 状态脚本不声明全局 class，避免与 C# 类型表冲突；若脚本缺失或协议返回无效，BoardController 立即抛出原等价初始化异常，不生成空卡牌。
