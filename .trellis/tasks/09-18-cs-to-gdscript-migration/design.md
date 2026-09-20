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

## EncounterManager 生产切换边界

- `scenes/Main.tscn` 的 `Gameplay/EncounterManager` 只把 ext_resource 换成 `core/application/encounter_manager.gd`；节点名、路径、`unique_id`、`GatheringRules` 三条 SubResource、`BaseGatheringSpawnChance=0.05`、`NightChanceMultiplier=6.0` 与每日成长倍率保持原值。
- 管理器稳定协议为 `ResolveGatheringEncounter(resourceTag, nightEncounterChanceMultiplier) -> RefCounted` 与 `ScaleEncounterMonsters(terrain, monsters) -> Array`；结果对象以 `Triggered` / `MonsterToSpawn` / `SpawnMessage` 字段表达，等价旧 `GatheringEncounterResult`，不改变战斗请求顺序和提示文案。
- 地形方差只通过 `TerrainInstance.GetEncounterVarianceSnapshot() -> Dictionary` 跨越语言边界；GDScript 侧缺失协议或字段类型不符时回退中性倍率 1，不复制也不会读写普通 C# `MonsterStatMultiplier`。地形实例仍由 `RoomTerrainStore` 持有并写入同一份内存状态。
- C# 消费者 `WorldInteractionCoordinator`、`TerrainInteractionExecutor` 继续持有 `Node`，调用后把动态数组过滤为 `Array<MonsterData>` 并按字段重建旧结果类型；旧 `EncounterManager.cs`、`EncounterMonsterScaler.cs`、`GatheringEncounterResult.cs`、`MonsterStatMultiplier.cs` 与 C# `GameplayPort.cs` 保留为兼容垫片。
- 回滚点为恢复 `scenes/Main.tscn` 的旧 C# ext_resource（uid `uid://d0aq30etvrhiu`），无需回退资源、存档、地图或战斗资产。本批不迁移 `RoomTerrainStore`、`MonsterData`、`Monster`、`Player`、组件层与战斗效果，也不处理 StartingStats、物品链、Crafting 与 Autoload 收尾。

## RoomTerrainStore 与 RoomTerrainLayoutGenerator 生产切换边界

- `scenes/Main.tscn` 的 `RuntimeState/RoomTerrainStore` 只把 ext_resource 换成 `core/map/room_terrain_store.gd`（uid `uid://cvc18jht88wtv`）；节点名、节点路径、`unique_id=229807555`、`TerrainStorePath = NodePath("../../RuntimeState/RoomTerrainStore")` 与房间缓存嵌套结构保持原样。
- 仓库稳定协议为 `HasRoom`、`CreateRoomLayout(roomPos, placements) -> bool`、`GetRoomTerrainsOrEmpty(roomPos) -> Dictionary`、`GetOrCreate`、`TryGetTerrain`（GDScript 无 `out` 参数，等价旧 `TryGet`）；布局生成协议为 `Generate(profile) -> Array`，每项含 `TerrainData`、`LocalGridPos`、`BoardPosition`、`Variance`。重复格子沿用旧错误文案并以 `push_error` + `false` 表达，其余格子保持已写入状态。
- `RoomBoardPresenter.cs` 不再编译期引用具体仓库或生成器类型：仓库以 `Node` 持有并按方法协议调用，生成器从固定脚本路径加载 GDScript 后以 `RefCounted` 持有；Godot 字典保持插入顺序，因此地形卡生成顺序与旧 C# `Dictionary.Values` 遍历一致。动态协议对 C# 与 GDScript 两种实现同时成立。
- 地形实例仍由旧 C# `TerrainInstance` 提供，仓库顶部只有一处脚本常量指向它，便于后续整体替换；跨语言倍率通过 `GetEncounterVarianceSnapshot()` 读、`ApplyEncounterVarianceSnapshot(Variant)` 写，字段缺失或类型不符一律回退中性值 1，普通 C# 类 `MonsterStatMultiplier` 不跨越语言边界。
- 唯一有意的行为差异是随机数源：旧实现用 `System.Random`，新实现用 `RandomNumberGenerator`，同一种子不再产生相同序列；权重抽样、总权重为零的退化分支、Fisher-Yates 方向、min/max 反序、数量夹紧与格子中心插值逐条等价，并已在两个脚本的中文注释中记录。
- 回滚点是恢复 `scenes/Main.tscn` 的旧 C# ext_resource（uid `uid://dysm4qdwufagp`），`RoomBoardPresenter` 的动态调用无需回退即可同时支持两种实现。旧 `RoomTerrainStore.cs`、`RoomTerrainLayoutGenerator.cs`、`TerrainSpawnPlacement` 与 C# 对照测试保留为兼容垫片；本批不迁移 `TerrainInstance`、`MonsterData`、`Monster`、`Player`、组件层与战斗效果，也不处理 StartingStats、物品链、Crafting 与 Autoload 收尾。

## VitalComponentBase / HealthComponent / EnergyComponent / SatietyComponent 生产切换边界

- `scenes/player_scenes/player.tscn` 只切换 `EnergyComponent` / `HealthComponent` / `SatietyComponent` 三条 ext_resource 与 `metadata/_custom_type_script`，`scenes/monster_scenes/monster.tscn` 只切换 `Components/HealthComponent` 一条；节点名、节点路径、`unique_id`、`unique_name_in_owner`、组件挂载顺序与序列化 `MaxValue`（玩家 1000、怪物 100）保持原值。
- 数值组件稳定协议为属性 `CurrentValue` / `MaxValue`、方法 `InitializeMax`、`SetMaxValuePreservingCurrent`、`Add`、`Subtract`、`TakeDamage(amount, element_type) -> int`，信号 `ValueChanged(current_value, max_value)`、`Depleted()`、`DamageTaken(amount, element_type)`。信号顺序固定：扣减到 0 时先 `ValueChanged` 后 `Depleted`；`Add` / `Subtract` 返回真实增减量，非正数参数为无操作；上限最低钳制为 1。
- 事件订阅属于边界：C# 消费者不再用 `+=` 绑定组件事件，改为 `Connect("Depleted"/"ValueChanged", 缓存 Callable)` 并在 `_ExitTree` 用 `IsConnected` 守卫；组件节点一律以 `Node` 持有，通过 `Get` / `Call` 读取属性与方法，因此同一套 C# 代码可同时驱动 C# 垫片与 GDScript 生产实现。
- `HealthComponent` 的 `TakeDamage` 仅在真实伤害大于 0 时发出 `DamageTaken`，归零后继续受击返回 0 且不再发信号；`ElementType.None == 0`，`Player.OnSatietyDepleted` 保持 `Call("TakeDamage", 5, 0)` 的旧数值与旧调用时机。
- `AttributeComponent.SynchronizeVitalMaximum` 只按属性类型查找同名子节点（`HealthComponent`、`EnergyComponent`），能量组件缺失时按旧行为静默跳过；`DamageReceiverComponent` 只新增 `ReadVitalCurrentValue(Node)`，`HealthBarUI` 只新增 `ReadInt(propertyName)`，其余伤害公式、护盾、吸血与上限状态实例逻辑不变。
- 回滚点是恢复两个场景的旧 C# ext_resource（玩家 uid `uid://coyiavqkkmsgv`、`uid://d4gp22cg5vjro`、`uid://vhrfbyuub4pr`，怪物 uid `uid://d4gp22cg5vjro`）并回退 8 个 C# 消费者。旧 `VitalComponentBase.cs`、`HealthComponent.cs`、`EnergyComponent.cs`、`SatietyComponent.cs` 与 `tests/CUSGA.Tests/Program.cs` 对照用例继续保留；本批不迁移 `AttributeComponent`、`StatusComponent`、`DamageReceiverComponent`、`TerrainInstance`、`MonsterData`、`Monster`、`Player` 与战斗效果，也不处理 StartingStats、物品链、Crafting、Autoload 收尾与 `AttributeModifierData`。

## TerrainInstance 生产切换边界

- 新增 `resources/interaction/terrain_instance.gd` 作为旧 `resources/interaction/TerrainInstance.cs` 的等价实现，**故意不声明 `class_name`**，避免与 C# 类型表产生同名全局类冲突；字段名与旧 C# 属性逐字一致（`LocalGridPos`、`BoardPosition`、`TerrainData`、`IsOccupied`、`IsHarvested`、`GrowthStage`、`RemainingGatheringCount`、`RefreshReadyTotalTime`、`EncounterVarianceMultiplier`），方法与默认值保持不变（`RemainingGatheringCount = -1`、`RefreshReadyTotalTime = 0`、`GrowthStage = 0`、两个布尔默认 `false`）。
- 稳定协议为“字段名一致的 `Get`/`Set` 通道”＋`GetEncounterVarianceSnapshot()` / `ApplyEncounterVarianceSnapshot(Variant)` 字典协议；倍率字典固定六字段 `MaxHealth`、`PhysAtk`、`PhysDef`、`MagPower`、`MagResist`、`Speed`，整体非字典时忽略、单字段缺失或类型不符时回退中性值 1。
- `resources/interaction/TerrainInstanceProtocol.cs`（`internal static`）是 C# 侧唯一读写边界，提供 `TryReadBool`、`SetBool`、`TryReadInt`、`SetInt`、`TryReadBoardPosition`、`TryReadLocalGridPos`、`ReadTerrainData`。每个入口先判断 `terrain is TerrainInstance legacy` 走旧强类型属性，否则走字段协议，因此同一份 C# 代码同时支持旧垫片与新生产实现，回滚只需切换创建点常量。
- 创建点唯一：`core/map/room_terrain_store.gd` 顶部 `TERRAIN_INSTANCE_SCRIPT` 常量。消费者降级只改跨语言那一处：`WorldInteractionContext`、`TerrainInteractionBuildContext` 的 `Terrain` 与 `WorldInteractionPorts` 的 `terrain` 形参改为 `required RefCounted`；`FarmingInteraction`、`GatheringInteraction`、`ReusableGatheringInteraction`、`MarkHarvestedOp` 改用协议读写；`TerrainInteractionExecutor`、`WorldInteractionCoordinator`（14 处形参）、`RoomBoardPresenter`、`BoardController` 改为 `RefCounted` + 协议。棋盘卡集合、视图、存档、战斗与玩法规则仍由原拥有者负责。
- `GameplayPort.cs` 同步移除最后一个 `EncounterManager.Instance` 静态单例读取，改为 `[Export] EncounterManagerPath` + `_Ready` 缓存 `Node` + `ScaleEncounterMonsters` 方法协议并重新过滤返回值；C# 消费者不再编译期依赖任何已迁移类型的静态单例。
- 本批未改 `scenes/Main.tscn`（该场景的 `GameplayPort` 已是 GDScript，通过 `_get_encounter_scaler()` 自行解析缩放器，导出字段对它无意义）。回滚点是恢复 `room_terrain_store.gd` 的常量并回退上述 C# 消费者的类型与读取方式。旧 `TerrainInstance.cs`、`BoardCardState.cs`、`BoardCardView.cs`、`EncounterManager.cs` 与 C# 对照测试继续保留为兼容垫片；本批不迁移 `AttributeComponent`、`StatusComponent`、`DamageReceiverComponent`、`MonsterData`、`Monster`、`Player` 与战斗效果，也不处理 StartingStats、物品链、Crafting、Autoload 收尾与 `AttributeModifierData`。

## AttributeModifierData 生产切换边界

- 新增 `core/combat/status/attribute_modifier_data.gd`（uid `uid://3uivcq44l7gy`）作为旧 `AttributeModifierData.cs` 的等价实现，字段与旧 C# 属性逐字同名（`Type`、`Mode`、`ValuePerStack`），默认值与旧实现一致（`PhysAtk` / `FlatAdd` / `0.0`）；脚本刻意不声明 `class_name`，避免与 C# 类型表冲突。
- 关键边界是数组类型而不是脚本本身：旧 `AttributeModifierStatusData.Modifiers` 声明为强类型 `Array<AttributeModifierData>`，Godot 会在反序列化阶段拒绝 GDScript 条目。本批把它降级为通用 `Godot.Collections.Array`，资产侧同步写 `Modifiers = Array[Resource]([...])`；这也是上一次撤回尝试的真正阻塞点。
- 新增 `core/combat/status/AttributeModifierDataProtocol.cs`（`internal static`）作为唯一读取入口，返回可空结构 `AttributeModifierFields?`：条目是旧 C# 垫片时走强类型属性，否则走 `Get("Type")` / `Get("Mode")` / `Get("ValuePerStack")` 同名字段协议。返回值而非 `out` 参数，是因为 `GetAttributeModifiers()` 是迭代器方法，迭代器内不能用 `out` 局部变量。
- `AttributeModifierStatusInstance.GetAttributeModifiers()` 只换成协议读取，仍然产出旧的 C# `AttributeModifier` record struct；`AttributeComponent.CalculateUnclampedEffectiveValue` 的 `(base + flatAdd) * (1 + percentAdd) * percentMul` 公式、`AttributeModifierMode` 三分支与警告分支完全未变，因此数值语义不变。
- 资产切换只有两处：`resources/effects/strength.tres` 与 `resources/combat_skills/test_card_1.tres` 的修正条目 ext_resource 换成 GDScript 脚本并把数组类型改成 `Array[Resource]`，其余字段（`ValuePerStack=10.0` / `Type=4`、`ValuePerStack=100.0`、`Id=&"strength_up"`、`MaxStacks=999`、`Policy=2`）逐字保留。
- 验证分工是本边界的一部分：编辑器里的 C# Resource 是占位实例，非 `[Tool]` 脚本在 `test_run` 中调用方法会失败，因此 `test_run` 套件只锁定数据形状与源码协议，属性重算的端到端验证必须在运行中的游戏经 `game_eval` 完成。回滚点是恢复两个资产的旧 C# ext_resource（uid `uid://ilmgwp6hkfi`）与 `Array<AttributeModifierData>` 声明。旧 `AttributeModifierData.cs` 继续保留为兼容垫片；本批不迁移 `AttributeModifierStatusData`、`StatusEffectData`、`AttributeComponent`、`StatusComponent` 与其余战斗效果。

## MonsterData 生产切换边界

- 新增 `resources/monster/monster_data.gd`（uid `uid://buhigatdeqss6`）作为旧 `resources/monster/MonsterData.cs` 的等价实现，直接 `extends Resource`，字段与旧 C# 属性逐字同名：`MonsterName`（默认 `"未知怪物"`）、`InitialAttributes: Resource`、`ElementalProperty: int = 0`、`ModelScene: PackedScene`、`LootTable: Resource`、`BehaviorTreeScene: PackedScene`、`Faction: int = 0`、`SkillSet: Resource`。脚本不声明 `class_name`，与 `terrain_instance.gd`、`attribute_modifier_data.gd` 保持同一约定，避免与 C# 类型表产生同名全局类冲突。
- 本批确立的前置结论：**GDScript 无法继承 C# 脚本**。`extends "res://resources/monster/MonsterData.cs"` 与 `extends MonsterData`（全局类名）两种写法都会报 `Parser Error: Could not resolve super class inheritance`。因此凡是要继承 C# 基类的类型（`StatusEffectData` 及其 9 个子类、`CardEffect` 及其 4 个子类、`TerrainInteraction`、`TerrainOp`、`VitalComponentBase`、`InventoryComponent`、`ItemData` 等）都必须连基类成批迁移；`MonsterData` 因直接继承 `Resource` 才成为安全切入点。
- 稳定协议：字段名逐字一致的 `Get`/`Set` 通道 ＋ `resources/monster/MonsterDataProtocol.cs`（`internal static`）。`IsMonsterData(GodotObject)` 先走旧 C# `is MonsterData`，否则比对 `GetScript().As<Script>()?.ResourcePath == "res://resources/monster/monster_data.gd"`；另有 `FilterMonsters(Godot.Collections.Array)`、`ReadMonsterName`、`ReadElementalProperty`、`ReadFaction`、`ReadResourceField`。同一份 C# 代码因此同时支持旧垫片与新生产实现，回滚只需把资产 ext_resource 切回 C#。
- 数组边界沿用上一批的根因：强类型 `Array<MonsterData>` 会在反序列化阶段拒绝 GDScript 条目，所以跨语言容器一律降级为通用 `Array` / `Array[Resource]`——`GatheringEncounterRule.MonsterToSpawn`、`GatheringEncounterResult.MonsterToSpawn`、`GameplayPort.EncounterRequested` 第 3 参与两个 `RequestEncounter` 重载、`IInteractionGameplayPort.RequestEncounter`、`PassageGuardMonsterResolver.MonsterArray`、`battle_manager.gd` 的 `starting_monster_data`。
- 资产切换 54 处：53 个 `resources/monster/*.tres` 的 ext_resource 换成新 uid、移除头部 `script_class="MonsterData"`、`metadata/_custom_type_script` 指向新 uid，其余序列化字段（含技能子资源与掉落子资源）逐字节未动；`scenes/monster_scenes/monster.tscn` 同样只改两行。`scenes/battle_scenes/battle.tscn` 删除 `MonsterData.cs` 的 ext_resource 并把 `starting_monster_data` 从 `Array[ExtResource("6_ajc51")]` 降为 `Array[Resource]`。
- 创建点语义唯一收敛在 `core/application/encounter_manager.gd` 的 `_new_monster_like()`：运行期优先 `source.get_script().new()`；编辑器内非 `@tool` 脚本不允许实例化（`can_instantiate()` 为 false），此时退化为 `source.duplicate(false)` 浅拷贝——脚本与子资源引用保持一致，且随后所有字段都被 `_scale_monster` 显式覆写，因此编辑器套件与运行时得到同一可观察结果，无需给数据脚本加 `@tool`。
- 消费者降级只改跨语言那一处：`entities/Monster.cs` 的 `BaseData` / `Initialize` / `UpdateCardUi` 改 `Resource`，名称、阵营、初始属性、SkillSet 与鼠标提示名称走协议；`DamageReceiverComponent` 的元素倍率走 `MonsterDataProtocol.ReadElementalProperty`；`MonsterSpawnOp`、`BossInteraction`、`WorldInteractionCoordinator`、`WorldCombatScenePresenter`、`TerrainInteractionExecutor`、`PassageGuardMonsterResolver` 与 GDScript 的 `gameplay_port.gd`、`gathering_encounter_result.gd` 同步；`EncounterManager.cs` 的 `ResolveGatheringEncounter` 发生一次显式 `Array<MonsterData>` → `Array<Resource>` 转换以保证编译。
- 回滚点是恢复 53 个资产的 ext_resource（`uid://dh28trwcjvre6` / `res://resources/monster/MonsterData.cs`）与上述 C# 消费者的类型及 `Array` 声明。旧 `MonsterData.cs` 未删除、未改语义；本批不迁移 `MonsterSkillEntryData`、`MonsterSkillSetData`、`MonsterSkillPreview`、`Monster.cs` 之外的实体行为、`core/combat`、`entities/components` 与 Autoload 收尾。

## CombatSkillData / CardEffect 家族生产切换边界

- 新增 6 个 GDScript 生产实现：`core/combat/effects/card_effect.gd`（uid `uid://bu272src84v8y`）、`damage_effect.gd`（uid `uid://0nubbe6tiwxp`）、`modify_attribute_effect.gd`（uid `uid://byc53p0d2p6y8`）、`apply_shield_card_effect.gd`（uid `uid://c15himckpty3d`）、`apply_status_card_effect.gd`（uid `uid://dgau6uej1oyct`）、`core/combat/skills/combat_skill_data.gd`（uid `uid://sxc1b8jrnrys`）。字段名与默认值与旧 C# 属性逐字一致（`BaseDamage=10`、`HitCount=1`、`HitTargetMode=0`、`Type=0`、`Element=0`、`TargetScope=2`、`Primary/SecondaryDamageMultiplier=1.0`、`TargetingType=1`），枚举继续用整数取值（`CardEffectTargetScope` 的 `Source=0/AllTargets=1/PrimaryOnly=2/SecondaryOnly=3`、`SkillTargetRole` 的 `Primary=0/Secondary=1`、`SkillTargetingType` 的 0~6），脚本不声明 `class_name`。
- 继承边界沿用 MonsterData 批的结论：GDScript 不能继承 C# 脚本，因此 `CardEffect` 基类与 4 个子类、`CombatSkillData` 与其 `BaseCardData` 字段**成批迁移**，而不是逐个效果切入。`combat_skill_data.gd` 直接 `extends "res://resources/item/base_card_data.gd"` 并重新声明 `Element` / `TargetingType` / `Effects`。
- 稳定协议：`core/combat/effects/CardEffectProtocol.cs`（uid `uid://ba18ajys7jegc`）与 `core/combat/skills/CombatSkillDataProtocol.cs`（uid `uid://bnqifvua7jr5t`）。识别逻辑统一为“先 `is` 旧 C# 垫片，否则比对 `GetScript().As<Script>()?.ResourcePath`”，读取走 `Get("字段名")`，执行走 `Execute` 方法协议。C# 侧因此同时支持旧垫片与新生产实现，回滚只需把资产 ext_resource 切回 C#。
- 数组边界（沿用 `AttributeModifierData` / `MonsterData` 批同一根因）：强类型 `Array<CardEffect>` 会在反序列化阶段拒绝 GDScript 效果条目，所以 `CombatSkillData.Effects` 与 `AttributeChangeTriggerStatusData.Effects` 必须是通用 `Array`，资产侧统一写 `Array[Resource]`；技能容器（`Monster.GetCombatSkills()` / `MonsterSkillComponent`）同样降级为 `Array<Resource>` / `Resource`。
- 本批新边界（纯 C# DTO → RefCounted）：`DamagePayload`、`SkillExecutionModifierContext`、`DamageEffectHitCountContext`、`DamageEffectSegmentContext` 原本是不继承 `GodotObject` 的纯 C# 类。GDScript 侧 `load("res://….cs").new(...)` 会报 `Invalid call. Nonexistent function 'new' in base 'CSharpScript'`（实测停在 `combat_skill_data.gd:73 @ Execute`），并且纯 C# 对象无法作为 Variant 传给 GDScript。因此这四类显式降级为 `public [sealed] partial class … : RefCounted`：字段、构造参数、执行语义逐字不变，C# 消费者（`StatusComponent`、`DamageReceiverComponent`、`DamageResolutionResult`）无需改动。源生成器接受 `IReadOnlyCollection<StringName>`、`DamageResolutionTrace` 这类不可 marshal 的属性（只是不会被绑定）。
- 编辑器与运行时的判据分工：`Script.can_instantiate()` 对没有默认构造函数的 C# 脚本返回 `false`，不能作为“GDScript 能否构造它”的判据。契约套件只断言 `get_instance_base_type() == "RefCounted"` 与字段形状；“真的能从 GDScript 构造出来并打出伤害”只能在运行中的游戏经 `game_eval` 验证。
- 执行顺序与惰性构造：`combat_skill_data.gd` 保持“开启技能作用域 → 顺序执行效果 → 统一收尾状态”；`SkillExecutionModifierContext` 只在施放者存在 `StatusComponent` 时构造，两次 Hook 仍传同一对象。`damage_effect.gd` 保持“段数修正 → 逐段选目标 → 单段修正 → 构造 `DamagePayload` → `ReceiveDamage`”，最终数值仍由 C# 伤害公式决定。
- 资产切换 87 个文件：69 个 `resources/combat_skills/*.tres`、14 个 `resources/skill_cards/*.tres`、`bmob.tres`、`senketsu.tres`、`resources/effects/strength.tres`、`resources/buffs/draw_when_physAtk_decreased.tres`、`scenes/battle_scenes/battle.tscn`、`scenes/monster_scenes/monster.tscn`。生成脚本 `card_table/export_current_cards.py` 同步改脚本常量、去掉新建资源的 `script_class`、技能数组写 `Array[Resource]`，并在 upsert 时清理旧 `script_class`。
- 回滚点：恢复 87 个资产的旧 ext_resource（`uid://deqpvvm5duhfp` / `uid://b2df0ritlplj8` / `uid://dq1ts5ykp8ai6` 等）与 `script_class="CombatSkillData"`、`Array[ExtResource(...)]`，并把 4 个 DTO 恢复为纯 C# 类、回退两个协议文件。旧 C# 垫片全部保留，未删除任何 `.csproj`、`.sln` 或 C# Autoload；本批不迁移 `core/combat/status` 与 `core/combat/buffs` 其余状态、`entities/components`、`Player.cs`、StartingStats、物品链、Crafting 与 Autoload 收尾。

## StatusEffectData 状态数据族生产切换边界（2026-09-20 20:05）

- 对象与范围：`StatusEffectData`（C# 抽象基类，12 个导出字段：`Id` / `DisplayName` / `Description` / `Icon` / `MaxStacks` / `Policy` / `ExpirePolicy` / `DurationTickTiming` / `DefaultHookPriority` / `InitOwnerTurnDuration` / `InitGlobalTurnDuration` / `InitRoundDuration`）与其 4 个有资产引用的数据子类 `AttributeModifierStatusData` / `ShieldStatusData` / `BurnStatusData` / `AttributeChangeTriggerStatusData`；涉及资产 `resources/effects/strength.tres`、`resources/combat_skills/test_card_1.tres`、`test_card_2.tres`、`bmob.tres`、`resources/buffs/draw_when_physAtk_decreased.tres`。
- 关键判断：把“数据”和“行为”拆开评估。状态数据本身是纯数据载体，`CreateInstance(source, owner)` 是它唯一的动态职责；只要实例类（`AttributeModifierStatusInstance` / `ShieldStatusInstance` / `BurnStatusInstance` / `AttributeChangeTriggerStatusInstance`）仍留在 C#，GDScript 端就只需继承自己写的 GDScript 基类，抽象方法的跨语言硬约束不会触发。这修正了上一批把“状态数据族必须连实例一起搬”的排期结论。
- 生产实现：`core/combat/status/status_effect_data.gd` 直接 `extends Resource` 并重新声明全部 12 个字段（默认值与旧 C# 逐字一致，枚举全部保持 0 基整数：`StackPolicy.ResetDuration=0`、`DurationExpirePolicy.FirstExpired=0`、`DurationTickTiming.Start=0`、`AttributeChangeDirection.Any=0`）；4 个子类 `extends "res://core/combat/status/status_effect_data.gd"`，各带 `const INSTANCE_SCRIPT_PATH`（指向保留的 C# 实例类）与 `CreateInstance`。所有脚本都不声明 `class_name`，避免与 C# 类型表里的同名全局类冲突。
- 唯一协议：`core/combat/status/StatusEffectDataProtocol.cs`。识别分两支：旧垫片走 `value is StatusEffectData`；GDScript 实现走 `IsGdStatusEffectData`——它**沿 `Script.GetBaseScript()` 链逐级向上**比对 `status_effect_data.gd` 的路径，因为子类脚本的 `resource_path` 指向子类自身而不是基类。读取入口 `ReadId` / `ReadText` / `ReadInt` / `ReadFloat` / `ReadTexture` / `ReadArray` / `HasFiniteDuration` / `ReadStackPolicy` / `ReadExpirePolicy` / `ReadTickTiming` 都按字段名同名取值；枚举读取失败时回退到旧 C# 默认值。
- C# 消费者降级：`StatusEffectInstance` 的 `Data` 由 `StatusEffectData` 改为 `Resource`，其 `Id` / `MaxStacks` / `Policy` / `ExpirePolicy` / `TickTiming` / `InitOwnerTurnDuration` / `InitGlobalTurnDuration` / `InitRoundDuration` / `GetHookPriority` / `DisplayDescription` / `IsExpired` 全部改走协议；4 个实例类的构造参数与 `_data` 字段同样降级（`Modifiers` / `Effects` 等数组先读成 `Godot.Collections.Array` 再遍历），实例类自身的状态语义、叠层与计时逻辑一行未改。
- 重载等价：旧 C# `ShieldStatusData` 有两个 `CreateInstance` 重载（带 / 不带 `shield_amount`）。GDScript 侧用 `CreateInstance(source, owner, shield_amount: Variant = null)` 的默认参数等价实现，显式传入与按字段推导两条路径都保留。
- 新增根因（写入排期检查项）：**Godot 解析 C# 脚本时要求“文件名 == 类名”**。`BurnStatusDataInstance.cs` 中声明的类是 `BurnStatusInstance`，C# 编译无警告，但 Godot 侧 `get_instance_base_type()` 返回空字符串（同族其余脚本返回 `RefCounted`），导致 GDScript `load(...).new()` 报 `Invalid call. Nonexistent function 'new' in base 'CSharpScript'`；重命名文件与 `.uid` 旁车后即恢复。同时确认 `Script.can_instantiate()` 对无默认构造函数的 C# 脚本**一律为 false**、`has_method("new")` 也不可靠，只有 `get_instance_base_type()` 是否为空可用于诊断。
- 验证：聚焦套件 `status_effect_data_contract` 8/8（132 断言）；全量 21 个套件 173/173；C# `dotnet build --no-restore --no-incremental` 0 警告 0 错误；运行时 run 21 经真实 `SkillExecutionContext` 验证 `strength.tres`（状态数 0→1、`PhysAtk` 100→110）与 `bmob.tres`（状态数 1→2、HP 1000→995、`status_ids=["strength_up","bomb_burn"]`），游戏日志无脚本/解析/加载/信号/类型错误。
- 回滚点：把 5 个资产的 ext_resource 改回 `AttributeModifierStatusData.cs` / `ShieldStatusData.cs` / `BurnStatusData.cs` / `AttributeChangeTriggerStatusData.cs` 并恢复 `script_class`，同时回退 `StatusEffectInstance.cs` 与 4 个实例类的 `Resource` 降级以及 `StatusEffectDataProtocol.cs`。旧 C# 垫片全部保留，未删除任何 `.csproj`、`.sln` 或 C# Autoload；本批不迁移 `core/combat/status` + `buffs` 其余 5 组状态数据/实例、`entities/components`（`AttributeComponent` / `DamageReceiverComponent` / `StatusComponent`）、场景根脚本、StartingStats、物品链、Crafting 与 Autoload 收尾。

## StatusComponent 生产切换边界（2026-09-20 21:10）

- 对象与范围：`entities/components/StatusComponent.cs`（C# `Node` 子类）改为 `entities/components/status_component.gd`（uid `uid://teq3xtey3ker`，`extends Node`，不声明 `class_name`）。方法面逐字保留 20 个公开入口：`GetActiveStatusesSnapshot` / `HasStatus` / `GetStatusOrNull` / `AddStatus` / `RemoveStatus` / `ClearAllStatuses` / `OnTurnStarted` / `OnTurnEnded` / `OnRoundStarted` / `OnRoundEnded` / `ProcessBeforeAttributeChange` / `ProcessAfterAttributeChanged` / `ProcessBeforeSkillExecution` / `ProcessAfterSkillExecution` / `ApplyDamageHitCountModifiers` / `ApplyDamageEffectSegmentDamageModifiers` / `ApplyModifyOutgoingDamage` / `ApplyModifyIncomingDamageBeforeMitigation` / `ApplyModifyIncomingDamageAfterMitigation` / `ApplyBeforeHealthDamage`。`PHASE_*`（16）/`REASON_*`（0~5）/`POLICY_*`（0~2）/`TIMING_*`（0~1）四组常量与旧枚举整数逐项一致。
- 四条跨语言边界规则（本批确立，后续组件批次直接复用）：
  1. **`ref` 参数不可跨语言** → 在 C# 侧补返回值的非 ref 包装。`StatusEffectInstance` 新增 `ApplyModifyDamageHitCount` / `ApplyModifyDamageEffectSegmentDamage` / `ApplyModifyOutgoingDamage` / `ApplyModifyIncomingDamageBeforeMitigation` / `ApplyModifyIncomingDamageAfterMitigation` / `ApplyBeforeHealthDamage`；`StatusComponent.cs` 垫片补齐 4 个聚合包装。
  2. **C# `event` 不可被 GDScript 订阅** → 改为 Godot 信号。`StatusChanged(change_event)` 取代 `StatusChangedDetailed`；载荷 `StatusChangeContext` 降级 `RefCounted` 后由消费方 `Call("GetFeedbackNode", ...)` 读取。
  3. **跨语言 DTO 必须 `RefCounted`**。`StatusChangeContext.cs`、`AttributeChangeContext.cs` 由纯 C# 类降级。
  4. **接口集合属性必须补快照方法**。`SkillExecutionModifierContext.GetStatusIdsMarkedForConsumptionSnapshot()` 返回 `Godot.Collections.Array<StringName>` 取代 `IReadOnlyCollection<StringName>` 属性。
- C# 消费者改写：`ComponentLookup.GetStatusComponentOrNull` 返回 `Node`；`AttributeComponent` 的 `_statusComponent` 降级并用 `Connect("StatusChanged", Callable.From<RefCounted>(HandleStatusChangedSignal))` 订阅（含 `_statusSubscribed` 防重复连接与 `_ExitTree` 断开）；`DamageReceiverComponent` 新增 `ApplyStatusDamageModifier` 统一 4 处非 ref 包装调用；`Player`/`Monster` 的 `Status` 与 `GetNode` 降级为 `Node`；`CombatSkillData` / `ApplyShieldCardEffect` / `ApplyStatusCardEffect` / `DamageEffect` / `ShieldStatusInstance` 五个垫片动态化。`StatusEffectInstance.AppliedSequence` 由 `internal set` 改为可写。
- 语义保真点：`_tick_turn_durations` 保留旧 C# `|=` 的非短路求值语义（避免同日多状态到期的处理顺序变化）；`_notify_status_changed` 在迁移期通过 `load("res://core/combat/status/StatusChangeContext.cs")` 构造旧 C# 载荷，让旧 C# 订阅方仍可工作，属过渡兼容输入。
- 资产/场景切换 2 处：`scenes/player_scenes/player.tscn`、`scenes/monster_scenes/monster.tscn` 的组件 ext_resource 由 `StatusComponent.cs`（uid `uid://gek5smi6lrcs`）切到 `status_component.gd`（uid `uid://teq3xtey3ker`）。
- 验证：聚焦套件 `status_component_contract` 9/9（140 断言）；全量 22 套件 182/182；C# `dotnet build --no-restore --no-incremental` 0 警告 0 错误；运行时 run 23 端到端验证状态加成（`0→1`、`PhysAtk 100→110`）、承伤修正（`bmob.tres` 使 HP `1000→995`）与灼烧计时（`OwnerTurnDuration 5→4`、HP `995→993`）；run 24 验证两个场景脚本切换；游戏日志无脚本/解析/加载/信号/类型错误。
- 回滚点：把两个场景的 ext_resource 与 uid 切回 `StatusComponent.cs`，并回退 `AttributeComponent` / `DamageReceiverComponent` / `Player` / `Monster` / `ComponentLookup` 的 `Node` 降级、`StatusEffectInstance` 的包装与 `internal set` 修改、两个 DTO 的 `RefCounted` 降级、`SkillExecutionModifierContext` 的快照方法。旧 C# 垫片全部保留，未删除任何 `.csproj`、`.sln` 或 C# Autoload。
- 本批不迁移：`AttributeComponent` / `DamageReceiverComponent`（下一批）、`entities/Monster.cs` / `entities/Player.cs` / `core/board/BoardController.cs` / `core/gameflow/WorldInteractionCoordinator.cs` / `core/map/RoomBoardPresenter.cs`（场景根脚本批次）、`core/combat/status` + `buffs` 剩余 5 组状态数据/实例、StartingStats、物品链、Crafting、Autoload 收尾。

## DamageReceiverComponent 生产切换边界（2026-09-20 22:40）

- 对象与范围：`entities/components/DamageReceiverComponent.cs`（C# `Node` 子类）改为 `entities/components/damage_receiver_component.gd`（uid `uid://dwdggwaghdncs`，`extends Node`，不声明 `class_name`）；连同**只被它使用**的两个纯计算类 `core/combat/DamageFormula.cs`、`core/combat/ElementalSystem.cs` 一起迁移为 `core/combat/damage_formula.gd`（uid `uid://cs2jb4l4ia5pe`）、`core/combat/elemental_system.gd`（uid `uid://cxavd0ykhd2ox`）。选点依据是消费者计数：`rg -c 'DamageFormula\.|ElementalSystem\.'` 在迁移前只命中 `DamageReceiverComponent.cs`，因此这四件事构成一个封闭边界。
- 对外协议面：信号 `DamageResolved(result)`（载荷仍是保留的 C# `DamageResolutionResult`，经 `load(...).new(payload, preGuard, actual, evaded, critical, lethal)` 构造）；方法 `ReceiveDamage(payload)`；导出属性 `RandomVarianceMin = 0.95` / `RandomVarianceMax = 1.05`。诊断文本（`DamageReceiverComponent received null damage payload.` / `has no parent defender.`）与旧 C# 逐字一致。
- 数据读取边界（本批的核心设计）：三类外部数据都走“节点名 + 字段/方法协议”，不使用任何 C# 类型——① 属性值 `component.get("PhysAtk")` / `PhysDef` / `PhysPenetrationRate` / `FixedPhysPenetration` / `MagPower` / `MagResist` / `MagicPenetrationRate` / `FixedMagicPenetration` / `CritRate`（缺省 1.0 的 `CritDamage`）/ `EvasionRate` / `LifestealRate`，属性名与旧 C# `[Export]` 属性逐字同名，因此 C# 与未来 GDScript 属性组件都能被同一份代码读取；② 生命 `health.call("TakeDamage", finalDamage, element)` 与 `health.get("CurrentValue")`；③ 状态修正 4 个非 ref 包装 `ApplyModifyOutgoingDamage` / `ApplyModifyIncomingDamageBeforeMitigation` / `ApplyModifyIncomingDamageAfterMitigation` / `ApplyBeforeHealthDamage`（沿用上一批建立的包装边界）。怪物五行属性读 `defender.get("BaseData").get("ElementalProperty")`，与 `action_timeline.gd` 的既有跨语言读法一致。
- 公式脚本：`damage_formula.gd` 与 `elemental_system.gd` 均 `extends RefCounted`、只提供与旧 C# 同名的静态函数（`CalculatePhysicalBaseDamage` / `CalculateMagicBaseDamage` / `CalculateEffectiveResistance` / `ShouldEvade` / `ShouldCrit` / `CalculateCriticalModifier` / `CalculateRandomVariance` / `CalculateActualDamage` / `CalculateLifestealAmount`、`CalculateMultiplier`），调用方 `preload` 后按脚本常量访问。伤害公式常数取自旧 `CombatConstants.DamageFormulaConstant = 100f`；五行矩阵为绕开“元组键不能做常量”改用 `攻击 * 10 + 防御` 整数键，五个相克 1.5、五个被克制 0.5 与旧 C# 元组字典逐项对应；天气修正通过 `Engine.get_main_loop()` → `root.get_node_or_null("WeatherManager")` → `CurrentWeather.ElementModifiers[元素整数]` 读取，兼容 GDScript 与 C# 天气管理器。
- 日志文本保真：旧 C# 用枚举插值打印 `Element: None` / `Type: Physical` / `Critical: False`，GDScript 只能读到整数，因此新增 `ELEMENT_NAMES`（`None/Wood/Metal/Water/Earth/Fire`）与 `DAMAGE_TYPE_NAMES`（`Physical/Magic/Real`）名称表与 `_bool_text()`；契约套件从 `ElementType.cs` / `DamagePayload.cs` 反向读取枚举成员名与顺序逐项比对，运行时实测日志为 `[Damage] Target: Monster | Source: Player | Damage: 100 | Critical: False | Element: None | Type: Physical`，与旧 C# 完全一致。
- C# 消费者改写 2 处：`core/combat/effects/DamageEffect.cs` 的 `GetNodeOrNull<DamageReceiverComponent>` → `GetNodeOrNull<Node>(...)` 并把 `receiver.ReceiveDamage(payload)` → `receiver.Call("ReceiveDamage", payload)`；`core/combat/buffs/BurnStatusInstance.cs` 同样降级为 `Node` 并改走 `Call("ReceiveDamage", payload)`。`scripts/battle_scripts/combat_feedback_director.gd` 早已是 `has_signal("DamageResolved")` + `GetFeedbackInt/GetFeedbackBool/GetFeedbackNode` 的动态读法，无需改动。
- 资产/场景切换 2 处：`scenes/player_scenes/player.tscn`、`scenes/monster_scenes/monster.tscn` 的组件 ext_resource 由 `DamageReceiverComponent.cs`（uid `uid://delpo10ufxcco`）切到 `damage_receiver_component.gd`（uid `uid://dwdggwaghdncs`），`metadata/_custom_type_script` 同步。
- 验证：聚焦套件 `damage_receiver_contract` 9/9（137 断言：脚本基类型与文档顺序、方法/导出属性面、公式逐项等价、五行十个属性对与旧 C# 元组字符串互证、枚举名称与修饰位同步、场景切换、C# 消费者协议化、垫片未被掏空、结算顺序 12 个标记位序）；全量 23 套件 191/191；`dotnet build --no-restore --no-incremental` 0 警告 0 错误；运行时三条链路（物理伤害 100/100 → 100、强度状态后 atk 110 → 105、灼烧经 C# `BurnStatusInstance` 打到 GDScript 组件 10 点真实伤害）全部符合预期，游戏日志无脚本/解析/加载/信号/类型错误，编辑器日志零新增。
- 回滚点：把两个场景的 ext_resource 与 `metadata/_custom_type_script` 切回 `DamageReceiverComponent.cs`（uid `uid://delpo10ufxcco`），并回退 `DamageEffect.cs` / `BurnStatusInstance.cs` 的 `Node` 降级与两个 `.Call("ReceiveDamage", ...)`；三个新 `.gd` 与 uid 旁车可整体删除。旧 `DamageReceiverComponent.cs` / `DamageFormula.cs` / `ElementalSystem.cs` 全部保留为兼容垫片与对照实现，未删除任何 `.csproj`、`.sln` 或 C# Autoload。
- 已知重复成本：`DamageFormula.cs` / `ElementalSystem.cs` 与新 GDScript 实现并存（迁移期刻意如此，C# 侧仅剩垫片使用），数值等价性由契约套件的公式与矩阵断言锁定；全量迁移收尾时可删 C# 侧。本批不迁移：`AttributeComponent`（需先决定 `Attribute` / `RecalculateRequest` / `AttributeChangeReason` 的跨语言承载）、`entities/Monster.cs` / `entities/Player.cs` / `core/board/BoardController.cs` / `core/gameflow/WorldInteractionCoordinator.cs` / `core/map/RoomBoardPresenter.cs`（场景根脚本批次）、`core/combat/status` + `buffs` 剩余 5 组状态数据/实例、StartingStats、物品链、Crafting、Autoload 收尾。

## Player 生产切换边界（2026-09-20 20:32）

### 范围

- 新增 `entities/player.gd`（uid `uid://chi5xxdxm0amm`）作为玩家根节点的生产实现；`entities/Player.cs` 保留为兼容垫片，一行未删。
- `scenes/player_scenes/player.tscn` 根节点脚本由 `entities/Player.cs`（uid `uid://dke2t2x325k63`）切到 `entities/player.gd`，复用原 `ext_resource id="1_d8qmr"`，节点结构与 `unique_name_in_owner` 标记完全不变。

### C# / GDScript 兼容边界

- 玩家根节点只是“组件定位 + 信号转发 + 稳定方法协议”的壳：`Energy` / `Attributes` / `BattleDeck` / `Equipment` / `Status` / `TagComponent` 六个公开属性与 `_health` / `_satiety` / `_inventory` 三个私有引用全部降级为 `Node`，组件本身可以来自任一语言。
- 行为入口全部按方法协议调用：饥饿归零 `_health.call("TakeDamage", 5, 0)`、死亡 `_global_event_bus.emit_signal("player_died")`、天赋 `Apply` 走 `has_method("Apply")` 过滤、库存写入走 `_inventory.call("AddItem", item, amount)` 并沿用“返回未放入数量 == 0 才算成功”的旧语义。
- 跨语言物品堆叠读取等价旧 C# `ItemStackProtocol.TryRead`：只依赖 `SetItem` / `Clear` / `Item` / `Amount` / `IsEmpty` 五个稳定成员，空堆叠、非 Resource 物品与 `amount <= 0` 一律拒绝。
- 路径常量必须是 `NodePath`（`^"..."`），信号名才用 `StringName`（`&"..."`）。运行时会因 `get_node(StringName)` 抛 `Parser Error: Cannot pass a value of type "StringName" as "NodePath"`，本批已踩并被契约套件反向锁定。
- 回滚点：把 `player.tscn` 的 ext_resource 切回 `uid://dke2t2x325k63` / `res://entities/Player.cs`，再回退 11 个 C# 消费者的 `Node` 降级与调用的稳定协议；`entities/player.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### C# 消费者改写（11 处）

- `core/application/GameplayPort.cs`：`private Player _player` → `private Node _player`，`GetNode<Player>` → `GetNode<Node>`，`public Player Player` → `public Node Player`，`TryAddItemToInventory` 改走 `_player.Call("TryAddItemToInventory", stack).AsBool()`。
- `core/gameflow/TerrainInteractionExecutor.cs`：新增 `GetPlayerEquipment` 助手（显式空值判断，避免 `?.` 作用在返回 `Variant` 的 `Get()` 上），`GetPlayer` 返回类型改 `Node`。
- `core/gameflow/WorldInteractionCoordinator.cs`：同构改写，新增 `GetGameplayEquipment`，长按耗时入口改读动态装备节点。
- `resources/interaction/GatheringInteraction.cs` / `ReusableGatheringInteraction.cs`：`context.Player.Equipment` → `context.Player.Get("Equipment").AsGodotObject() as Node`，保留 `GetGatheringYieldBonus` / `GetGatheringTimeReduction` 方法协议。
- `core/ui/InventoryUI.cs`：属性节点改按 `Get("Attributes")` 取，装备节点按 `Get("Equipment")` 取后再降级为旧 `EquipmentComponent`。
- `core/debug/DebugLoadoutSeeder.cs`：`GetNodeOrNull<Player>` → `GetNodeOrNull<Node>`。
- `resources/interaction/TerrainInteractionBuildContext.cs`：`required Player Player` → `required Node Player`。
- `resources/talents/TalentEffect.cs` / `AttributeTalentEffect.cs` / `TagTalentEffect.cs`：`Apply(Player)` → `Apply(Node)`；`AttributeTalentEffect` 继续使用旧代码的相对路径 `"AttributeComponent"`（刻意不修正以免行为漂移）；`TagTalentEffect` 改从 `Get("TagComponent")` 取节点后 `Call("AddTag", ...)`。

### 验证

- 聚焦套件 `player_contract` 9/9（146 断言：脚本基类型与文档顺序、公开字段/方法/节点路径与旧 C# 互证、信号名与伤害数值与三条日志文本、堆叠协议、场景切换与节点结构、11 个 C# 边界片段、全项目生产 C# 无 `Player` 强类型残留、垫片未被掏空、天赋签名与旧路径）。
- 全量回归 24 套件 200/200；`dotnet build CUSGA.csproj --no-restore --no-incremental` 0 警告 0 错误。
- 运行时：实例化 `player.tscn` → 根脚本为 `res://entities/player.gd`、`Status` 为 `status_component.gd`、`Attributes` 为 C# `AttributeComponent` 且 `PhysAtk=100`、`Equipment` / `TagComponent` / `BattleDeck` / `Energy` 全部解析成功；调用 `OnSatietyDepleted()` 后 HP `1000 → 995`；空物品堆叠经 `TryAddItemToInventory` 正确返回 `false`。再实例化 `Main.tscn`：GDScript `gameplay_port.gd` 的 `Player` 属性拿到正是场景里那个 GDScript 玩家节点，`PlayerBattleDeck` / `PlayerHealth` / `PlayerInventory` / `PlayerCraftingNode` 全部非空，地图生成链路完整跑通。游戏与编辑器日志无 `SCRIPT ERROR`、Parse Error、Failed to load script、资源加载失败、信号或类型错误。

### 本批不迁移

- `entities/components/AttributeComponent.cs`（玩家场景与怪物场景仍引用，需先决定 `Attribute` / `IReadOnlyAttribute` / `AttributeRecalculateRequest` / `AttributeChangeReason` 的跨语言承载）。
- `entities/Monster.cs`、`core/board/BoardController.cs`、`core/gameflow/WorldInteractionCoordinator.cs`、`core/map/RoomBoardPresenter.cs` 四个场景根脚本。
- `core/combat/status` + `buffs` 剩余 5 组状态数据/实例、StartingStats、物品链、Crafting、Autoload 收尾。

## AttributeComponent 生产切换边界（2026-09-20 20:45）

### 属性域承载：三个纯数据 RefCounted

`AttributeComponent.cs` 的依赖里既有枚举（`AttributeType`/`AttributeChangeReason`/`AttributeRecalculateScope`）又有值类型（`Attribute`/`AttributeChangeContext`/`AttributeChangedEvent`），都属于“数据而非行为”，因此不引入新协议层，直接按同名同字段的 GDScript 纯数据脚本承载：

- `core/attributes/attribute_value.gd`：等价 `Attributes.cs` 的 `Attribute`，`Type`/`DisplayName`/`BaseValue`/`BonusValue`/`AllocatedPoints`/`GrowthPerPoint` + 计算属性 `RawValue`，方法 `Initialize/AddPoint/AddBonus/RemoveBonus/SetBaseValue`。
- `core/attributes/attribute_change_context.gd`：等价 `AttributeChangeContext.cs`，字段面（`Owner`/`Source`/`Type`/`Reason`/`TypeId`/`ReasonId`/`OldValue`/`OriginalNewValue`/`NewValue`/`IsCancelled`/`Delta`/`IsIncrease`/`IsDecrease`）与方法 `Initialize/Cancel/MatchesDirection`，常量 `DIRECTION_ANY/INCREASE/DECREASE = 0/1/2`。
- `core/attributes/attribute_changed_event.gd`：等价 `AttributeChangedEvent.cs`，`Initialize(context)` 用 `context.get(...)` 读字段，因此 C# 与 GDScript 两种上下文都能转成同一事件载荷。
- 三个脚本一律 `extends RefCounted`、不声明 `class_name`：同名 C# 全局类仍在类型表里，声明 `class_name` 会直接冲突。

### 生产实现与 C# 边界

- `entities/components/attribute_component.gd`（uid `uid://ba4f811xp0el`，`extends Node`、无 `class_name`）逐行等价迁移旧 C#：三段状态组件回退查找（`"StatusComponent"` → `"Components/StatusComponent"` → `"%StatusComponent"`）、15 条默认值与展示名、`(base + flatAdd) * (1 + percentAdd) * percentMul` 公式、Before/After 拦截链路、`MaxRecalculateRequestsPerFlush = 64`、`HealthComponent`/`EnergyComponent` 相对宿主路径 + `InitializeMax`/`SetMaxValuePreservingCurrent` 方法协议、`_round_to_int` 复刻 `Mathf.RoundToInt` 的银行家舍入。
- 属性修饰跨语言出口（**API 增补**，与批次 17 给 ref Hook 加非 ref 包装同理）：C# `StatusEffectInstance` 新增 `public virtual Godot.Collections.Array GetAttributeModifiersData()`，由 `AttributeModifierDataProtocol.ToDictionary` 统一写出 `Type/Mode/ValuePerStack/Stacks/SourceId`；`AttributeModifierStatusInstance` 无需覆盖（基类已迭代其 `GetAttributeModifiers()`）。GDScript 侧 `_read_attribute_modifiers` 只认这一个出口，避免语言切换后静默漏算加成。
- C# 属性变化钩子签名放宽：`StatusEffectInstance.OnBeforeAttributeChange` / `OnAfterAttributeChanged` 由 `AttributeChangeContext` 改为 `Variant`；`AttributeChangeGuardStatusInstance` 与 `AttributeChangeTriggerStatusInstance` 改按 `Get("Type")` / `Call("MatchesDirection", ...)` / `Get("OldValue")`+`Get("Delta")` / `Set("NewValue", ...)` / `Call("Cancel")` 读写。`AttributeChangeTriggerStatusInstance` 是 GDScript 状态数据 `CreateInstance` 指向的运行时实例（`resources/buffs/draw_when_physAtk_decreased.tres`），属真实路径而非死代码。
- C# 消费者降级：`entities/Monster.cs`、`entities/Player.cs` 的 `Attributes` 由 `AttributeComponent` 改为 `Node`，初始化改走 `Call("InitializeWithData", ...)`。其余仍持有 C# 强类型的调用方（`AttributeSummaryUI.cs`、`EquipmentComponent.cs`、`DamageReceiverComponent.cs`、`ModifyAttributeEffect.cs`、`AttributeTalentEffect.cs`、`DebugLoadoutSeeder.cs`）都是未挂场景的垫片，生产脚本分别为 `attribute_summary_ui.gd` / `equipment_component.gd` / `damage_receiver_component.gd` / `modify_attribute_effect.gd` / `attribute_talent_effect.gd` / `debug_loadout_seeder.gd`。
- 旧批次遗漏修正：`scenes/Main.tscn` 的 `Player` 节点此前用 `script = ExtResource("14_v0vrg")` 覆盖 player.tscn 的 GDScript 根脚本，导致主场景玩家实际仍跑 `entities/Player.cs`（上一批的“资产侧 C# 引用 11 → 10”因此少算一处）；本批删除该覆盖与对应 `ext_resource`，主场景玩家才真正运行 `player.gd`。
- 资产切换 2 处：`player.tscn`（id `5_k3sny`）、`monster.tscn`（id `2_twjs6` 且 `metadata/_custom_type_script` 同步）。
- 回滚点：两个场景 ext_resource 切回 `uid://ckflk2am2hx30` / `res://entities/components/AttributeComponent.cs`，回退 3 个 C# 边界（状态基类钩子、两个状态实例、Monster/Player）与 Main.tscn 的脚本覆盖；四个新 `.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### 遗留边界

- 本项目把 GDScript 的 `inference_on_variant` 当作错误：`var x := SCRIPT.new()` 会让游戏启动即停在 `Parser Error: The variable type is being inferred from a Variant value`。脚本构造一律写 `SCRIPT.new() as RefCounted` 或用显式类型，已写成回归断言。
- 状态实例仍是 C#（`AttributeModifierStatusInstance` 等由 GDScript 状态数据 `CreateInstance` 构造）：编辑器侧会报“无参数构造函数”警告，运行时实测构造与读取均正常，属已知噪声。

## Monster 生产切换边界（2026-09-20 20:53）

- 生产根脚本：`entities/monster.gd`（`extends Node2D`，不声明 `class_name`），逐行等价旧 `entities/Monster.cs`；旧 C# 文件完整保留为兼容垫片。
- 公开面逐字保持：`signal DeathPresentationRequested`、`@export var BaseData: Resource`、`Health` / `Attributes` / `Faction` / `Status` / `SkillComponent` / `Loot`（全部 `Node`）、`Initialize(Resource)`、`TryClaimDeathPresentation()`、`FinalizeCombatDeathPresentation()`、`FinalizeUnclaimedDeath()`、`ApplyTargetSelectionVisual(...)`、`StartTargetSelectionPulse(...)`、`StopTargetSelectionPulse()`、`ResetTargetSelectionVisual(...)`、`TweenVisualScale(...)`、`ResetVisualScale(...)`、`GetCombatSkills()`、`GetRandomCombatSkill()`。调用方 `card_manager.gd` / `battle_manager.gd` / `combat_feedback_director.gd` / `monster_manager.gd` 全部走 `has_method` / `call` / `BaseData` 赋值，无需改动。
- 组件边界：`Components/AttributeComponent`、`Components/FactionComponent`、`Components/HealthComponent`、`%StatusComponent` 用 `get_node` 硬取（保持旧 `GetNode` 的失败语义）；`Components/LootComponent`、`Components/SkillComponent` 用 `get_node_or_null`（保持旧 `GetNodeOrNull` 的可选语义）。生命 `Depleted` / `ValueChanged` 仍连缓存 Callable，`_exit_tree` 精确断开，鼠标 `mouse_entered` / `mouse_exited` 同样成对断开。
- 数据协议：怪物数据字段（`MonsterName` / `ElementalProperty` / `Faction` / `InitialAttributes` / `SkillSet`）按字段名读取，兼容旧 C# `MonsterData` 与 `monster_data.gd`；初始属性缺失时回退 `starting_stats.gd` 新实例（等价旧 `new StartingStats()`）。技能过滤按脚本路径同时接受 `combat_skill_data.gd` 与 `CombatSkillData.cs`，对应 C# 侧仍保留的 `CombatSkillDataProtocol`。
- C# 消费者降级：`entities/components/DamageReceiverComponent.cs` 的属性克制由 `defender is Monster` 改为 `defender.Get("BaseData").AsGodotObject() as Resource` + `MonsterDataProtocol.ReadElementalProperty(...)`。生产侧 `damage_receiver_component.gd` 本来就是同一条字段协议，两侧一致；此前该分支会让 GDScript 怪物静默失去五行克制。
- 视觉协议：`visualNodePaths = ["Sprite2D","CardName","Element","MonsterAttribute","StatusEffectBar","TargetSelectionOutline"]`（故意不含 `HealthBar`，避免高亮时血条跟着放大）；`Node2D` 取 `scale` / `position`，`Control` 取 `scale` / `position`，`CanvasItem` 存调制基色；`Sprite2D` 用绝对目标缩放、其余内部节点按基准倍率；静态 Tween 与呼吸 Tween 互斥。
- 已知诊断差异：旧 C# 在缺 `HealthBar` 时抛 `NullReferenceException`，GDScript 侧以 `push_error("HealthBar node is missing on Monster!")` + 提前返回表达同一硬失败语义，文本保持不变。
- 回滚点：`scenes/monster_scenes/monster.tscn` 的 ext_resource（id `1_1wyrm`）切回 `uid://wl3ajed8xmqo` / `res://entities/Monster.cs`，回退 `DamageReceiverComponent.cs` 一处与 `test_attribute_component_contract.gd` 的状态断言；`entities/monster.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

## BoardController 生产切换边界（2026-09-20 21:04）

这一批与前面“数据 Resource 批量迁移”的区别：`BoardController` 是**场景根脚本 + 跨语言信号源**，它的类型从 C# 消失会连锁影响三个 C# 消费方，所以边界必须一次性设计完整。

### 兼容边界

- 生产脚本：`core/board/board_controller.gd`（uid `uid://b8oardc7t2mqk`，`extends Node2D`、不声明 `class_name`），逐行等价旧 `core/board/BoardController.cs`；旧 C# 文件完整保留为兼容垫片。
- 公开面逐字保持：7 个信号（`CardSpawned` / `CardRemoved` / `CardClicked` / `CardPressed` / `CardReleased` / `CardHoverStarted` / `CardHoverEnded`，参数均 `Node2D card`）、4 个导出（`CardViewScene: PackedScene`、`CardsRootPath: NodePath`、`ScatterRadiusMin = 40.0`、`ScatterRadiusMax = 90.0`）、9 个公开方法 `SpawnTerrainCard` / `SpawnLootCard` / `SpawnLootCards` / `RemoveCard` / `ClearAllCards` / `TryGetTerrainCardByLocalGrid` / `GetTerrainCardByLocalGridOrNull` / `HasTerrainCardAtLocalGrid` / `GetActiveCardsSnapshot`。
- 唯一的签名差异（GDScript 无 `out`）：旧 `bool TryGetTerrainCardByLocalGrid(Vector2I gridPos, out Node2D card)` 在 GDScript 侧等价为 `func TryGetTerrainCardByLocalGrid(grid_pos: Vector2i) -> Node2D`，与 `GetTerrainCardByLocalGridOrNull` 同路径；C# 垫片保留原 `out` 签名，两侧公开方法名集合由契约套件归一化后逐名核对（必须完全相等）。
- 卡状态：`preload("res://core/board/board_card_state.gd")` 后 `.new()`，两侧共用同一份状态脚本；`IsTerrain` / `IsLoot` 判定与 `InitializeTerrain` / `InitializeLoot` 调用顺序不变。
- 跨语言数据读取：局部网格坐标经字段协议 `terrain.get("LocalGridPos")`（等价旧 `TerrainInstanceProtocol.TryReadLocalGridPos`），物品堆叠按 `Item` + `Amount` + `IsEmpty`（等价旧 `ItemStackProtocol.TryRead`）。
- 失败语义：旧 C# 抛 `InvalidOperationException` / `ArgumentException` 的三处（`CardViewScene` 未设置、网格重复、状态未知、`TerrainData` 为空、堆叠协议不完整）改为同文本 `push_error` + 返回 `null`；日志文本 `[BoardController] Spawn terrain card at ...` / `Removing card: ...` / `Removed card: ...` / `Card clicked: ...` 逐字一致。

### C# 消费者降级（三处）

- `core/map/RoomBoardPresenter.cs`：`_boardController` 由 `BoardController` 降为 `Node`，`GetNode<BoardController>` → `GetNode<Node>`，调用改为 `Call("ClearAllCards")` / `Call("SpawnTerrainCard", terrain, boardPosition)`。房间进入顺序、`HasRoom` / `CreateInitialRoomLayout` / 地形字典遍历顺序都不变。
- `core/gameflow/TerrainInteractionExecutor.cs`：主构造函数与 `BoardInteractionPort` 的棋盘参数降为 `Node`，`Call("SpawnLootCards", drops, spawnOrigin)` / `Call("RemoveCard", sourceCard)`。
- `core/gameflow/WorldInteractionCoordinator.cs`：`_boardController` 降为 `Node`，四个 `+=`/`-=` 事件改按稳定信号名 `Connect` / `Disconnect`（新增 `DisconnectBoardSignal(...)` 助手，`IsConnected` 守卫 + 同一个 `Callable` 实例）；`RemoveCard` 与时间刷新使用的 `GetActiveCardsSnapshot()` 改走 `Call`（快照按 `AsGodotArray()` 遍历并显式 `as Node2D`）。
- 回滚点：`scenes/Main.tscn` 的 ext_resource（id `2_0bbpv`）切回 `uid://bv1xoc07ydxw7` / `res://core/board/BoardController.cs`，回退上述三个 C# 文件与三个测试文件；`core/board/board_controller.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### 遗留边界

- 本批新暴露的阻塞类型：Godot 4 的整型向量类型是 `Vector2i`，写成 `Vector2I` 时编辑器扫描与契约套件都不报错，只在**游戏启动**时以 `Parser Error: Could not find type "Vector2I" in the current scope.` 卡在 debugger break。已写入回归断言，规则同前一批的 `NodePath` 常量。
- 运行时探针里 `SpawnLootCards` / `CardClicked` 这类跨语言调用只覆盖“协议可用”，真实玩法路径（房间进入 → 地形卡 → 点击 → 交互执行）由 `Main.tscn` 冒烟覆盖；`GameplayPort` / `Enemy` 等尚未迁移的 C# 仍可能按类型判断棋盘卡，需在最终清理审计中复查。

## RoomBoardPresenter 生产切换边界（2026-09-20 21:06）

这一批是“无跨语言调用方的场景根脚本”：全项目没有任何 C# 按类型引用 `RoomBoardPresenter`，因此边界只在**资产侧**（Main.tscn 的 ext_resource）与**协议侧**（它调用的仓库/生成器/棋盘）。

### 兼容边界

- 生产脚本：`core/map/room_board_presenter.gd`（uid `uid://b1rmprsnt7kq4`，`extends Node`、不声明 `class_name`），逐行等价旧 `core/map/RoomBoardPresenter.cs`（194 行）；旧 C# 文件完整保留为兼容垫片。
- 序列化面逐字保持：`@export var MapSystemPath: NodePath`、`BoardControllerPath: NodePath`、`TerrainStorePath: NodePath`、`HideHarvestedTerrain: bool = true`。主场景节点类型仍是 `Node`、三个 `NodePath(...)` 值与节点层级零改动，只替换 ext_resource（id `1_elqb8`）。
- 失败语义：三处缺路径的 `InvalidOperationException` 与“MapSystem 缺少信号”“缺少地形布局生成器脚本”改为同文本 `push_error` + `return`。顺序必须与旧 C# 的 `throw` 一致（先校验三个路径，再取节点，再建生成器，最后查信号），否则会多出一条 `get_node("")` 报错。
- 跨语言读取：地形配置 `terrain.get("TerrainData")`、采集状态 `terrain.get("IsHarvested")`、显示位置 `terrain.get("BoardPosition")`，等价旧 `TerrainInstanceProtocol.ReadTerrainData` / `TryReadBool` / `TryReadBoardPosition` 的零值回退。
- 跨语言调用：地形仓库 `call("HasRoom")` / `call("GetRoomTerrainsOrEmpty")` / `call("CreateRoomLayout")`；棋盘控制器 `call("ClearAllCards")` / `call("SpawnTerrainCard", terrain, boardPosition)`；布局生成器 `load("res://core/map/room_terrain_layout_generator.gd")` + `call("Generate", profile)`；可重复采集刷新按“先旧 C# `RefreshIfReady`、后生产 `refresh_if_ready`”的顺序分支。
- 时间系统：继续按 Autoload 路径 `/root/TimeSystem` + `get("TotalTimePassed")` 读取，不依赖 C# 静态单例。
- 回滚点：`scenes/Main.tscn` 的 ext_resource 切回 `uid://dp2kl6obtjoh` / `res://core/map/RoomBoardPresenter.cs`，回退四个测试文件的断言；`core/map/room_board_presenter.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### 遗留边界

- 房间地形数量由 `room_terrain_layout_generator.gd` 的随机抽样决定（迁移说明已记录与旧 `System.Random` 的序列差异），因此同房间两次运行可能得到不同地形卡数量；这属于既有随机行为，不是本批引入的偏差，验证时应比对“规则一致”而不是“数量相同”。
- `HideHarvestedTerrain` 过滤发生在刷新之后，与旧 C# 顺序一致（先把已就绪的可重复采集复位，再决定是否隐藏），不能把两步调换。

## WorldInteractionCoordinator 生产切换边界（2026-09-20 21:17）

这一批的性质是「主场景最后一个 C# 场景脚本 + 四个仅本脚本可见的纯 C# 普通类」。盘点结论决定边界形态：`WorldCombatScenePresenter` / `ScreenTransitionAdapter` / `WorldViewVisibilityController` / `TerrainInteractionExecutor` 都不继承 `GodotObject`，GDScript 无法 `load()`、`new()` 或按类型引用它们，因此本批只能「同名协议内联复刻」，而不是「复用 + 降级」。

### 兼容边界

- 生产脚本：`core/gameflow/world_interaction_coordinator.gd`（uid `uid://b1wldintrct9k`，`extends Node`、不声明 `class_name`），逐行等价旧 `core/gameflow/WorldInteractionCoordinator.cs`（551 行）；旧 C# 文件与四个辅助类全部完整保留为兼容垫片。
- 序列化面逐字保持：9 个 `@export`（`BoardControllerPath` / `GameplayPortPath` / `BackpackFlyTargetPath` / `EncounterManagerPath` / `HoldInteractionControllerPath = "WorldHoldInteractionController"` / `WorldRootPath = "../.."` / `MapSystemPath = "../../MapSystem"` / `MapCanvasLayerPath = "../../MapSystem/CanvasLayer"` / `HudLayerPath = "../../UI/HUDLayer"`）。`ScreenTransitionsPath` 在旧 C# 里本来就不是 `[Export]`，GDScript 侧保持普通 `var`（`^"/root/ScreenTransitions"`），序列化面零变化。
- 信号面逐字保持：`PassageGuardEncounterFinished(is_victory: bool)`、`WorldHoldCompleted(owner: Node)`；稳定信号名常量保留 `EncounterRequested` / `TimeChanged` / `CardClicked` / `CardPressed` / `CardReleased` / `CardSpawned`，另加战斗侧 `battle_ended`。
- 公开协议方法名逐字保持（GDScript 侧 PascalCase）：`RequestPassageGuardEncounter(monsters: Array)`、`ScaleEncounterMonsters(terrain: Variant, monsters: Array) -> Array`、`BeginWorldHoldForMap(owner, action_point_cost, progress_target)`、`CancelWorldHoldFor(...)`。参数类型必须放宽为非泛型 `Array`：GDScript 调用方（`passage_guard_controller.gd`）传的就是非泛型数组，声明成 `Array[Resource]` 会直接运行时报错。
- 内联复刻一：战斗场景过场（等价 `WorldCombatScenePresenter`）。`[WorldCombatScenePresenter] Entering Combat!` → `fade_out` → 实例化 `res://scenes/battle_scenes/battle.tscn` → 按需写入 `starting_deck_data` / `starting_monster_data` → 用 `current_map_background_resolver.gd::DuplicateCurrentBackground` 复制背景 → 连接 `battle_ended` → 挂到 `WorldRootPath` → 隐藏世界视图 → `fade_in`。`_is_transitioning` 语义与旧 `try/finally` 等价（唯一前置守卫放在函数开头，协程内不再中途 return）。
- 内联复刻二：战斗结果等待。旧 `TaskCompletionSource<bool>` 用 `_battle_result_ready` / `_battle_result` + `await get_tree().process_frame` 轮询表达；进入战斗前必须清空标记，避免上一次 fire-and-forget 战斗的结果被本场消费。过渡中拒绝新战斗时 `RequestPassageGuardEncounter` **同步**发出 `false`，保持旧 C# 的同步语义（`passage_guard_controller.gd` 依赖这一点）。
- 内联复刻三：过场适配（等价 `ScreenTransitionAdapter`）。`await node.signal` 对静态类型 `Node` 不可用，改为「先 `connect(&"fade_complete", on_completed, CONNECT_ONE_SHOT)`，再 `call("fade_out")`，最后轮询 `process_frame`」；连接必须先于发起，否则同帧完成的动画会永久挂起。
- 内联复刻四：世界视图显隐（等价 `WorldViewVisibilityController`）。四个路径（棋盘 `CanvasItem`、地图 `CanvasItem`、地图 `CanvasLayer`、HUD `CanvasLayer`）同时切换 `visible`；路径缺失时用 `get_node(path) as T` 的零值跳过，保持「不抛异常但日志可见」的迁移期行为。
- 内联复刻五：地形交互执行（等价 `TerrainInteractionExecutor` + 9 个 `TerrainOp`）。GDScript 侧只走 `build_ops` 协议（生产地形交互资源全部是 GDScript），把 9 种操作描述映射为运行时端口调用：`pass_time` / `spawn_loot` / `mark_harvested` / `check_gathering_encounter` / `record_reusable_gathering` / `enter_vault` / `open_farming_panel` / `spawn_monster` / `remove_source_card`。日志前缀逐字保持（`[TerrainInteractionExecutor] Click terrain:`、`Build GDScript ops from`、`GDScript ops count =`、`[PassTimeOp] Pass time`、`Checking gathering encounter for tag:`）。
- 跨语言数据边界：`terrain.get("TerrainData")`、`terrain_data.get("InteractionBehavior")`、`terrain_data.get("CardName")`、`interaction.get("TimeCost")`、`_gameplay_port.get("Player")`、`player.get("Equipment")`、`_time_system.get("TotalTimePassed")`；掉落数组按 `Item` / `Amount` / `IsEmpty` 过滤，等价旧 `ItemStackProtocol.TryRead`。
- 可重复采集双语言分支：`interaction is ReusableGatheringInteraction` → `call("GetEffectiveTimeCost" | "CanHarvest")`；生产 GDScript → `call("get_effective_time_cost" | "can_harvest")`；判定入口同时接受 `has_method("get_effective_time_cost")`。
- 回滚点：`scenes/Main.tscn` 的 ext_resource（id `7_nxtc6`）切回 `uid://bvmf7jb6rrxk7` / `res://core/gameflow/WorldInteractionCoordinator.cs`，回退 7 个测试文件的断言；`core/gameflow/world_interaction_coordinator.gd` 与 uid 旁车可整体删除。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### 遗留边界

- 旧 C# `TerrainInteraction.BuildOps`（C# 强类型操作序列）在 GDScript 侧无法表达：需要 C# 构建上下文与 `TerrainOp` 实例。生产地形交互资源已全部是 GDScript（`res/terrain/*.tres`、`resources/map/terrain/*.tres` 均引用 `gathering_interaction.gd` / `reusable_gathering_interaction.gd`），因此该路径由保留的 C# 执行器独占；GDScript 侧只保留同文本的硬失败提示作为明确边界。
- 旧 C# `TerrainInstance` 的公开属性不是 Godot 属性，GDScript 只能写「字段存在的地形实例」。生产地形实例是 `terrain_instance.gd`（由 `room_terrain_store.gd` 创建），所以 `mark_harvested` 在生产路径等价；但若将来有 C# 生产者创建地形实例，`IsHarvested` 的写入会退化为跳过，需在最终清理审计中复查。
- 战斗背景复制依赖 `MapInstantiator.current_scene` 或首个带 `Background` 的子节点；未进入任何房间时返回 null（与旧 C# 一致，本批冒烟即为此情形）。
- `_fade_out` / `_fade_in` 若过场 Autoload 不发出完成信号会永久挂起（与旧 C# `await ToSignal` 一致），这是既有契约而不是本批引入的风险；`ScreenTransitions.gd` 的 `fade_out` / `fade_in` 均已确认会发出对应信号。

## 状态数据族收口边界（2026-09-20 21:24）

### 兼容边界

- 生产脚本：`core/combat/status/attribute_change_guard_status_data.gd`、`core/combat/buffs/boss_damage_cap_status_data.gd`、`core/combat/buffs/hit_count_modifier_status_data.gd`、`core/combat/buffs/next_attack_damage_bonus_status_data.gd`、`core/combat/buffs/vulnerable_status_data.gd`；均 `extends "res://core/combat/status/status_effect_data.gd"`、不声明 `class_name`，各带 `const INSTANCE_SCRIPT_PATH` 与 `func CreateInstance(source: Node, owner: Node) -> RefCounted`。至此 10 个状态数据子类全部有 GDScript 生产实现。
- 序列化面逐字保持：`TargetAttribute` / `Direction` / `CancelChange` / `DeltaMultiplier` / `EnableMinValue` / `MinValue` / `EnableMaxValue` / `MaxValue`（拦截）、`MaxHealthDamageRatio`（Boss 上限，默认 0.10）、`FlatHitCountBonusPerStack` / `AttackSkillUses`（段数修正，默认 0 / 0）、`FlatSegmentDamageBonusPerStack` / `AttackSkillUses`（每段伤害修正，默认 0 / 1）、`TargetDamageType` / `DamageMultiplier`（脆弱，默认 0 / 1.5）。枚举一律以旧 C# 的整数取值导出（`AttributeChangeDirection.Any = 0`、`DamageType.Physical = 0`、`AttributeType.PhysAtk = 0`），与既有 `attribute_change_trigger_status_data.gd` 的处理一致。
- 实例侧仍是 C#：`AttributeChangeGuardStatusInstance` / `BossDamageCapStatusInstance` / `HitCountModifierStatusInstance` / `NextAttackDamageBonusStatusInstance` / `VulnerableStatusInstance` 的构造参数与 `_data` 字段由强类型降级为通用 `Resource`，字段读取统一走 `StatusEffectDataProtocol`。这是「数据在 GDScript、实例在 C#」这一族形态的必然结果——GDScript 无法继承 C# 的 `StatusEffectInstance`，因此实例族要到单独一批才能整体迁移。
- 协议面：`StatusEffectDataProtocol` 新增 `ReadBool(Resource, string)`（数据为空或字段缺失返回 false），加上既有 `ReadId` / `ReadText` / `ReadInt` / `ReadFloat` / `ReadTexture` / `ReadArray` / `HasFiniteDuration` / `ReadStackPolicy` / `ReadExpirePolicy` / `ReadTickTiming`，已覆盖全部 10 个数据子类的字段类型。
- 读取时机保持「实时」：`AttackSkillUses` / `FlatHitCountBonusPerStack` / `FlatSegmentDamageBonusPerStack` 在 C# 侧实现为只读属性，每次访问都经由协议读取资源，等价旧 C# 直接访问 `_data.X` 的行为；仅构造时的初始剩余次数在字段初始化器里用主构造参数 `data` 读取一次（C# 字段初始化器不能引用其它实例字段）。
- 回滚点：删除 5 个新 `.gd`（与 uid 旁车），把 5 个 C# 实例的构造参数与 `_data` 还原为强类型数据类、字段读取还原为直接属性访问，并回退本批测试断言。5 组数据类当前无 `.tres` 引用，因此没有资产回滚项。旧 `.csproj`、`.sln`、C# Autoload 全部保留。

### 遗留边界

- 这 5 组状态数据当前没有任何资产引用（全项目 `.tres`/`.tscn` 扫描为 0），本批只把数据侧生产实现补齐、把实例侧降到字段协议；等对应内容资产出现时可直接引用 `.gd` 数据脚本，无需再改动实例。
- `VulnerableStatusInstance` 的 `_data` 在旧 C# 中即未被读取（增伤硬编码物理 ×1.5，`TargetDamageType` / `DamageMultiplier` 两个导出字段不参与运行），本批逐字保持该现状，不做行为修正。
- `tests/godot/multi_hit_damage_tests.gd` 仍 `load()` 旧 C# 数据类作为对照基线，属允许保留的旧语言测试引用。
- 编辑器在 C# 程序集重载后仍会对只有带参构造的状态实例报 `MissingMemberException: does not define a parameterless constructor`（`AttributeModifierStatusInstance` / `ShieldStatusInstance` / `BurnStatusInstance` / `AttributeChangeTriggerStatusInstance`，共 4 个类）；这是 `_update_exports` 的编辑器侧噪声，游戏运行时与 `test_run` 计数均不受影响。

## 状态实例族生产切换边界（2026-09-20 21:45）

### 兼容边界

- 生产脚本 12 个，全部不声明 `class_name`、无 BOM、LF：基类 `core/combat/status/status_effect_instance.gd`（`extends RefCounted`，60 函数，逐字对照旧 `StatusEffectInstance.cs` 374 行）＋ 9 个实例子类（`attribute_modifier` / `burn` / `shield` / `boss_damage_cap` / `hit_count_modifier` / `next_attack_damage_bonus` / `vulnerable` / `attribute_change_guard` / `attribute_change_trigger`）＋ 2 个跨语言 DTO 载体（`status_change_context.gd` / `status_changed_event.gd`）。
- Hook 形态必须换手：旧 C# `void OnX(DamagePayload payload, ref float damage)` 的 `ref` 在 GDScript 不存在，本批统一改成 `func OnX(payload, damage) -> float` 的返回值语义，并在基类提供非 ref 包装 `ApplyX(payload, damage)`；状态组件一律调用 `ApplyX`，因此 C# 垫片实例与 GDScript 生产实例在同一套调用协议下行为一致。
- 数据 → 实例路由切换：9 个数据 `.gd` 的 `INSTANCE_SCRIPT_PATH` 全部指向新 `.gd` 实例；旧 C# 数据垫片的 `CreateInstance` 仍创建 C# 实例，作为回滚路径与 C# 测试工程基线保留。
- 载荷表现记录协议：`DamagePayload.cs` 新增 `RecordShieldAbsorption(float, bool)` 与 `RecordDamageCap(float)`。原因是 `DamageResolutionTrace` 是纯 CLR 类（非 `GodotObject`），GDScript 既不能读也不能写；把这两条写入收敛到载荷自身的方法协议后，护盾吸收与单次扣血上限的表现数据才能跨语言落到同一追踪对象上。
- 消费方协议：`attribute_component.gd` 走 `GetAttributeModifiersData()`；C# `AttributeComponent.cs` 保留「C# 强类型快路径 + GDScript 字段协议回退」；C# `StatusComponent.cs` / `StatusChangeContext.cs` 保持强类型不变，因为本工作区没有任何场景挂载这个 C# 组件（`player.tscn` / `monster.tscn` 都指向 `status_component.gd`），它只服务 C# 测试工程与回滚路径；跨语言入口始终是 `status_component.gd` + 字段/方法协议。
- 序列化面零变化：本批不改任何 `.tres` / `.tscn` 的字段值，只把 9 个数据 `.gd` 的实例脚本路径常量改指向 `.gd`。
- 回滚点：把 9 个数据 `.gd` 的 `INSTANCE_SCRIPT_PATH` 切回 `.cs`、`status_component.gd` 的 `STATUS_CHANGE_CONTEXT_SCRIPT_PATH` / `STATUS_CHANGED_EVENT_SCRIPT_PATH` 切回 `.cs`、删除 12 个新 `.gd`（含 uid 旁车），再回退本批测试断言与 `DamagePayload` 的 `Record*` 方法。

### 遗留边界

- C# 实例族（基类 + 10 个实例类）全部保留完整实现，仍是 C# 测试工程与回滚路径的实现；未删除任何 `.cs` / `.csproj` / `.sln` / C# Autoload。
- GDScript 实例不声明 `class_name`，跨语言判定只能靠脚本路径或字段/方法协议，不能按类型引用。
- 叠加策略整数逐字沿用旧 C#（`ResetDuration=0` / `AddDuration=1` / `AddStackOnly=2`）：`MaxStacks=1` 的状态重复施加仍只刷新持续时间、不涨层。
- 编辑器在 C# 程序集重载后仍会对带参构造的状态实例报 `MissingMemberException: does not define a parameterless constructor`（`_update_exports` 噪声，本批未新增，运行时与 `test_run` 计数不受影响）。

## 伤害结算结果族生产切换边界（2026-09-20 22:05）

### 兼容边界

- 生产脚本 `core/combat/damage_resolution_result.gd`（`extends RefCounted`、不声明 `class_name`），逐字等价 `DamageResolutionResult.cs`：同样的 6 个构造参数（`payload, preGuardDamage, actualDamage, isEvaded, isCritical, isLethal`）、同样的 16 个字段名、同样的 `GetFeedbackInt` / `GetFeedbackBool` / `GetFeedbackNode` 协议，以及同样的钳制与兜底（`PreGuardDamage` / `ActualDamage` 取 `max(0)`、`HitIndex` 取 `max(0)`、`HitCount` 取 `max(1)`、空载荷时 `DamageType.Physical=0` / `ElementType.None=0`）。
- 追踪对象不可跨语言：`DamageResolutionTrace` 是纯 CLR 类，`DamagePayload.ResolutionTrace` 是 C# 属性，GDScript 既读不到也写不到。因此在 C# `DamagePayload` 上补 3 个只读转发属性 `ShieldAbsorbedDamage` / `ShieldWasBroken` / `CappedDamage`，GDScript 结算结果按字段协议读取；追踪对象仍是唯一权威来源，写入路径（`RecordShieldAbsorption` / `RecordDamageCap`）不变。
- 消费方：`entities/components/damage_receiver_component.gd` 的 `RESULT_SCRIPT_PATH` 切到 `.gd`，构造参数顺序保持；表现层 `combat_feedback_director.gd` 本就优先走 `GetFeedback*` 方法协议，因此零改动即可同时读两种实现。
- 旧 `DamageResolutionResult.cs` 完整保留：C# 测试工程（`tests/CUSGA.Tests/Program.cs`）与 C# 垫片继续按旧类型消费；本批不改任何 `.tres` / `.tscn`。
- 回滚点：`damage_receiver_component.gd` 的 `RESULT_SCRIPT_PATH` 切回 `.cs`，删除新 `.gd` 与 uid 旁车，回退 `DamagePayload` 的 3 个转发属性与 `test_damage_receiver_contract.gd` 的断言。

### 遗留边界

- `DamagePayload` 仍在 C#：它的消费方（`StatusEffectInstance` 家族钩子、`DamageEffect.cs`）签名是强类型 `DamagePayload`，因此载荷本体要与技能执行上下文一起作为后续批次处理，不能单独切。
- 改完 C# 必须 `dotnet build` 再跑 GodotAI：本批第一次聚焦测试 `ShieldAbsorbedDamage` 读回 0，就是编辑器仍用旧程序集；`dotnet build` 之后同一用例通过。程序集刷新是 GodotAI 侧验证的前置条件。

## 技能执行上下文族生产切换边界（2026-09-20 21:55）

## 伤害载荷本体生产切换边界（2026-09-20 22:20）

## 技能目标选择族生产切换边界（2026-09-20 22:35）

### 兼容边界

- 生产脚本：`core/combat/effects/skill_effect_target_selection.gd`（`Unit` / `Role` / `IsSource` + getter 形式 `IsPrimary` / `IsSecondary` + 静态 `FromSource` / `FromTarget`）、`core/combat/effects/skill_effect_target_scope_utility.gd`（静态 `SelectTargets` / `SelectNodes` + `SCOPE_*` + `_scope_matches`）、三个枚举载体（`skill_effect_target_scope.gd` / `damage_hit_target_mode.gd` / `core/combat/skills/skill_target_role.gd`）。
- 枚举载体遵循既有约定：`extends RefCounted` + `enum`、不声明 `class_name`、取值顺序与 C# 枚举逐字一致（顺序即序列化契约）。
- 惰性枚举 → 数组：旧 C# 工具类返回 `IEnumerable`，GDScript 返回一次性数组；本项目调用方都是立即遍历，语义等价。若将来出现「只取前 N 个」的 C# 调用方，必须重新核对。
- 单一规则源：`card_effect.gd` 的 `_select_scope_targets` 委托 GDScript 工具类，私有 `_scope_matches` 已删除；对外仍是 `Array[Dictionary]`（`Unit` / `Role` / `IsSource` / `IsPrimary` / `IsSecondary`），`damage_effect.gd` 等消费方零改动。
- 旧 C# 五个类型（工具类、选择结构体、三个枚举）完整保留：C# 效果实现（`ApplyShieldCardEffect.cs` / `ApplyStatusCardEffect.cs` / `ModifyAttributeEffect.cs` / `DamageEffect.cs`）与 C# 测试工程继续按旧类型消费。
- 回滚点：删除 5 个新 `.gd` 与 uid 旁车、恢复 `card_effect.gd` 自带的 `_scope_matches`、回退 `test_combat_skill_contract.gd` 的新增用例。

### 遗留边界

- 跨语言的目标条目有两个形态：C# `SkillTarget`（`Unit` / `Role` / `IsPrimary` / `IsSecondary`）与 GDScript `skill_target.gd`；工具类与效果脚本都只用字段协议判定，因此两种条目可以混用，但任何新判定都必须写进工具类，不得在效果脚本里复制。
- 枚举整数值散落在 `.tres` 的反序列化路径上：最终审计需要逐项核对资源里的枚举整数与两个语言的枚举定义一致。

### 兼容边界

- 生产脚本 `core/combat/damage_payload.gd`（`extends RefCounted`、不声明 `class_name`）：字段 `Source` / `Target` / `Type` / `Damage` / `Element` / `DamageModifiers` / `IsExtraDamage` / `HitIndex` / `HitCount` / `TargetRoleId` 与旧 C# 逐字一致，默认值同样为 `DEFAULT_COMBAT=15` / `1` / `0`；位标记与枚举常量（`MODIFIER_*` / `DAMAGE_TYPE_*` / `ELEMENT_*`）同名同值。
- 纯 CLR 内部对象降级为载荷字段：旧 C# 把护盾吸收与扣血上限记在 `DamageResolutionTrace`（非 Godot 类型，GDScript 读写不到），GDScript 版直接存在载荷自身字段上，对外仍只暴露方法协议 `RecordShieldAbsorption` / `RecordDamageCap` 与只读属性 `ShieldAbsorbedDamage` / `ShieldWasBroken` / `CappedDamage`。
- 记录语义逐字等价：四舍五入 + 非负钳制；吸收量规整后 ≤ 0 时整条记录被忽略（不累加、也不更新击破标记）；击破标记只做或运算；上限削减量无条件累加。
- 消费方切换（3 个 GDScript 构造点）：`core/combat/effects/damage_effect.gd`、`core/combat/buffs/burn_status_instance.gd` 的 `PAYLOAD_SCRIPT_PATH`，`scripts/battle_scripts/battle_manager.gd` 的 `DAMAGE_PAYLOAD_SCRIPT_PATH`。
- 旧 `DamagePayload.cs`（含 `DamageResolutionTrace` / `DamageModifierFlags` / `DamageType`）完整保留：C# 测试工程（`tests/CUSGA.Tests/Program.cs`）与 C# 状态 Hook（`StatusComponent.cs` 的 `ApplyModify*`、`ShieldStatusInstance.cs`、`BossDamageCapStatusInstance.cs`）继续按强类型消费。
- 回滚点：三个路径常量切回 `.cs`，删除 `core/combat/damage_payload.gd` 与 uid 旁车，回退 `tests/godot/test_damage_receiver_contract.gd` 的新增用例。

### 遗留边界

- `GetFeedbackInt` / `GetFeedbackBool` 的支持名单是硬契约（与旧 C# 逐字一致，不含 `CappedDamage`）：新消费方不得顺手扩展名单，否则表现层会读到旧实现永远不会给出的字段。
- 运行时 C#：本批后伤害管线不再创建 C# 对象，`project.godot` 的 autoload 全为 `.gd` / `.tscn`；资产侧只剩 Crafting 的 2 个 recipe `.tres` 挂 C# 资源脚本，属下一批对象。

### 兼容边界

- 生产脚本 5 个：`core/combat/skills/skill_target.gd`、`skill_execution_context.gd`、`skill_execution_modifier_context.gd`、`core/combat/effects/damage_effect_hit_count_context.gd`、`damage_effect_segment_context.gd`。全部 `extends RefCounted`、**不声明 `class_name`**，字段名 / 工厂名 / 方法名与旧 C# 逐字一致。
- **C# 静态方法不在 Godot 反射方法集合里**：旧 `load("...SkillExecutionContext.cs").FromSingleTarget(...)` 在 GDScript 侧报 `Nonexistent function`（`Self` / `FromPrimaryTargets` / `FromSpread` 同理）。这是本次必须迁移的直接原因——凡是「C# 侧需要被 GDScript 通过 `load(path).Method(...)` 调用」的静态入口，都必须迁到 GDScript。工厂现在挂在 GDScript 脚本资源上，调用点写法不变。
- 无 `class_name` 时的自举构造：静态函数内部不能对自身类型 `new()`，统一用 `load(SELF_PATH).new(source, targets, candidates)`；`SELF_PATH` / `TARGET_SCRIPT_PATH` 作为脚本内常量维护。
- 语义等价与唯一差异：`SkillExecutionContext.PrimaryTarget` 在旧 C# 里当 `Targets[0]` 为 null 时抛空引用，GDScript 版返回 `null`（更安全，正常路径行为不变，已在注释标注）。
- `SkillExecutionModifierContext` 的内部集合：旧 C# `HashSet<StringName>` → GDScript「去重数组 + 首次插入顺序」；`MarkStatusForConsumption("")` 忽略、同 Id 重复标记只保留一次；`GetStatusIdsMarkedForConsumptionSnapshot()` 返回 `.duplicate()` 副本，供跨语言读取且不可反向修改内部集合。
- 消费方切换（5 处脚本路径常量）：`scripts/battle_scripts/battle_manager.gd`、`scripts/card_scripts/skill_card.gd`、`core/combat/status/attribute_change_trigger_status_instance.gd` 用 `CONTEXT_SCRIPT_PATH`；`core/combat/skills/combat_skill_data.gd` 用 `MODIFIER_CONTEXT_SCRIPT_PATH`；`core/combat/effects/damage_effect.gd` 用 `HIT_COUNT_CONTEXT_SCRIPT_PATH` / `SEGMENT_CONTEXT_SCRIPT_PATH`。
- 旧 5 个 C# 上下文 / DTO 垫片完整保留：C# 状态实例（`HitCountModifierStatusInstance.cs`、`NextAttackDamageBonusStatusInstance.cs` 等）与 C# 测试工程继续按同一套字段 / 方法协议消费；GDScript 状态实例与 C# 状态实例都能读 GDScript 上下文，反之亦然。
- 回滚点：5 个路径常量切回 `.cs`，删除 5 个新 `.gd` 与 uid 旁车，回退 `tests/godot/test_combat_skill_contract.gd` 的新增用例。

### 遗留边界

- `DamagePayload` 仍在 C#，载荷本体与 `DamageResolutionTrace` 的归宿待下一批；本族与载荷共同构成伤害管线的跨语言边界，先切上下文后切载荷，避免一次改动同时改变两侧签名。
- 不带 `class_name` 的脚本不能被 `is` 类型判定：任何新消费方必须走脚本路径或字段 / 方法协议——这条对状态实例族与本族同时成立。

## 属性域类型族生产边界（2026-09-20 22:07）

### 兼容边界

- 生产脚本 7 个：`core/attributes/attributes.gd`（`AttributeType` 0..14）、`attribute_modifier.gd`（条目本体 + `AttributeModifierMode` 0..2）、`attribute_recalculate_scope.gd`、`attribute_change_direction.gd`、`attribute_change_reason.gd`、`attribute_recalculate_request.gd`、`i_read_only_attribute.gd`。全部 `extends RefCounted`、**不声明 `class_name`**，避免与仍在使用的 C# 全局类型重名。
- 旧 C# `AttributeModifier` 是 `readonly record struct`：GDScript 用 `RefCounted` + `_init(type, mode, value_per_stack, stacks, source_id)` 表达同一字段面，字段名必须与跨语言字典出口一致；`TotalValue()` 复用旧调用点 `ValuePerStack * Stacks` 的口径，`ToDictionary()` 字段与 `AttributeModifierDataProtocol.ToDictionary` 逐字一致。
- 旧 C# `RecalculateRequest` 的私有 `Action _mutation` 在 GDScript 侧用 `Callable`（默认 `null`）等价，`ApplyMutation()` 无 Callable 时是空操作；`Single` / `All` 的默认参数（`allowInterception=true` / `emitEvents=true`）与 `All` 的 `type=default(AttributeType)=0` 逐字保留。
- `IReadOnlyAttribute` 是 C# 接口，GDScript 没有接口语义：不造空实现，用 `REQUIRED_MEMBERS`（`Type` / `DisplayName` / `BaseValue` / `BonusValue` / `AllocatedPoints` / `GrowthPerPoint` / `RawValue`）描述协议面，契约测试同时核对旧 C# 接口与实际生产实现 `attribute_value.gd`。
- 消费方保持整数常量（`attribute_component.gd` 的 `ATTRIBUTE_*` / `MODIFIER_MODE_*` / `REASON_*` / `SCOPE_*`，`attribute_change_context.gd` 的 `DIRECTION_*`）：本批用契约测试逐值锁定「枚举 ↔ 常量」一致，不为纯类型载体改动大脚本。
- 旧 7 个 C# 类型完整保留：`AttributeComponent.cs`、`StatusEffectInstance.cs`、`AttributeModifierStatusInstance.cs` 与 C# 测试工程继续按强类型消费。
- 回滚点：删除 7 个新 `.gd` 与 uid 旁车，回退 `tests/godot/test_attribute_component_contract.gd` 新增的 5 个用例。

### 遗留边界

- 本族跨语言表面只有两条：字段字典（`Type` / `Mode` / `ValuePerStack` / `Stacks` / `SourceId`）与整数枚举；两侧不互相传递类型实例本身。
- `readonly record struct` 的值拷贝语义在 GDScript 侧变成引用语义：任何依赖「副本」的新调用方必须显式 `.duplicate()`。这是本族唯一允许存在的语义差异，已在脚本注释标注。
- 枚举整数值散落在 `.tres` 反序列化路径与存档里：最终审计需逐项核对资源 / 存档里的整数与两侧枚举定义一致。

## 地形操作族兼容边界（2026-09-20 22:10）

### 兼容边界

- 归类：`resources/interaction/operations/` 的 10 个 C# 类型（`TerrainOp` + 9 个操作类）是 **C#-only 兼容层**，运行期不可达。调用方只有 C# 地形交互链（`BossInteraction.cs` / `FarmingInteraction.cs` / `GatheringInteraction.cs` / `ReusableGatheringInteraction.cs` / `VaultInteraction.cs` 的 `BuildOps`）、`core/gameflow/TerrainInteractionExecutor.cs` 与 `tests/CUSGA.Tests/Program.cs`。
- GDScript 等价不是新的类族，而是内联执行：生产交互资源（`resources/interaction/*_interaction.gd`，由 `res/terrain/*.tres` 与 `scenes/map_scenes/**` 挂载）返回「操作描述 Dictionary」，`core/gameflow/world_interaction_coordinator.gd` 的 `_apply_gdscript_ops` 按 `type` 执行。
- 两侧唯一共享面是操作词汇：`pass_time` / `spawn_loot` / `mark_harvested` / `check_gathering_encounter` / `record_reusable_gathering` / `enter_vault` / `open_farming_panel` / `spawn_monster` / `remove_source_card`；未知类型两侧同文本硬失败。
- 桥接语义落在端口实现上：`RemoveSourceCardOp` → `context.Board.RemoveSourceCard()`，C# 端口实现为 `boardController.Call("RemoveCard", sourceCard)`，与 GDScript 的 `_board_controller.call("RemoveCard", card)` 同义。
- 契约测试：`tests/godot/test_world_interaction_coordinator_contract.gd::test_terrain_op_family_boundary`（词汇 ↔ 副作用逐条对照 + 资产零引用扫描）。

### 遗留边界

- 删除条件：该族必须与 C# 交互链（5 个交互资源 + `TerrainInteractionExecutor.cs` + C# 测试工程）**整链退役**，审计时不得只删操作类。
- 词汇表有第二份真实现（`world_interaction_coordinator.gd` 内联 match）：新增操作类型时，词汇表与契约测试必须同步更新，否则新操作会在运行期落到「未知类型」硬失败。

## 核心常量族生产边界（2026-09-20 22:15）

### 载体与真源

- 新增 GDScript 生产载体：`core/constants/combat_constants.gd`（`DAMAGE_FORMULA_CONSTANT = 100.0`）、`core/constants/element_type.gd`（`enum ElementType { None=0, Wood=1, Metal=2, Water=3, Earth=4, Fire=5 }`）、`core/constants/gd_signals.gd`（`OnPlayerAcquiredTalent` / `OnStatusChanged` / `OnEntityDropped` / `OnEnteredVault` / `OnEnteredRoom`，StringName）、`core/constants/tag_consts.gd`（7 个 StringName）、`core/constants/time_costs.gd`（`MapMove 10` / `EnterScene 5` / `ChopTree 20` / `PlantSeed 10`）。
- 全部 `extends RefCounted`、无 `class_name`，与 `core/constants/{equipment_types,weather_type,world_interaction_timing}.gd` 的既有约定一致；均带 uid 旁车。
- 载体是契约锚点，不替换既有消费方：`core/combat/damage_formula.gd`、`core/combat/damage_payload.gd`、`core/combat/elemental_system.gd`、`core/autoloads/GlobalEventBus.gd`、`core/autoloads/time_system.gd`、`scripts/map_scripts/map_instantiator.gd`、`core/ui/draggable/draggable_data.gd`、`entities/components/equipment_component.gd` 里的字面量本批一律不动。

### 兼容边界

- 旧 C#：`core/constants/{CombatConstants,ElementType,GDSignals,TagConsts,TimeCosts}.cs` 全部保留（兼容垫片 + C# 侧消费者仍在）。
- 跨语言唯一共享面是「值」本身：常数 100、枚举 0..5、5 个信号名字符串、7 个标签字符串、4 个时间成本整数；GDScript 信号名与 `GlobalEventBus.gd` 的 `signal` 声明逐字一致（`on_entered_room` 例外，声明在 `map_instantiator.gd`）。
- 有意不迁移：旧 C# `GDSignals.OnInventoryToggled`（源码中被注释掉）不在 GDScript 侧建立载体。
- 「暂无 GDScript 消费方」的常量：`WoodDamageUp` / `HealAfterAction` / `EnterScene` / `ChopTree` / `PlantSeed`；契约测试以负向断言锁定其只命中载体自身。
- 删除条件：C# 侧 5 个常量类与全部 C# 消费者（`ElementalSystem.cs` / `DamageFormula.cs` / `TimeSystem.cs` / `Player.cs` / `Monster.cs` / 各 `Component.cs` / `TalentManager.cs` / `tests/CUSGA.Tests/Program.cs`）整链退役后，方可清理。

### 契约测试

- `tests/godot/test_core_constants_contract.gd`（suite `core_constants_contract`，7 个用例）+ 根级 shim `tests/test_core_constants_contract.gd`（测试发现只扫 `res://tests/` 根目录）。
- 断言面：载体形状 → 消费方同值 → 无消费方负向断言 → 枚举文本形（注意最后一项无尾逗号，用 `"%s = %d"` 拼接而非 `"Fire = 5,"`）。

## 枚举族生产边界（2026-09-20 22:19）

### 载体与真源

- 新增 GDScript 载体 8 个（`extends RefCounted`、无 `class_name`）：`core/combat/status/status_change_reason.gd`、`stack_policy.gd`、`duration_tick_timing.gd`、`duration_expire_policy.gd`、`status_hook_phase.gd`、`core/crafting/crafting_failure_reason.gd`、`core/shop/shop_failure_reason.gd`、`core/progression/upgrade_kind.gd`。
- `SkillTargetingType` 的 GDScript 等价物是**代码生成产物**：`addons/skill_targeting_type_codegen`（5 秒轮询）从 `core/combat/skills/SkillTargetingType.cs` 生成 `scripts/generated/SkillTargetingType.gd`（`class_name SkillTargetingType`，`enum Value`）。手改生成物会被覆盖，改动必须落到 C# 枚举；消费者为 `scripts/card_scripts/card_manager.gd` 与 `scripts/battle_scripts/battle_manager.gd`（`SKILL_TARGETING_TYPE.Value.<成员>`）。
- 既有 GDScript 真源（本批不改）：`entities/components/status_component.gd`（`REASON_*` / `POLICY_*` / `TIMING_*` / `PHASE_*`）、`core/combat/status/status_effect_instance.gd`（`EXPIRE_POLICY_*`）、`core/crafting/crafting_service.gd` 与 `entities/components/crafting_component.gd`（内联 `enum CraftingFailureReason`）、`core/shop/shop_service.gd`（内联 `enum ShopFailureReason`）。
- 本批补齐的唯一缺口：`StatusChangeReason.Cleared = 6`（旧 GDScript 侧只有注释、没有常量）。

### 兼容边界

- 旧 C# 9 个枚举全部保留；成员顺序与取值不允许重排或删除，只允许追加。
- 「能力式边界」：`UpgradeKind` 不向 GDScript 暴露整数，能力由 `core/progression/player_progression.gd` 的具名方法（`GetWarehouseCapacity` / `TryUpgradeCarrySlots`）提供；载体当前无 GDScript 消费方，由负向断言锁定。
- 消费方自带的整数镜像不合并、不替换，一致性由契约测试运行时常量表比对维持。
- 删除条件：C# 侧 9 个枚举与全部 C# 消费者（战斗 / 合成 / 商店 / 进度脚本，以及 `PlayerProgression.cs` 的存档整数读取）整链退役后，方可清理。

### 契约测试

- `tests/godot/test_enum_family_contract.gd`（suite `enum_family_contract`，6 个用例 / 404 条断言）+ 根级 shim `tests/test_enum_family_contract.gd`。
- 关键实现约束：C# 枚举多为隐式取值，必须用测试内的小型解析器（支持隐式递增、显式赋值、行尾注释、`///` 文档行，并显式跳过开头的 `{`）比对「顺序 + 取值」，不能按 `成员 = 值` 字面量匹配。
- 统计口径：`SkillTargetingType.cs` 的孪生是 PascalCase 生成物，按 snake_case 匹配会漏计，审计时必须单独认。

## 协议 / 接口族生产边界（2026-09-20 22:23）

### 载体与真源

- 7 个旧 C# 协议类是 **C#-only 读取垫片**：它们不产生运行时对象，只是让未迁移的 C# 代码按稳定字段/脚本路径读取已迁移的 GDScript 生产对象。GDScript 等价物 = 被读取的生产脚本：
  - `CardEffectProtocol` → `core/combat/effects/{card_effect,damage_effect}.gd`（`Execute`）
  - `CombatSkillDataProtocol` → `core/combat/skills/combat_skill_data.gd`（`Element` / `TargetingType` / `Execute`）+ `resources/item/base_card_data.gd`（`CardId` / `CardName`）
  - `StatusEffectDataProtocol` → `core/combat/status/status_effect_data.gd`（12 个 `@export` 字段）
  - `MonsterDataProtocol` → `resources/monster/monster_data.gd`（`MonsterName` / `ElementalProperty` / `Faction` / `SkillSet` / `LootTable`）
  - `AttributeModifierDataProtocol` → `core/combat/status/attribute_modifier_data.gd`（`Type` / `Mode` / `ValuePerStack`）+ `core/attributes/attribute_modifier.gd::ToDictionary()`（`Type` / `Mode` / `ValuePerStack` / `Stacks` / `SourceId`）
  - `TerrainInstanceProtocol` → `resources/interaction/terrain_instance.gd`（`LocalGridPos` / `BoardPosition` / `TerrainData` / `IsHarvested` / `GrowthStage` / `RemainingGatheringCount` / `RefreshReadyTotalTime`）
  - `ItemStackProtocol` → `resources/item/item_stack.gd`（`Item` / `Amount` / `IsEmpty` + `SetItem` / `Clear`）
- 4 个 C#-only 接口（GDScript 无法实现 C# 接口）的 GDScript 等价物是组件方法协议：`IDamageable` → `health_component.gd::TakeDamage`；`ICraftingInventory` → `inventory_component.gd` 的 `Slots` / `CanStore` / `CountWhere` / `AddItem` / `TryRemoveItems`；`IShopInventory` → 同文件的 `CanAddItem` / `AddItem` / `TryRemoveItem` / `ItemCnt`；`IPlayerWallet` → `core/autoloads/player_wallet.gd` 的 `Gold` / `TrySpend` / `Add`。

### 兼容边界

- 唯一共享面是「脚本路径 / 字段名 / 方法名」；字段改名会同时破坏 C# 垫片、GDScript 消费者与 `.tres` 反序列化。
- 生产 GDScript 对 11 个标识符零裸依赖、对 11 个 `.cs` 路径零加载（4 个生产根目录全扫）；生产脚本中的名字只出现在说明等价关系的 `##` 文档注释里。
- **AttributeModifierData 类型表前提：已满足** —— `ProjectSettings.get_global_class_list()` = 160 个全局类且含 `AttributeModifierData`；探针 API 必须用 `ProjectSettings.get_global_class_list()`，`ClassDB.class_exists()` 对 C# 全局类返回 false，会误判为「未刷新」。
- 删除条件：C# 侧 7 个协议类与 4 个接口的全部 C# 消费者（战斗 / 地形执行器 / 商店 / 合成 / 进度脚本 + `tests/CUSGA.Tests/Program.cs`）整链退役后，方可清理。

### 契约测试

- `tests/godot/test_protocol_family_contract.gd`（suite `protocol_family_contract`，4 个用例 / 231 条断言）+ 根级 shim。
- 关键实现约束：负向扫描必须去掉注释与字符串字面量后再匹配裸标识符（逐字符扫描器），否则 `## 等价旧 C# XxxProtocol` 这类文档注释会被误判成依赖；另需单独断言「生产 `.gd` 不得出现这些 `.cs` 路径」。

## C# 地形交互链生产边界（2026-09-20 22:31）

### 范围

- 8 个 C# 文件：`resources/interaction/{TerrainInteraction,TerrainInteractionBuildContext,WorldInteractionContext,WorldInteractionPorts}.cs` + `core/gameflow/{TerrainInteractionExecutor,ScreenTransitionAdapter,WorldCombatScenePresenter,WorldViewVisibilityController}.cs`。
- 与 10 个 `resources/interaction/operations/*Op.cs` 同链：C# 半幅 = 「读 GDScript 交互资源产出的 ops 并执行」的兼容层。

### GDScript 生产等价物

- 5 个交互资源：`@export var TimeCost: int = 20` + `build_ops(player, terrain, effective_time_cost_override := null) -> Array[Dictionary]`（`farming_` / `vault_` / `gathering_` / `boss_` / `reusable_gathering_interaction.gd`）。
- `core/gameflow/world_interaction_coordinator.gd`：`_execute_terrain_interaction` / `_apply_gdscript_ops` / `_fade_out` / `_fade_in` / `_run_screen_transition` / `_enter_combat` / `_enter_combat_and_wait_for_result` / `_on_battle_ended` / `_create_battle_instance` / `_duplicate_current_background` / `_set_world_view_visible`，日志标签与 C# 同文本。

### 兼容边界

- 过场：`ScreenTransitionAdapter.RunAsync("fade_out", "fade_complete")` ↔ `_run_screen_transition("fade_out", "fade_complete")`；`/root/ScreenTransitions` 只暴露小写 `fade_out` / `fade_in` + 信号 `fade_complete` / `fade_in_complete`。`HasMethod` 为假时 C# 静默 return，属「静默 no-op 边界」，必须锁方法名字符串。
- 资产（`.tscn` / `.tres` / `.res`）对 8 个链名零命中；生产逻辑本批零改动。
- 删除条件：8 个 C# 文件 + 10 个 `*Op` 操作类 + `tests/CUSGA.Tests/Program.cs` 整链一起退役。
- 本批修复的真实缺陷：两处 stale `.uid` 旁车（`world_interaction_coordinator.gd.uid`、`room_board_presenter.gd.uid`），权威值只能来自 `ResourceLoader.get_resource_uid()`。

### 契约测试

- `tests/godot/test_gameflow_chain_contract.gd`（suite `gameflow_chain_contract`，4 个用例 / 204 条断言）+ 根级 shim。
- 关键实现约束：断言 GDScript 源码片段时若 `print` 参数跨行，只能匹配字符串字面量本身（例如 `"[TerrainInteractionExecutor] Build GDScript ops from %s"`），不要匹配跨行的完整调用。

## C# 剩余逻辑族生产边界（2026-09-20 22:33）

### 范围

- 5 个逻辑型 C# 类型：`core/progression/UpgradeService`、`core/progression/PlayerDataPolicy`、`resources/encounters/MonsterStatMultiplier`、`core/application/EncounterMonsterScaler`、`core/map/PassageGuardEdge`。
- `entities/components/ComponentLookup` 的三段回退已由 `test_status_component_contract.gd` 覆盖，本批不重复断言。

### GDScript 生产等价物（改名并存，不是新代码）

| 旧 C# | GDScript 生产实现 |
| --- | --- |
| `UpgradeService` | `core/progression/player_progression.gd`：`WarehouseBaseValue 27` / `WarehouseValuePerLevel 9` / `WarehouseMaxLevel 3` / `CarryBaseValue 5` / `CarryValuePerLevel 1` / `CarryMaxLevel 5`，费用表 `[300,600,1000]`、`[200,350,550,800,1100]`，`_clamp_level` / `_get_value` / `_is_max_level` / `_get_cost` |
| `PlayerDataPolicy` | `player_wallet.gd` 与 `player_progression.gd` 各自 `const PersistAcrossRuns: bool = false` + 跳过分支 |
| `MonsterStatMultiplier` | `encounter_manager.gd` 的 `MULTIPLIER_FIELDS` 与 `_identity_multiplier()`；地形浮动倍率走 `terrain_instance.gd::GetEncounterVarianceSnapshot()` |
| `EncounterMonsterScaler` | `encounter_manager.gd` 的 `_build_day_multiplier` / `_scale_monsters` / `_scale_monster` / `_scale_stats`（30 字段）/ `_scale_float` |
| `PassageGuardEdge` | `core/map/passage_guard_state.gd` 的 `_edge_key` / `_compare_points`（先比 X 再比 Y） |

### 兼容边界与已知缺口

- **`StartingStats` 是最后一个跨语言硬依赖**：`encounter_manager.gd::_scale_stats` 仍写 `var scaled: StartingStats = StartingStats.new()`，即运行时构造旧 C# `StartingStats`。`resources/stats/starting_stats.gd` 已有 30 个同名字段（无 `class_name`，标识符仍解析到 C# 全局类）。StartingStats 批次完成前不得删除 `resources/stats/StartingStats.cs`。
- 能力式边界：`UpgradeService.GetRemainingTotalCost` 无任何调用方（含 C# 测试工程），GDScript 侧不新增同名入口；最终清理前需复核。
- 数值真源：升级常量 / 费用表在 C# 与 GDScript 各一份，默认值表另有 `StartingStats.cs` 第三份；由 `test_logic_family_contract` 的三方比对维持一致。
- 回滚点：删除测试与根级 shim 即可，生产代码与资产本批零改动。

### 契约测试

- `tests/godot/test_logic_family_contract.gd`（suite `logic_family_contract`，7 个用例 / 207 条断言）+ 根级 shim。
- 可复用模式：`_csharp_const_int` / `_csharp_int_array` / `_csharp_property_order` / `_csharp_export_defaults` / `_read_stat_defaults(text, marker)`（C# 与 GDScript 共用同一解析器，只是 marker 不同）+ `_strip_gd_comments` + `_scan`。
- 运行时必备：`tests/test_*.gd` 根级 shim 缺失会让 `test_run(suite=...)` 报 `No suite named ... is registered`。

## StartingStats 生产边界（2026-09-20 22:37）

### 范围与结论

- 旧 C# `resources/stats/StartingStats.cs`（`[GlobalClass] partial : Resource`，30 个 `[Export] float`）保留为兼容垫片。
- 资产侧早已迁移：53 个怪物 `.tres` 的 `CSV_StartingStats` / `Resource_stats` 子资源均指向 `res://resources/stats/starting_stats.gd`。
- 生产侧唯一残留依赖是 `core/application/encounter_manager.gd::_scale_stats` 的 `StartingStats.new()`（裸标识符 → 旧 C# 全局类），本批切换为 GDScript 实现。

### 改动

- `encounter_manager.gd` 新增 `const STARTING_STATS_SCRIPT: GDScript = preload("res://resources/stats/starting_stats.gd")`。
- `_scale_stats`：`var scaled: StartingStats = StartingStats.new()` → `var scaled: Resource = STARTING_STATS_SCRIPT.new()`；30 个字段写入与缩放公式不变。

### 兼容边界

- 跨语言协议 = 「`Resource` 基类 + 30 个同名字段 + 同默认值」。C# 与 GDScript 两侧改字段名或默认值会同时破坏 `.tres` 反序列化与缩放结果。
- C# 侧无任何 `StartingStats` 强转：`MonsterData.InitialAttributes` / `AttributeComponent.InitialData` / `DebugLoadoutData.PlayerStartingStats` 都是 `Resource`；`Monster.cs` 走 `MonsterDataProtocol.ReadResourceField`。
- `starting_stats.gd` 不得声明 `class_name`（会遮蔽 C# 全局类并打断未迁移的 C# 消费者）。
- 回滚点：还原 `_scale_stats` 两行并删常量；测试与 shim 可整批删除。

### 契约测试

- `tests/godot/test_starting_stats_contract.gd`（suite `starting_stats_contract`，6 个用例 / 203 条断言）+ 根级 shim。
- 关键实现约束：
  - 「零命中」扫描必须自证有产出（例如 `_scan(dir, "", ["tres"])` 后断言 `files.size() > 40`）。
  - `String.find("")` 返回 `-1`，空 needle 的「匹配全部」必须显式写成 `needle == "" or text.find(needle) != -1`。
  - 词边界扫描用 `RegEx` 的 `(?<![A-Za-z0-9_])标识符(?![A-Za-z0-9_])`，否则 `PlayerStartingStats` 会被误判成 `StartingStats` 依赖。

## Crafting 旧配方资产跨语言强转修复边界（2026-09-20 22:45）

### 问题与根因

- 生产侧早已全量切到 GDScript（`player.tscn` 用 `crafting_component.gd` + `crafting_recipe.gd` + `recipe_book_data.gd`，`Main.tscn` / `crafting_ui.tscn` 用 `crafting_ui.gd`），但 `resources/recipe/res/{torch_recipe,stone_axe_recipe}.tres` 仍以 `CraftingRecipe.cs` / `CraftingIngredient.cs` 作为 Script 引用——这是**全项目唯一的资产级 C# 脚本依赖**。
- 旧 C# 垫片的导出字段是强类型：`[Export] public ItemData OutputItem`、`[Export] public ItemData RequiredItem`、`[Export] public Array<CraftingIngredient> Inputs`。而它们引用的物品资产（`torch.tres` / `axe.tres` / `branch.tres` / `charcoal.tres` / `stone.tres`）早已切到 `resource_card_data.gd`（GDScript `item_data.gd` 的子类）。
- 结果：加载旧配方资产时托管层抛 `System.InvalidCastException: Unable to cast object of type 'Godot.Resource' to type 'CUSGA.resources.item.ItemData'`，被 Godot 记录后**静默丢弃该字段**——`OutputItem` 与 `RequiredItem` 变回 `null`，即「原序列化字段值丢失」。这是跨语言边界破损，不是渲染或玩法问题。

### 修复决策

- 采用「资产脚本身份升级」而不是「放宽 C# 垫片类型」：两个旧路径资产切换到 `crafting_recipe.gd` / `crafting_ingredient.gd`，文件路径、文件 UID（`uid://mq7g5ojandul` / `uid://ch4rxtqw0tc74`）、`RecipeName`、`Inputs` 顺序与 `Amount`、`OutputItem`、`OutputAmount` 默认值全部不变；`Array[ExtResource(...)]` 类型化数组降级为 `Array[Resource]`，与 GDScript 出口一致；C# 专用的 `metadata/_custom_type_script` 提示一并移除。
- 理由：① 迁移终态本来就不允许资产绑定 C# 脚本，这一步是必经的；② C# 强类型链（`ICraftingInventory` / `VirtualInventory` / `ItemStack.Item` 全是 `ItemData`）一旦放宽出口类型就要连带改 4 个 C# 文件，而本轮验证边界限制为 GodotAI MCP（无 C# 编译验证手段），改动无法自证，风险高于收益；③ C# 配方类没有任何资产级消费者——`tests/CUSGA.Tests/Program.cs` 用 `RuntimeHelpers.GetUninitializedObject` 在内存里构造配方，不读 `.tres`。
- C# 类本身（`CraftingRecipe.cs` / `CraftingIngredient.cs` / `RecipeBookData.cs` / `CraftingComponent.cs` / `CraftingService.cs` / `CraftingUI.cs`）原样保留为兼容垫片，未删除任何 `.cs` / `.csproj` / `.sln` / C# Autoload。

### 兼容边界与回滚

- 跨语言协议 = 「`Resource` 基类 + `RecipeName`/`Inputs`/`OutputItem`/`OutputAmount` 同名字段 + 同默认值」；两侧脚本都不得声明与被迁移物品资源冲突的强类型导出。
- 回滚点：把两个 `.tres` 的 Script 引用与数组类型还原为 C# 版本即可（会重新引入强转丢值问题，仅用于紧急回退）。

### 契约测试

- `tests/godot/test_crafting_recipe_contract.gd`（suite `crafting_recipe_contract`，3 个用例 / 60 条断言）+ 根级 shim。
- 关键断言：C# 垫片导出字段名/顺序/默认值与 GDScript 孪生脚本逐个一致（3 组字段契约）；旧路径资产与 `*_recipe_gd.tres` 的配方快照逐条相等，且**两侧脚本都必须是 GDScript**、`OutputItem` 与每个 `RequiredItem` 都必须非空（直接锁死本批的丢值回归）；生产场景/资产/GDScript 对 crafting 的 6 个 `.cs` 路径零引用（`LEGACY_ASSET_ALLOWLIST` 现为空，扫描另配「已知资产引用必须被扫出」的自证断言）。

## 物品链与商店链跨语言边界（2026-09-20 22:53）

### 范围与结论

- 物品数据家族（`ItemData` / `BaseCardData` / `ResourceCardData` / `SkillCardData` / `ToolData` / `EquipmentData` / `EquipmentSetData` / `SetBonusTier`）、`ItemStack` 与商店链（`ShopCatalog` / `ShopFailureReason` / `ShopService` / `ShopTradeBridge` / `IPlayerWallet` / `IShopInventory`）在生产侧**早已全量 GDScript**：`player.tscn`、`Main.tscn`、`Shop.tscn` 与全部物品资产只绑定 `.gd`，19 个物品链 `.cs` 在资产与场景里零引用。
- 本批因此不做资产切换，只做两件事：① 解除 `entities/components/battle_deck_component.gd::_can_store_item` 对「脚本是 `SkillCardData.cs`」的语言绑定（改为 `Skill` 字段协议）；② 把字段契约、容器弱化位置与「禁止出现的强类型容器」钉成契约测试。

### 字段契约表（C# 垫片 ↔ GDScript 生产，导出顺序与默认值必须一致）

| 家族 | C# 垫片 | GDScript 生产 | 导出字段（原顺序） |
| --- | --- | --- | --- |
| `ItemData` | `resources/item/ItemData.cs` | `resources/item/item_data.gd` | MaxStackSize=99, ItemTags, BuyPrice=0, SellPrice=0 |
| `BaseCardData` | `resources/item/BaseCardData.cs` | `resources/item/base_card_data.gd` | CardId, CardName, CardIcon, Description |
| `ResourceCardData` | `resources/item/card/ResourceCardData.cs` | `resources/item/card/resource_card_data.gd` | 无新增字段（继承 `BaseCardData`） |
| `SkillCardData` | `resources/item/card/SkillCardData.cs` | `resources/item/card/skill_card_data.gd` | Skill, cost=10, CardTags |
| `ToolData` | `resources/item/tool/ToolData.cs` | `resources/item/tool/tool_data.gd` | TargetGatheringTag, YieldGrowth=0, GatheringTimeReduction=0 |
| `EquipmentData` | `resources/item/equipment/EquipmentData.cs` | `resources/item/equipment/equipment_data.gd` | ValidSlots, SetType=0, AttributeBonuses, GrantedTags |
| `EquipmentSetData` | `resources/item/equipment/EquipmentSetData.cs` | `resources/item/equipment/equipment_set_data.gd` | SetType=0, Tiers |
| `SetBonusTier` | `resources/item/equipment/SetBonusTier.cs` | `resources/item/equipment/set_bonus_tier.gd` | RequiredPieces=0, AttributeBonuses, GrantedTags |
| `ShopCatalog` | `core/shop/ShopCatalog.cs` | `resources/shop/shop_catalog.gd` | Goods, AlsoIncludeEveryPricedItem=false, DefaultBuyPrice=100 |

### 容器弱化登记（唯一允许的 C# 强类型 → GDScript 通用类型）

| C# 强类型出口 | GDScript 出口 |
| --- | --- |
| `EquipmentData.ValidSlots : Array<EquipmentSlot>` | `Array[int]` |
| `EquipmentData.AttributeBonuses : Dictionary<AttributeType, Vector2I>` | `Dictionary` |
| `EquipmentSetData.Tiers : Array<SetBonusTier>` | `Array[Resource]` |
| `SetBonusTier.AttributeBonuses : Dictionary<AttributeType, float>` | `Dictionary` |
| `ShopCatalog.Goods : Godot.Collections.Array<ItemData>` | `Array[Resource]` |

- 这 5 处是**唯一**允许出现的弱化；其余位置一旦出现 `Array[ItemData]` / `Array<ItemData>` / `Dictionary[AttributeType` 等强类型容器，就会在反序列化或赋值阶段拒收另一侧资源（`FORBIDDEN_GD_TYPES` 13 条），套件逐文件断言这些字符串在 13 个物品链生产脚本里零命中。
- 物品链的 GDScript 脚本**不得声明 `class_name`**（会遮蔽 C# 全局类型并打断未迁移的 C# 消费者），与 `starting_stats.gd` 同一策略。

### 商店失败原因三方同值（0..6）

| 成员 | 值 |
| --- | --- |
| `None` | 0 |
| `InvalidItem` | 1 |
| `InvalidQuantity` | 2 |
| `NotEnoughGold` | 3 |
| `NotEnoughSpace` | 4 |
| `MissingItem` | 5 |
| `NotConfigured` | 6 |

- 三方 = C# `ShopFailureReason` 枚举 + `scripts/shop/shop_control.gd` 的具名镜像常量（`FAILURE_NONE`..`FAILURE_NOT_CONFIGURED`）+ `core/shop/shop_failure_reason.gd`。具名常量刻意不用裸数字，避免后续有人在两处之间插入枚举成员时静默错位。

### 出战卡组判定：从「脚本路径」改为「字段协议」

- 旧实现：`_can_store_item` 先看资源脚本路径是不是 `SkillCardData.cs`，所以物品资产切到 GDScript 之后，**GDScript 技能卡反而进不了卡组**，而旧 C# 技能卡能进。这是迁移过程中的临时补丁留下的语言绑定。
- 新实现：只扫 `get_property_list()` 里有没有 `Skill` 属性——旧 C# `SkillCardData`（`[Export] public Resource Skill`）与 GDScript `skill_card_data.gd`（`@export var Skill: Resource`）都满足，非卡物品不满足。行为与「卡牌=有技能字段」的原语义一致。
- 运行时实测：`gd_card_ok=true`、`legacy_card_ok=true`、`plain_item_ok=false`、`deck_cards=4`。

### 契约测试

- `tests/godot/test_item_chain_boundary_contract.gd`（suite `item_chain_boundary_contract`，9 个用例 / 573 条断言）+ 根级 shim。
- 关键实现约束（可复用）：一次 `DirAccess` 遍历 `_collect_files()` 收文件、再单趟扫描（4 个根目录 × 19 条旧路径的双循环会把套件拉到 12.4s，单趟扫描后 0.7s）；「零命中」断言必须配 `files.size() > 200` 的自证；`String.find("")` 返回 `-1`，空 needle 必须显式判空。

### 回滚点

- 还原 `_can_store_item` 的 C# 脚本路径分支，并删除本套件与根级 shim。本批其余生产代码、资产、场景零改动。

## 生产 GDScript 语言绑定清理：能力协议 vs 字段协议（2026-09-20 23:40）

### 问题模式

- 「跨语言兼容分支」有两种形态：一种是**接受双方**（本批三处），一种是**只认一侧**（物品链的 `_can_store_item` 曾只认 GDScript，早期 `_can_store_item` 只认 C#）。只认一侧会直接丢功能；接受双方看似无害，但它把「语言身份」写进了生产逻辑——新增同协议资源被静默丢弃，垫片退役后分支又静默失效。
- 判定手段的**选择顺序**（本批实测得出）：
  1. **方法协议**（`Object.has_method`）：跨语言最稳，C# 与 GDScript 的方法都进方法表。
  2. **字段取值类型探测**（`typeof(obj.get("Field")) == TYPE_*`）：适用于 C# 属性**没有 `[Export]`** 的情况（此时属性表为空，但按名 `get()` 有效）。
  3. **属性表扫描**（`get_property_list()`）：只适用于两侧字段都可见的情形（C# 侧需 `[Export]`，如 `SkillCardData.Skill`）。
  4. **脚本路径 / 类型名判定**：迁移期禁用，语言身份耦合，禁止进入生产代码。

### 本批边界

| 位置 | 旧判定 | 新判定 | 判定类型 |
| --- | --- | --- | --- |
| `entities/monster.gd::_is_combat_skill_data` | 脚本路径 ∈ {`combat_skill_data.gd`, `CombatSkillData.cs`} | `resource.has_method("Execute") and has_method("RequiresTarget")` | 方法协议 |
| `core/ui/slot_ui.gd::_is_draggable_data` | 脚本路径 ∈ {`draggable_data.gd`, `DraggableData.cs`} | `typeof(obj.get("SourceSystem")) == TYPE_STRING_NAME` | 字段取值类型 |
| `core/ui/equipment_slot_ui.gd::_is_draggable_data` | 同上 | 同上 | 字段取值类型 |

### 实测事实（探针：编辑器进程 + 游戏进程各一次）

- 战斗技能：GDScript `combat_skill_data.gd` = `[Execute: true, RequiresTarget: true]`；C# `CombatSkillData` = `[true, true]`；GDScript 物品技能卡 = `[false, false]`；C# `SkillCardData` = `[false, false]`。→ 方法协议有足够区分度，不会把物品卡当怪物技能。
- 拖拽载荷：C# `DraggableData` 的 `get_property_list()` 只有 `["RefCounted", "script", "DraggableData"]`（属性未 `[Export]`），但 `get("SourceSystem")` 返回 `StringName`（`&"SystemInventory"`）；GDScript 载荷的属性表完整且同样返回 `StringName`；普通 `RefCounted` 返回 `null`（`TYPE_NIL`）。→ 只能用取值类型探测。
- 真实数据面：53 个怪物资产 / 231 条技能条目在新判定下 **231/231 通过、0 拒绝**，且技能脚本 100% 为 GDScript 生产实现。

### 契约测试

- `tests/godot/test_production_language_binding_contract.gd`（suite `production_language_binding_contract`，4 个用例 / 29 条断言）+ 根级 shim。
- 用例：① 生产 `.gd` 去注释后 `.cs` 字面量零命中（配「扫描器必须在 tests 目录扫出已知引用」的自证 + 生产文件数 > 150 的自证）；② 三处判定源码必须使用协议字面量、且不得出现 `resource_path`；③ 战斗技能四类对象矩阵；④ 拖拽载荷四类对象矩阵（含真实 GDScript 载荷）。
- `tests/godot/test_monster_contract.gd::test_skill_protocol_contract` 同步改为能力协议断言，并新增反向断言「生产脚本不得再出现 `resource_path`」。

### 回滚点

- 还原三处判定的脚本路径分支（会重新把语言身份写回生产逻辑），并删除本套件与 shim；生产资产、场景、数值、序列化字段本批零改动。

---

## MonsterData 判定语言中立化（2026-09-21 00:05）

### 判定手段优先级（沿用上批结论并补第 3 档）

| 优先级 | 手段 | 成立条件 | 本批用法 |
| --- | --- | --- | --- |
| 1 | 方法协议 | 对侧成员一定进方法表 | 战斗技能（上批） |
| 2 | 字段取值类型 | 属性未 `[Export]` 但按名 `get()` 可用 | 拖拽载荷（上批） |
| 3 | 属性表字段面 | 属性带 `[Export]` / `@export`，两侧都进属性表 | **MonsterData（本批）** |
| 4 | 脚本路径 / 类型名 | 迁移期禁用 | 生产代码已清零 |

### 本批边界

| 位置 | 旧判定 | 新判定 |
| --- | --- | --- |
| `core/application/encounter_manager.gd::_is_monster_data` | 脚本路径 ∈ {`monster_data.gd`, `MonsterData.cs`} | 属性表同时含 `MonsterName` + `ElementalProperty` + `SkillSet` |
| `core/application/gameplay_port.gd::_is_monster_data` | 同上 | 同上 |
| `core/gameflow/world_interaction_coordinator.gd::_is_monster_data` | 同上 | 同上 |
| `resources/encounters/gathering_encounter_result.gd::_is_monster_data` | 同上 | 同上 |
| `core/application/encounter_manager.gd::_new_monster_like` | 末段回退 `MonsterData.new()` | 末段回退 `MONSTER_DATA_SCRIPT.new()`（`preload("res://resources/monster/monster_data.gd")`） |

### 实测事实（run 71 / run 72，游戏进程与编辑器进程一致）

- 两侧怪物数据的属性表都含 `MonsterName / ElementalProperty / SkillSet / InitialAttributes`；`ItemData`、`SkillCardData`、`StartingStats`、`CombatSkillData` 的属性表都不含前三个字段 → 字段面具备区分度。
- 本批刻意只取前三个字段：`InitialAttributes` 在旧 C# 侧默认可能为 `null`，纳入协议会让判定依赖数据填充状态，属行为放大的风险点。
- 回退构造的实际优先级：源脚本可实例化 → 源脚本 → 浅拷贝 → 生产 GDScript 怪物数据（run 71 验证末段返回 `res://resources/monster/monster_data.gd` 实例）。
- 真实数据面：`res://resources/monster` 下 **53/53** `.tres` 被新判定接受，脚本计数 `monster_data.gd = 53`、`MonsterData.cs = 0`。

### 契约测试

- `tests/godot/test_production_language_binding_contract.gd::test_monster_data_protocol_is_field_based`（20 条断言）：4 个消费方源码协议断言 + 5 类对象矩阵 + 全量怪物资产扫描（自带「资产数 > 40」自证，防止空扫描通过）。
- `tests/godot/test_monster_data_contract.gd`：覆盖 4 个消费方，并禁止 `is MonsterData` / `as MonsterData` / `Array[MonsterData]`。

### 回滚点

- 还原 4 处判定的路径常量分支与 `MonsterData.new()` 构造，删除新增用例；资产、场景、数值、序列化字段零改动。


## 批 K（2026-09-21 00:27–00:41）：C# 物理退役与退役期收口

### 决策

- **退役动作本身不是迁移动作**：物理删除的前提是「所有 C# 都有等价 GDScript 实现」已由全量测试 + 端到端流程分别证明，因此删除时不再改动任何生产逻辑；删除后出现的红灯一律按「断言过期」或「编辑器回写漂移」处理。
- **回写漂移要按迁移前形态收敛，而不是按漂移改断言**。`scenes/Main.tscn` 上 `Player` / `InventoryUI` / `CraftingUI` / `WarehouseUI` 四个实例节点的 `script` / `custom_minimum_size` / `SlotPrefab` / `EquipmentSlotPrefab` 覆盖是编辑器会话回写的产物：取值与四个实例场景自身根节点逐字相同（已逐一比对 `scenes/player_scenes/player.tscn`、`scenes/inventory/inventory_ui.tscn`、`scenes/crafting/crafting_ui.tscn`、`scenes/Warehouse/warehouse_ui.tscn`），且 `git show HEAD:scenes/Main.tscn` 里这些覆盖与 `14_v0vrg` 等 `ext_resource` 并不存在。结论：删除覆盖 = 恢复迁移前节点结构，比改断言更忠于「语言迁移不改结构」。
- **语言判定边界在 C# 退役后必须归零**。`gameplay_port.gd::_is_csharp_script_instance()` 是唯一保留的跨语言判定（旧强类型信号 vs 通用 Node 信号双路分发）。C# 组件全部退场后该分支不可达，删除它不改变任何运行时行为（GDScript 组件本来就走 `*Node*` 信号）。四个强类型旧信号仍保留声明与 UI 双向连接，避免改动信号 API 面。
- **测试侧的 C# 对照保留为惰性输入**：`csharp_optional.gd` 的守卫与 39 个套件里的 `.cs` 常量不删，因为它们是「两侧行为逐字一致」的历史证据；C# 缺席时整体 `skip` 并给出统一原因，而不是产生解析期错误或「空源文假通过」。
- **判定 C# 类型名的扫描必须覆盖 `.new()`**：只用「`: 类型` / `-> 类型` / `is 类型`」做正则时，`var x := MonsterData.new()` 这类写法会漏网（`new` 前有 `.`）。本批的收口扫描因此把 `X.new()` 与 `as X` 一并纳入判据。

### 契约测试

- `test_final_migration_audit_contract.gd::test_no_language_boundary_remains`：生产四根目录内「语言判定谓词」与「按脚本扩展名判定语言」双谓词 0 命中，并附测试目录阳性自证（同一扫描逻辑必须在 `res://tests` 扫出已知命中）。
- `test_attribute_component_contract.gd::test_main_scene_drops_legacy_player_override`：主场景不得含旧玩家脚本的 `ext_resource id`，且必须仍 `instance=ExtResource("8_jlsqs")` —— 本批按「删漂移」而非「改断言」通过。
- 退役期双模态：`test_classified_csharp_files_follow_phase_contract` 在无 `CUSGA.csproj` 时要求 39 个 `.cs` 清零 + 工程文件已删。
- 测试助手修复：`csharp_optional.gd::read()` 先判存在，缺失文件不再让 `FileAccess.get_file_as_string` 往编辑器日志推 `Cannot open file` / `Failed loading resource`。

### 回滚点

- 隔离区 `%TEMP%\cusga-csharp-quarantine-20260921-0030\`（306 个文件）保留全部 `.cs` / `.cs.uid` / `.csproj` / `.sln` / `.godot/mono/` / `tests/CUSGA.Tests/` 的原相对路径；退役前 `project.godot` 备份在 `%TEMP%\cusga-cs-untracked-20260921-0027\project.godot.before-retirement`。回滚 = 移回文件 + 恢复 `[dotnet]` 段 + 还原 4 处 `Request*` 双路分发与审计断言。
