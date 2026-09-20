# 执行计划

## 阶段 0：分析与基线

- 记录项目自有 C# 数量、分层、场景挂载和 `.tres` 引用。
- 保存 `project.godot`、主场景和现有长按测试的基线状态。

## 阶段 1：局外长按模块

1. 新建 GDScript 圆环指示器，保持导出字段、绘制几何和目标锚点行为。
2. 新建 GDScript 长按控制器，保持默认路径、Tween、取消和完成回调行为。
3. 将主场景脚本资源切换到 GDScript。
4. 将 C# 协调器对子控制器的依赖降为稳定的 `Node` 动态调用，避免编译期继续依赖已迁移类型。
5. 更新 Godot 测试的脚本路径和 GDScript API 名称。
6. 通过 `script_manage` 读取新脚本、`test_run` 运行局部长按测试、`scene_open`/`project_run` 做主场景冒烟检查。

## 阶段 2 及以后

- 迁移常量/枚举和纯逻辑，更新所有调用者。
- 迁移 Resource 基类与资产，逐个更新 `.tres` / `.res` 脚本引用并验证 Inspector 字段。
- 迁移实体组件、UI、系统和 Autoload。
- 全局清理旧 C# 引用，确认项目不再需要 Mono 后再删除 `.csproj`、`.sln` 和 C# 特性。

### EquipmentComponent 并行实现

1. 通过稳定堆叠协议和 `equipment_data_compat.gd` 实现槽位判断、装备、卸下、交换和最佳槽位选择。
2. 保留属性、标签、套装阶级、采集产量/时间和夜晚火把倍率结算。
3. 用并行 GDScript ItemStack/Inventory、旧 C# ToolData 资产和轻量 Attribute/Tag 假对象覆盖聚焦契约。
4. 只在聚焦测试、完整相关套件和主场景冒烟均通过后记录并行实现完成；不得在本批切换玩家场景或 C# UI。

### DraggableData 并行实现

1. 以等价 PascalCase 字段实现无规则的 GDScript 拖拽载荷，并用 `Node` / `RefCounted` 保留新旧语言对象引用。
2. 在库存组件契约套件中验证默认值、装备槽整数值和库存、装备、堆叠对象身份。
3. `SlotUI.cs` 与 `EquipmentSlotUI.cs` 仍使用 C# 类型；迁移顺序先处理 `ItemTooltipPresenter`，再处理 `EquipmentSlotUI`，最后才允许评估 `InventoryUI` 和生产场景切换。

### ItemTooltipPresenter 并行实现

1. 用单一 `Show(Variant)` 接受旧 C# / 新 GDScript ItemStack 或直接 ItemData，保留 `Hide` 和共享空 Presenter 语义。
2. 复用 `item_data_compat.gd`，保持 DisplayName → CardName 与空描述 → `暂无描述` 的原文案规则，并继续调用既有 TooltipPanel 方法。
3. 用 GodotAI 契约同时覆盖 C# ItemData + ItemStack、GDScript ItemData + ItemStack、空堆叠、空值和空 Presenter；生产 C# UI 不在本批切换。

### EquipmentSlotUI 并行实现

1. 保留原场景的 ItemIcon、AmountLabel、SlotLabel 路径和 16 个槽位文案，使用新 ItemTooltipPresenter 与 ItemData 兼容桥刷新展示。
2. 使用新 DraggableData 生成装备来源载荷，同时识别旧 C# 载荷；所有放置合法性和实际操作继续委托 EquipmentComponent。
3. 聚焦测试覆盖图标、数量信号、悬停提示、预览参数、拖拽载荷、库存装备和装备槽移动；生产 `EquipmentSlotUI.tscn` 在 InventoryUI 迁移前保持 C# 脚本。

### SlotUI 并行实现

1. 保留原场景的 ItemIcon / AmountLabel、等宽尺寸、绑定公开属性、提示框与拖拽预览。
2. 固定 ShiftClick=0、AltClick=1 并以 Callable 转发快捷输入；所有库存移动和装备卸下继续委托现有组件方法。
3. 聚焦测试覆盖视觉信号、尺寸、快捷键、载荷、新旧拖拽类型、库存互移和装备卸下；生产 `SlotUI.tscn` 在 InventoryUI / WarehouseUI 迁移前保持 C# 脚本。

### WarehouseUI 并行实现

1. 保留三个 PascalCase 导出字段、两组生产节点路径、关闭按钮样式和 `WarehouseRequested` 打开流程。
2. 动态接受旧 C# / 新 GDScript 库存组件，切换绑定时解除旧 `InventoryChanged`，容量不变时只重绑并复用槽位节点。
3. GodotAI 聚焦测试使用生产场景子树和最小槽位协议验证请求、双库存容量、引用绑定、节点复用、提示框、关闭与信号清理。
4. 生产 `warehouse_ui.tscn` 继续使用 C#；先迁移 InventoryUI，再统一评估 WarehouseUI、SlotUI 和 EquipmentSlotUI 的生产切换。

### InventoryUI 并行实现

1. 保留四个 PascalCase 导出字段、生产节点路径、InventoryToggleRequested 开关、三组槽位和属性摘要绑定。
2. 动态接受旧 C# / 新 GDScript Inventory、BattleDeck 和 Equipment 组件；组件变化后统一重绑，容量不变时复用现有槽位节点。
3. 保持 Shift 单堆叠、Alt 批量技能卡和“先关闭背包再请求合成”的原行为，并在退出场景时解除 GameplayPort、按钮及三组件信号。
4. GodotAI 聚焦测试覆盖请求开关、三组绑定、节点复用、快捷移动、合成请求和信号清理；生产场景继续使用 C#，等待共享 UI 与玩家组件边界统一切换。

### HUD 背包与合成输入桥

1. 将 HUDController 和 BackpackButton 等价迁移为 GDScript，保留两个导出 NodePath、输入阶段、echo 过滤与请求/handled 时序。
2. 只把 Main 场景的两个叶子脚本引用切到 GDScript，GameplayPort、InventoryUI 与 CraftingUI 继续沿现有稳定方法边界运行。
3. 在库存契约套件中覆盖合成快捷键、背包快捷键、echo 抑制、handled 时序和按钮点击转发。
4. 通过 GodotAI 验证脚本符号、聚焦/相关回归、Main 场景加载与三条真实输入路径，再扫描旧路径和 UTF-8。

### AttributeSummaryUI 并行实现

1. 以固定 AttributeType 整数协议实现五项摘要、八项详情、弹窗和旧格式化规则，公开 Bind 接受现有 C# 或未来 GDScript 属性组件。
2. 保持 AttributeChanged 与 AvailablePointsChanged 两个刷新信号，重绑前解除旧连接，退出场景时同时清理按钮和属性信号。
3. 独立 GodotAI 契约覆盖空绑定、全部数值格式、信号刷新、重复/切换绑定、详情弹窗与退出清理。
4. 生产 `AttributeSummaryUI.tscn` 继续使用 C#，等待 InventoryUI 强类型边界解除后再统一切换。

### HealthBarUI 生产迁移

1. 等价迁移生命条视图，保留 `GameplayPortPath`、两个唯一节点路径、初始刷新、变化信号刷新与文本格式。
2. 只把 Main 场景的 HealthBarUI 脚本引用切到 GDScript，通过稳定属性与信号继续读取现有 C# GameplayPort / HealthComponent。
3. 独立 GodotAI 契约覆盖初始快照、变化刷新、重复/切换绑定和退出清理；相关库存、ItemStack 与可重复采集套件继续回归。
4. 用 GodotAI 确认 Main 实际加载新脚本、保留原 NodePath 并显示生产生命值，再检查增量日志、旧路径与 UTF-8；本批不迁移生命公式或战斗。

### TimePanelUI 生产迁移

1. 等价迁移时间面板视图，保留四个唯一节点路径、三种文本格式、进度条范围和 TimeChanged 五参数协议。
2. 继续读取现有 C# TimeSystem Autoload；初始刷新以兼容常量 100 对应旧静态 PhaseLength，后续刷新使用信号携带的阶段长度。
3. 只把 Main 场景的 TimePanelUI 脚本引用切到 GDScript，独立 GodotAI 契约覆盖初始快照、昼夜变化、动态阶段长度和退出清理。
4. 用 GodotAI 验证脚本符号、聚焦/相关回归、Main 真实界面与日志，再扫描旧路径和 UTF-8；本批不迁移 TimeSystem 或任何时间规则。

### LootTable 并行实现

1. 以 `Array[Resource] Drops` 接受新旧 LootDrop，保持概率、数量范围、yieldGrowth 和非正结果过滤规则。
2. 复用并行 GDScript ItemStack 创建掉落结果，保持原物品 Resource 引用身份；不在 LootTable 内迁移库存、事件总线或怪物逻辑。
3. 在 reusable_gathering 套件增加聚焦契约，覆盖默认数组、必定掉落、固定数量、产量修正、空条目、空物品、未命中和非正数量。
4. 生产 LootComponent 等强类型消费者迁移前不切换 62 个资产；通过 GodotAI 聚焦/相关回归、Main 冒烟、旧路径和 UTF-8 检查后只记录并行实现完成。

### LootComponent 并行实现

1. 保留 `DropTable` 和 `TriggerDrop` 协议，通过动态 Resource 方法同时接受 C# / GDScript LootTable。
2. 保持 `/root/GlobalEventBus`、`on_entity_dropped` 信号名及位置/堆叠参数顺序，不在组件内复制掉落或库存规则。
3. 独立 GodotAI 契约覆盖空表短路、yieldGrowth 转发、单次广播、位置、数组长度和堆叠身份。
4. `Monster.cs` 强类型依赖解除前不切换怪物场景；完成聚焦/相关回归、Main 冒烟、旧路径和 UTF-8 检查后记录并行实现。

### FactionComponent 生产迁移

1. 用单一导出整数保存阵营，并用显式 Inspector 枚举提示锁定 Hostile=0、PlayerSummon=1、Neutral=2。
2. 将 Monster 对组件的字段/节点获取降为 Node，通过稳定 `Faction` 属性写入 MonsterData 的同值整数；不修改其他怪物或战斗逻辑。
3. 切换 `monster.tscn` 的脚本与 metadata UID，独立 GodotAI 契约验证三个枚举值。
4. 用 GodotAI 打开并运行怪物场景，确认 C# Monster 实际获取 GDScript 子组件，再执行相关回归、日志、旧路径与 UTF-8 检查。

### LootComponent 生产切换

1. 在并行组件契约通过后，把 Monster 私有 Loot 字段降为 Node，并以 `Call("TriggerDrop", ...)` 保持死亡回调位置与参数。
2. 只切换 `monster.tscn` 的 LootComponent 脚本和 metadata UID，保留原 DropTable 空值，不修改 MonsterData 初始化或掉落内容。
3. 强制重载怪物场景，确认生产节点使用 GDScript；直接运行场景并调用空表路径，验证 C# Monster / GDScript 子组件边界。
4. 复跑聚焦与掉落资源套件，检查编辑器/游戏日志、旧路径和 UTF-8；既有 MonsterData 到组件的未绑定风险只记录不修复。

### TagComponent 并行实现

1. 用 Dictionary 保存 StringName 到正整数层数，等价实现增加、移除、存在性与层数查询四个公开方法。
2. 锁定空标签过滤、重复叠层、逐层递减、归零删除与缺失查询，不把标签玩法规则搬入组件。
3. 独立 GodotAI 契约覆盖完整生命周期，并回归 Inventory / Equipment 与 PassageGuard 相关套件。
4. Player、EquipmentComponent、TagTalentEffect 和旧 C# Provider 强类型边界解除前不切换 player 场景；完成 Main 冒烟、旧路径和 UTF-8 检查后记录并行实现。

### TagComponent 生产切换

1. 将 Player、EquipmentComponent、TagTalentEffect 与保留的 C# PassageGuardProbabilityProvider 对标签组件的依赖降为 `Node` + 四个稳定 PascalCase 方法协议。
2. 把 `player.tscn` 的 TagComponent 脚本引用切到已验证的 GDScript，更新旧 PassageGuard 测试输入，但不删除旧 C# 组件。
3. 扩展 GodotAI 聚焦契约，覆盖生产场景脚本引用、C# Provider → GDScript 标签、缺少 `HasTag` 的安全退化，并在运行时验证装备和天赋的增减标签链。
4. 通过玩家场景与 Main 冒烟、Inventory / reusable_gathering 回归、增量日志、旧路径及 UTF-8 检查后收口；Vital、Crafting、Autoload 与 AttributeModifierData 不混入本批。

### DebugLoadout 生产迁移

1. 以通用 Resource 数组迁移 DebugLoadoutData，并保持固定堆叠与动态装备条目的全部 PascalCase 字段和默认值。
2. 固定物品和动态装备工厂继续输出保留的 C# ItemStack / ItemData 派生类型，明确本批不迁移物品链。
3. 用 Node 与稳定方法协议迁移 Seeder，保持属性初始化、装备清空、库存/卡组清空、填充、直接装备和 ApplyOnce 的原顺序。
4. 切换默认 `.tres` 与 Main 的四条生产脚本引用，保留旧 C# 文件作为兼容垫片和 C# 测试输入。
5. 用 GodotAI 聚焦契约和真实 Main 运行同时验证编辑器工具态与游戏态边界，再执行 Inventory、ItemStack、reusable_gathering 回归、日志、旧路径与 UTF-8 检查。

### AttributeSummaryUI 生产切换

1. 将 C# InventoryUI 对属性摘要视图的字段、节点获取和 Bind 调用降为 Node + 稳定方法名，不修改玩家属性组件或父面板行为。
2. 把 `AttributeSummaryUI.tscn` 根脚本切换到已验证的 GDScript，并扩展聚焦契约锁定生产引用。
3. 先运行 Main 刷新 C# 程序集，再用真实 InventoryUI 打开/关闭和属性绑定验证跨语言路径。
4. 复跑 AttributeSummaryUI 与 Inventory 契约，检查增量日志、旧路径和 UTF-8；AttributeModifierData 与属性数值不进入本批。

### 共享背包 UI 链生产切换

1. 为现有 C# EquipmentComponent 增加无 `out` 的只读堆叠查询桥，不改变装备、卸装、交换或结算逻辑。
2. 同批切换 InventoryUI、WarehouseUI、SlotUI 与 EquipmentSlotUI 的生产场景脚本，保留旧 C# 文件和跨语言 ItemStack / ItemData 边界。
3. 扩展 Inventory 聚焦契约，锁定四个生产场景的 GDScript 引用，并回归槽位视觉、快捷键、拖放和父面板绑定行为。
4. 在真实 Main 中分别打开背包与全局仓库，验证容量、16 个装备槽、脚本身份、对象身份、属性摘要、默认装备图标和关闭行为。
5. 通过 GodotAI 聚焦测试、增量日志、旧路径与 UTF-8 检查后收口；物品链、Crafting、Autoload、战斗和 AttributeModifierData 不进入本批。

### VaultInteraction 生产迁移

1. 新增只导出 `TimeCost` 的 GDScript Resource，并按旧顺序返回 `pass_time` 与 `enter_vault` 两个操作描述。
2. 在 TerrainInteractionExecutor 的既有 GDScript 描述映射中复用 `EnterVaultOp`，不复制 GameplayPort 或仓库规则。
3. 切换火山地图唯一密库子资源脚本，移除旧 C# metadata，同时保留旧 C# 类型和操作类作为兼容垫片。
4. 扩展 reusable_gathering 契约覆盖字段默认值、第三参数兼容、操作顺序与生产场景引用。
5. 在 Main 中生成真实密库棋盘卡并走完长按，验证时间增加 20、仓库双栏打开、关闭与测试卡清理，再检查日志、旧路径和 UTF-8。

### BossInteraction 生产迁移

1. 新增保留 `TimeCost` 与 `Monster` 的 GDScript Resource，并按旧顺序返回 `pass_time`、`spawn_monster` 与 `remove_source_card` 三个操作描述。
2. 在 TerrainInteractionExecutor 的既有 GDScript 描述映射中复用 `MonsterSpawnOpOp` 和 `RemoveSourceCardOp`，不把遭遇、战斗切换或棋盘操作搬入 Resource。
3. 切换 Boss 房间与雪原两个生产子资源脚本，移除旧 C# metadata，同时保留旧 C# 类型、MonsterData 与操作类作为兼容垫片。
4. 扩展 reusable_gathering 契约，覆盖字段、Monster 引用、第三参数兼容、操作顺序与两个生产地图引用。
5. 在 Main 中生成真实 Boss 卡并走完长按，验证时间增加 20、遭遇请求、源卡移除、战斗切换、怪物生成和初始抽牌，再检查日志、旧路径与 UTF-8。

### GatheringInteraction 生产迁移

1. 新增保留 `TimeCost`、`GatheringTag` 与通用 `DropTable` 的 GDScript Resource，继续调用原 C# LootTable 的 `RollLoot` 并保持对象身份。
2. 按旧顺序返回时间、采集标记、可选掉落、遭遇检查和源卡移除描述；在 TerrainInteractionExecutor 中把 `mark_harvested` 映射回既有 MarkHarvestedOp。
3. 切换 3 个直接地形卡、6 个群系 Profile 和沙漠地图共 10 个生产引用，并同步 `create_terrain_profiles.gd`，保留所有标签、掉落表和默认耗时。
4. 扩展 reusable_gathering 契约覆盖默认字段、额外产量、已采集分支、操作顺序、10 个生产资产和生成器路径。
5. 在 Main 中生成受控一次性采集卡并走完真实长按，验证时间、采集标记、源卡移除和 C# 执行器映射，再执行完整相关回归、日志、旧路径与 UTF-8 检查。

### FarmingInteraction 并行迁移

1. 新增只导出 `TimeCost` 的 GDScript Resource，按旧占用判断返回 `pass_time` 与可选 `open_farming_panel` 描述。
2. 在 TerrainInteractionExecutor 中把 `open_farming_panel` 映射回既有 OpenFarmingPanelOp，不修改 GameplayPort、TerrainInstance 或农场 UI。
3. 扩展 reusable_gathering 契约覆盖默认耗时、第三参数兼容、未占用/已占用分支与操作顺序；确认仓库没有生产 FarmingInteraction 资产引用。
4. 在 Main 中生成受控临时农场卡并走完真实长按，验证时间、FarmingPanelRequested 参数与源卡保留，再执行完整相关回归、日志、旧路径与 UTF-8 检查。

### TalentCard 生产迁移

1. 新增 GDScript 卡片视图，保留四个导出字段、Initialize、OnCardClicked、缩放轴心与悬浮动画参数。
2. 将 TalentManager 的卡片实例边界降为 Control，通过动态方法和 Godot 信号继续传递原 C# TalentData。
3. 切换 `talent_card.tscn` 生产脚本，并在库存契约套件中锁定场景引用、序列化节点、方法和信号协议。
4. 通过 GodotAI 验证 C# Manager 生成 GDScript 卡片、数据显示、暂停、悬浮、点击、隐藏与恢复运行，再检查日志、旧路径和 UTF-8。

### TalentManager 生产迁移

1. 新增 GDScript Manager，保留三个导出字段、随机洗牌、最多三张、空池短路、暂停显示和选择移除行为。
2. 通过稳定信号继续连接 C# TimeSystem 与 GlobalEventBus，并把同一个 C# TalentData Resource 传给卡片和 Player。
3. 切换 `talent_screen.tscn` 生产脚本，把空池声明收窄为 `Array[Resource]`，保留节点、预制体和 process_mode。
4. 增加生产场景契约，并用 GodotAI 验证四选三、暂停、一次广播、Resource 身份、4→3 移除、恢复运行与空池短路。

### TalentData 与 TalentEffect 兼容迁移

1. 新增 TalentData、TalentEffect、AttributeTalentEffect、TagTalentEffect 的等价 GDScript，保持全部序列化字段、枚举整数和 Apply 行为。
2. 将 Player 的天赋事件参数降为 Resource，通过 Effects 数组和 Apply 方法协议同时接受旧 C# 与新 GDScript 输入。
3. 在库存契约中锁定四个脚本的字段、数组、整数、StringName 与方法协议；因当前无生产天赋资产，不伪造场景引用。
4. 用 GodotAI 在真实 Main 中验证新数据 + 新标签效果、新数据 + 旧 C# 标签效果、旧 C# TalentData，以及属性效果参数，再检查日志、旧路径和 UTF-8。

### MonsterSkillPreview 与 MonsterSkillComponent 生产迁移

1. 新增预览 RefCounted 值对象和技能组件 GDScript，保留技能字段、预览说明回退、可见过滤、随机选择和 Resource 身份。
2. 将 `Monster.cs` 的技能组件字段与初始化/查询边界降为 Node 动态协议，并将查询结果转换回 `CombatSkillData`，不改战斗调用方签名。
3. 切换 `monster.tscn` 的技能组件脚本，保留旧 C# 文件、UID、技能集合和技能条目作为兼容输入；核对场景 ext_resource UID 与新 `.gd.uid` 一致。
4. 通过 GodotAI 聚焦契约、脚本符号解析、怪物场景直接运行和 Main helper 烟测，再执行 UTF-8、占位实现和旧 C# 路径扫描；战斗技能数据、效果链和 Autoload 不进入本批。

### CurrentMapBackgroundResolver 并行实现

1. 新增 Resolver GDScript，保留当前房间优先选择、背景复制、名称和层级属性。
2. 在 PassageGuard/reusable_gathering 聚焦测试中直接构造 GDScript 实例，验证背景选择与非背景节点隔离。
3. 保留 C# Presenter 的静态调用；若 Main/战斗 helper 未 live，立即停止生产切换并记录程序集/缓存阻塞。
4. 收口前执行脚本符号解析、单用例 GodotAI 测试、旧路径扫描和 UTF-8 检查；不把 Resolver 并行实现写成战斗生产迁移完成。

### Crafting 数据 Resource 并行迁移

1. 新增三个无 `class_name` 的 GDScript Resource，避免在 C# 全局类型表刷新前引入同名全局类。
2. 用 `Array[Resource]` 表示配方材料与配方书，保持字段名、默认数量和嵌套 Resource 身份；C# CraftingComponent、CraftingService、UI 和生产 `.tres` 暂不切换。
3. 在已注册的 `reusable_gathering` GodotAI 套件中增加 Crafting 数据聚焦断言，同时加载火把/石斧旧配方确认兼容输入仍可用。
4. 通过 `script_manage.find_symbols`、聚焦与完整套件、Main 场景 helper 冒烟、日志增量、UTF-8 和旧路径扫描后收口；下一批再单独设计 CraftingComponent 的运行时消费边界。

### CraftingService 并行迁移

1. 新增无 `class_name` 的 `crafting_service.gd`，保留 C# 服务的需求汇总、二分最大数量、材料检查、虚拟库存和失败码语义。
2. 把 C# `out` 失败原因转换为 `TryCraftWithReason` 整数返回和 `LastFailureReason` 属性；不把组件信号或 UI 消息复制到规则服务。
3. 在 `reusable_gathering` 套件增加并行库存夹具，覆盖消耗释放空间、产物仍放不下、原子失败不扣材料、成功扣除/产出和非正数量。
4. 通过 GodotAI 符号解析、Crafting 聚焦/完整回归、Main helper 运行时加载、日志、UTF-8 和旧路径扫描后收口；生产组件桥接留到下一批。

### CraftingComponent 并行迁移

1. 新增无 `class_name` 的 CraftingComponent GDScript，保持配方书读取、同级库存绑定、服务调用、失败码和两个信号的原协议。
2. 用 `RecipeBook`/`Recipes` 的通用 Resource 边界同时承接旧 C# 配方和新 GDScript 配方；`TryCraftWithReason` 与 `LastFailureReason` 明确替代 C# `out` 参数。
3. 不修改 `player.tscn`、GameplayPort、CraftingUI 或生产配方资产，避免 C# 强类型事件订阅在程序集未刷新时断裂；旧组件继续作为生产实现。
4. 在 `reusable_gathering` 中增加组件夹具，验证库存绑定、配方身份、最大数量、成功扣除/产出、完成信号、失败信号和失败码。
5. 通过 GodotAI 符号解析、组件聚焦、完整 reusable_gathering、inventory_component 回归、Main helper 烟测、日志、UTF-8 和旧路径扫描后收口；下一批再单独处理 GameplayPort/CraftingUI 的动态边界。

### CraftingUI 生产迁移

1. 新增 GDScript 合成界面，保留原节点路径、GameplayPortPath、Open/Close、配方按钮、材料汇总、数量限制、状态文本和库存延迟刷新。
2. 通过动态信号连接同时接收旧 C# GameplayPort 与并行组件；新组件返回原因码，旧组件用 `TryCraft`/库存协议兼容旧 `out` 失败原因。
3. 切换 `scenes/crafting/crafting_ui.tscn` 的 ext_resource 与 UID，保留 `player.tscn`、GameplayPort、CraftingComponent、配方资产和旧 C# UI 文件。
4. 增加 inventory_component 契约覆盖生产场景脚本、配方按钮、材料行、成功产出、状态文本、关闭行为和信号边界。
5. 通过 GodotAI 符号解析、CraftingUI 聚焦、inventory_component 23/23、reusable_gathering 48/48、Crafting 场景与 Main helper 烟测、日志、UTF-8 和旧路径扫描后收口；下一批再处理 GameplayPort 动态降型或物品链，不与 Autoload/战斗混做。

### ShopService 并行迁移

1. 新增无 `class_name` 的商店规则服务，保留 `IsPurchasable`、`ResolveSellPrice`、买卖校验、容量/余额前置检查、原子副作用和 `ShopFailureReason` 数值。
2. 以 Node/Variant 稳定协议承接旧 C# 钱包/库存与并行 GDScript 钱包/库存；显式目录单价通过带 `WithPrice` 的入口传入，避免改变目录价格回退语义。
3. 增加 reusable_gathering 聚焦夹具，覆盖成功买卖、买价折半卖价、余额不足、容量不足、非正数量、持有量不足、显式卖价和最近失败码。
4. 通过 GodotAI 符号解析、ShopService 聚焦/完整 reusable_gathering、Main helper 烟测、日志、UTF-8 与旧路径扫描后收口；ShopTradeBridge、PlayerWallet Autoload 和商店 UI 留到后续独立边界。

### ShopTradeBridge 并行迁移

1. 新增无 `class_name` 的 `core/shop/shop_trade_bridge.gd`，复刻目录价格回退、显式商品顺序、自动商品 `CardId` 排序和 Resource 身份去重。
2. 通过 `Node`/`Resource` 动态协议读取旧/新钱包与库存，并把 `CanBuy`、`CanSell`、`TryBuyWithReason`、`TrySellWithReason` 委托到已验证的 `shop_service.gd`。
3. 在 `reusable_gathering` 增加 Bridge 聚焦契约，覆盖兜底买价、卖价折半、目录顺序、自动排序、去重、钱包/库存读写和交易失败码边界。
4. 保持 `Shop.tscn`、`shop_control.gd`、PlayerWallet、GlobalWarehouse 和旧 C# Bridge 不变；仅以脚本实例测试并行实现，不宣称商店生产桥已切换。
5. 通过 GodotAI `script_manage.find_symbols`、Bridge 聚焦与完整 `reusable_gathering`、Shop 场景 helper 烟测、日志增量、UTF-8 和旧路径扫描后收口；下一批再单独设计 PlayerWallet 或 ShopTradeBridge 生产切换。

### ShopTradeBridge 生产切换

1. 仅将 `scenes/Shop/Shop.tscn` 的 Bridge ext_resource 从 `ShopTradeBridge.cs` 切到 `shop_trade_bridge.gd`，保留节点名、Catalog、UI 节点结构和旧 C# 文件。
2. 更新 `shop_control.gd` 的边界注释，不改其分页、按钮和信号流程；继续以动态 Bridge 方法读取旧 C# 钱包/仓库。
3. 扩展商店契约测试，锁定生产节点脚本路径并回归目录排序、价格回退、库存/钱包读写和交易结果。
4. 通过 GodotAI 场景加载、`Shop.tscn` 直接运行、Main/运行时 `game_eval`、完整 reusable_gathering、日志、UTF-8 和旧路径扫描；如出现新增脚本/类型/信号错误，立即恢复旧 C# ext_resource。

### PlayerWallet 并行迁移

1. 新增无 `class_name` 的 `core/autoloads/player_wallet.gd`，保留余额字段、GoldChanged 信号、扣款/进账边界、默认金币和持久化键。
2. 通过 SettingsManager 动态协议实现读写、开发期清理、非法存档回退和 int 上限钳制；不复制 PlayerProgression 的升级规则。
3. 在 `reusable_gathering` 增加钱包契约，覆盖默认余额、成功/失败扣款、非正数进账、信号次数和最大值钳制。
4. 保持 `project.godot` 的 C# PlayerWallet Autoload 和 `PlayerProgression.cs` 不变；用 Main `game_eval` 只验证并行脚本挂入场景后的 SettingsManager/交易行为。
5. 通过 GodotAI 符号解析、聚焦与完整 reusable_gathering、Main helper 烟测、日志、UTF-8 和旧路径扫描后收口；下一批再单独降型 PlayerProgression 或切换 PlayerWallet Autoload。

### PlayerProgression 并行迁移

1. 新增无 `class_name` 的 `core/progression/player_progression.gd`，逐项保留仓库/带入栏容量、费用表、最大等级、存档键和升级信号。
2. 以 `Gold`、`TrySpend`、`SetCapacity` 与 SettingsManager 动态协议承接旧 C# 钱包、仓库和设置实现，避免提前替换仍依赖 `IPlayerWallet` 的 Autoload。
3. 在 `reusable_gathering` 增加并行组件夹具，覆盖初始数值、升级费用、扣款顺序、容量同步、最大等级、失败不变更和 `UpgradeChanged` 信号。
4. 通过 GodotAI 符号解析、PlayerProgression 聚焦、完整 `reusable_gathering`、Main helper 烟测、日志、UTF-8 与旧路径扫描后收口；下一批优先处理 GlobalWarehouse/Inventory 兼容边界或降低 PlayerProgression C# 钱包依赖。

### PlayerProgression 生产切换

1. 只替换 `project.godot` 中 PlayerProgression 的 Autoload 路径，保留旧 C# 文件和 UID 作为回滚兼容垫片。
2. 通过 GodotAI `autoload_manage` 确认生产路径，再运行 Main 并用 `game_eval` 检查脚本路径、初始容量、钱包扣款、仓库容量同步和升级结果。
3. 回归 PlayerProgression 聚焦与完整 `reusable_gathering`，检查日志增量、UTF-8 和旧路径扫描；不把 GlobalWarehouse、PlayerWallet、StartingStats、Crafting 或战斗混入本批。

### PlayerWallet 生产切换

1. 只替换 `project.godot` 中 PlayerWallet 的 Autoload 路径，保留 C# 钱包、接口和旧商店服务作为兼容垫片。
2. 用 GodotAI `autoload_manage` 确认生产脚本，再运行 Main 检查新钱包脚本、默认余额、扣款/退款和 PlayerProgression 的动态调用。
3. 回归钱包聚焦与完整 `reusable_gathering`，检查编辑器日志、UTF-8 和旧路径扫描；ShopTradeBridge/ShopService 已通过动态钱包协议，不重复迁移商店逻辑。

### TimeSystem 并行迁移

1. 新增无 `class_name` 的 `core/autoloads/time_system.gd`，逐项保留 C# 时间累计、昼夜切换、天数增加、每七天天赋信号和地图移动耗时。
2. 以动态属性读取协议承接现有 GDScript TimePanel/地图消费者，不修改仍使用 `TimeSystem.Instance` 的 C# 逻辑或生产 Autoload。
3. 在 `reusable_gathering` 增加时间推进、阶段信号、天数信号、阶段进度和地图移动耗时契约；通过 GodotAI 符号解析、聚焦/完整回归、Main 冒烟、日志、UTF-8 和旧路径扫描后收口。

### GameplayPort 并行迁移

1. 新增无 `class_name` 的 `core/application/gameplay_port.gd`，保留六个导出路径、六个请求信号、玩家组件解析、库存委托和遭遇数组转换。
2. 保持 `GameplayPort.cs`、`Main.tscn` 与 C# 强类型消费者不变；通过 Node/Variant 协议为后续 GlobalWarehouse/Inventory 生产边界提供可逆门面。
3. 新增 `tests/godot/test_gameplay_port_contract.gd` 与 `tests/test_gameplay_port_contract.gd` 发现包装器，覆盖节点身份、请求次数、仓库参数、卡组结果、单怪物数组化和堆叠对象身份。
4. 使用 GodotAI `filesystem_manage(op="scan")`、`script_manage.find_symbols`、GameplayPort 聚焦测试（13 断言）、`reusable_gathering` 全量回归（53/53）和 Main helper 冒烟；修复脱离 SceneTree 夹具解析绝对路径的错误后，增量编辑器日志无新增错误。
5. 收口时保留旧 C# 生产路径并记录下一批先处理 GlobalWarehouse/Inventory 消费者降型；不得把 GameplayPort 生产切换与物品链、StartingStats、AttributeModifierData 或战斗混做。

### GlobalWarehouse 生产切换

1. 将 `global_warehouse.tscn` 的脚本引用切换为 `warehouse_inventory_component.gd`，保留 C# 仓库文件和 UID。
2. 在 `GameplayPort.cs` 增加 Node 仓库缓存与 `WarehouseNodeRequested`，旧 C# InventoryComponent 仍发送 `WarehouseRequested`。
3. 让 `warehouse_ui.gd` 双订阅/双解除仓库请求信号，并扩展库存契约测试。
4. 通过 GodotAI 检查真实 Autoload 脚本、Main 仓库打开/关闭、槽位数量、聚焦测试、完整回归、日志、UTF-8 和旧路径扫描。

### CraftingComponent 生产切换

1. 在 C# GameplayPort 保留旧 CraftingComponent 强类型信号，并增加 Node 参数的合成切换/打开信号与通用组件缓存。
2. 让 CraftingUI 同时消费旧强类型信号和新 Node 信号，保持 Open、Toggle、Close 与信号清理时序。
3. 将玩家 CraftingComponent 节点切换到 `crafting_component.gd`，保留 RecipeBook、配方值、节点路径与旧 C# 兼容文件。
4. 用 GodotAI 运行组件/UI 聚焦契约、Inventory 回归、玩家场景与 Main 冒烟，并检查运行脚本身份、日志、UTF-8 和旧路径。

### Crafting 配方 Resource 生产切换

1. 新建两张 GDScript 生产配方，逐项复制旧火把/石斧配方的材料引用、数量、名称、输出和默认产量。
2. 将玩家内嵌 RecipeBookData 改为 `recipe_book_data.gd`，只引用新的 GDScript 配方；保留原 C# 配方资产作兼容对照。
3. 增加生产资产脚本路径和玩家场景引用契约，继续保留旧 C# 配方加载断言。
4. 用 GodotAI 验证两个 Resource、Crafting 6/6、玩家场景真实脚本、Main Tab 打开两张配方和增量日志，再检查 UTF-8 与旧路径。

### Inventory 动态兼容边界

1. 在 `GameplayPort.cs` 保留旧 `InventoryToggleRequested(InventoryComponent)`，新增 `InventoryNodeToggleRequested(Node)` 与 `PlayerInventoryNode` 缓存；根据玩家库存实际脚本选择旧信号或 Node 信号。
2. 调整仓库请求分流：仅当玩家库存与全局仓库都能转换为旧 C# InventoryComponent 时发强类型信号，否则通过既有 `WarehouseNodeRequested` 传递两个 Node。
3. 让 `inventory_ui.gd` 双订阅/双解除库存切换信号，并扩展父面板契约覆盖动态信号打开和退出清理；不切换玩家库存生产脚本。
4. 通过 GodotAI 完成脚本符号解析、InventoryUI 聚焦测试（1/1、40 个断言）、`inventory_component_contract`（24/24）和 Main 真实 B 键打开/关闭验证；检查增量日志、UTF-8 与旧路径后收口。

### Player 库存 Node 访问边界

1. 将 `Player.cs` 的玩家库存缓存降为 Node，保留固定节点路径和 `TryAddItemToInventory(ItemStack)` 公开签名。
2. 通过稳定 `AddItem(Item, Amount)` 动态调用保留“未放入数量为 0 才成功”的原行为；不切换玩家库存生产脚本。
3. 扩展 Inventory 聚焦契约锁定 Node 字段、固定路径、动态调用及无旧强类型解析；通过 GodotAI 运行单测、完整 Inventory 套件和玩家场景真实加物品/回滚冒烟。
4. 检查 cursor 91 后增量日志、UTF-8 与旧路径；下一批单独处理 Equipment 对 GDScript 库存的参数边界，未完成前不切换玩家库存。

### Equipment 消费者 Node 边界

1. 将 `Player.Equipment` 降为 Node，保留固定节点路径；把地形执行、长按协调和两类采集 C# 消费者改为稳定方法动态调用。
2. 保留 EquipmentComponent.cs 生产脚本、EquipmentSlot、ItemStack、EquipmentData、套装/属性/标签规则及所有旧 C# 文件；旧 InventoryUI 仅做兼容转换。
3. 扩展 Inventory 聚焦契约锁定 Node 类型与三个查询方法边界；运行 Inventory 26/26、reusable_gathering 54/54 和玩家场景三项真实查询冒烟。
4. 检查 cursor 91 后日志、UTF-8 与生产旧路径；下一批单独切换 EquipmentComponent 生产脚本并验证换装/采集，不与玩家库存切换混做。

### EquipmentComponent 生产切换

1. 为 `equipment_component.gd` 补齐 `GetEquippedStack(slot)` 兼容入口，将玩家节点脚本切换到该 GDScript，保留旧 C# 文件和 UID。
2. 增加玩家生产场景脚本/信号/方法契约；运行生产切换 1/1、装备规则 4/4、Inventory 27/27、reusable_gathering 54/54。
3. 玩家场景真实装备/卸下 GDScript EquipmentData/ItemStack 并验证标签增减；Main 场景确认装备与三套 UI 实际脚本路径，检查游戏和 cursor 91 后编辑器日志。
4. 若 Main 强制加载暴露旧 C# UI 实例覆盖，只移除覆盖与未使用外部资源并重跑失败用例；最后执行 UTF-8/旧路径扫描和文档收口。

### 玩家 Inventory / BattleDeck 物品链生产切换

1. 将 Player 与 GameplayPort 的 BattleDeck 消费降为 Node，新增 `GetPlayerSkillCards()` 过滤出口，并让 WorldInteractionCoordinator 继续接收原 C# SkillCardData 数组。
2. 同时切换玩家 InventoryComponent 和 BattleDeckComponent 到共享 GDScript 库存链；保留旧 C# ItemStack 加物品入口、全部 C# 组件文件和对照测试。
3. 增加卡组生产契约 1/1（9 断言）与玩家库存生产契约 1/1（8 断言），运行卡组规则 1/1、Inventory 29/29、ItemStack 1/1、reusable_gathering 54/54。
4. Main 真实验证 DebugLoadout 后的技能卡强类型出口、背包/卡组双向移动、旧 C# ItemStack 加物品、Inventory/Warehouse/Crafting UI 打开关闭；检查日志、UTF-8 和旧路径后收口。

### GameplayPort 生产切换

1. 盘点 GameplayPort 的玩家组件缓存、背包/合成/仓库/农场信号、掉落加入、遭遇倍率和通道驻守调用；把 Main 脚本回退及两个 C# 消费者强类型恢复定义为同一回滚点。
2. 补齐 `gameplay_port.gd` 的 Node 信号别名、组件别名和 `GetPlayerSkillCards`，按旧 C# 分流规则只发一组 UI 信号；遭遇倍率经同级 WorldInteractionCoordinator 的稳定方法调用。
3. 将 WorldInteractionCoordinator 与 TerrainInteractionExecutor 的 GameplayPort 依赖降为 Node，通过 PascalCase 方法、Player 属性和动态信号工作；协调器以非泛型数组接收端口输入，再把 EncounterRequested、通道驻守卡组和倍率怪物显式过滤为 `Array<SkillCardData>` / `Array<MonsterData>`。
4. 切换 `Main.tscn` 的 GameplayPort ext_resource，扩展聚焦测试覆盖生产路径、节点身份、全部请求信号、卡组/怪物过滤、倍率调用次数、顺序和 Resource 身份。
5. 使用 GodotAI 完成脚本符号解析、GameplayPort 聚焦、Inventory、reusable_gathering、Main/相关场景冒烟和增量日志检查；最后执行严格 UTF-8 与旧 C# 路径扫描并同步进度和反馈文档。

### LootTable 生产切换

1. 将 GDScript LootTable 的生产输出固定为旧 C# ItemStack，保留概率、数量范围、额外产量、非正过滤和物品 Resource 身份；旧 C# LootTable 继续作为兼容垫片。
2. 把 MonsterData 的 LootTable 字段放宽为 Resource，批量切换 65 个怪物/地形/地图资产的脚本路径与 metadata UID，并同步地形 Profile 生成脚本。
3. 扩展 reusable_gathering 契约，验证生产掉落表路径、C# ItemStack 输出、原物品身份、生成器路径以及代表性怪物/地形资产加载；工具态强类型测试直接实例化 C# ItemData。
4. 使用 GodotAI 运行 LootTable 聚焦、LootComponent、reusable_gathering、ItemStack、Inventory 和 Main 冒烟；运行时确认代表性怪物/地形掉落表、C# 堆叠类型、数量与物品身份，再检查增量日志、UTF-8 和旧路径。

### 棋盘掉落 ItemStack 通用协议

1. 将棋盘状态、视图、控制器、局外协调器和 Player 拾取入口从具体 ItemStack 放宽为 `RefCounted`，集中读取 `Item`、`Amount`、`IsEmpty`，保持对象身份、数量显示和库存成功判定。
2. 将棋盘端口与 GDScript 操作转换改为非泛型 Array；让 `SpawnLootOp` 同时提供旧 `Array<ItemStack>` 与新非泛型 Array 构造入口，并显式复制旧数组。
3. 将生产 LootTable 输出切换到 `resources/item/item_stack.gd`，保留旧 C# ItemData 输入、概率、数量和额外产量；旧 ItemStack/LootTable 与调试工厂不删除。
4. 扩展 reusable_gathering 契约同时覆盖新旧堆叠属性协议与源码边界；用 Main 运行时实际生成两种掉落卡、校验数量/身份、混合数组过滤并加入玩家 GDScript Inventory。
5. 使用 GodotAI 运行聚焦、完整 reusable_gathering、ItemStack、Inventory、LootComponent、GameplayPort、代表性 Resource 加载、Main 冒烟和增量日志；最后检查 UTF-8 与旧 C# 路径并同步文档。

### ResourceCardData 生产切换

1. 新增 `resources/item/card/resource_card_data.gd`，只继承已投产的 `item_data.gd`，保持旧 ResourceCardData 无新增字段或行为的原始契约。
2. 将 branch、charcoal、stone、torch、axe 五个资源卡切换到新脚本，移除旧 `script_class` 与 `_custom_type_script` 标记，保留资产 UID、CardId、显示字段、图标和继承默认值。
3. 扩展 reusable_gathering 中的 ItemData 聚焦契约，逐个锁定脚本路径、旧标记清理、字段值、默认堆叠/价格和通用物品协议；旧 `ResourceCardData.cs` 继续保留。
4. 使用 GodotAI 完成脚本符号解析、ResourceCardData 1/1（65 断言）、ItemData 相关 4/4（935 断言）、代表性 Resource 加载和 Main helper 冒烟；确认 cursor 133 后无新增错误。
5. 执行严格 UTF-8、无 BOM 与旧路径扫描，确认生产资产中旧 C# 路径、类标头和自定义脚本元数据均为 0；下一批先为 SkillCardData 设计动态兼容边界，不直接批量替换技能卡资产。

### SkillCardData 动态兼容边界

1. 新增并行 `skill_card_data.gd`，并为 BaseCardData/ItemData GDScript 增加等价虚属性钩子；保持技能卡三个导出字段、标签、元素、堆叠上限和 C# CombatSkillData 执行入口，显示回退通过 C# Skill 的导出 `CardName` / `Description` / `CardIcon` 字段完成。
2. 将 GameplayPort、WorldInteractionCoordinator、WorldCombatScenePresenter、BattleManager、DeckManager 与 SkillCard 的技能卡输入降为 Resource/Array[Resource]，以 `ApplyEffect` 和稳定字段协议过滤，保留 C# GameplayPort 回滚输入。
3. 扩展 reusable_gathering、GameplayPort 与 Inventory 聚焦契约，覆盖新 Resource 默认值/回退、C# 与 GDScript 卡牌顺序身份、无效 Resource 过滤及战斗入口源码边界。
4. 使用 GodotAI 完成脚本符号解析、SkillCardData 单用例、GameplayPort、Inventory、ItemData/reusable_gathering 回归，以及 battle/Main 场景冒烟和增量日志检查。
5. 检查全部修改文件严格 UTF-8、无 BOM，并确认本批没有改写任何生产技能卡资产、`battle.tscn` 或生成器路径；下一批再单独切换生产技能卡资源及相关外部/内嵌引用。

### SkillCardData 生产资产切换

1. 盘点 69 个 `resources/skill_cards/*.tres`、31 个怪物资源、8 个 CombatSkill 资源、`battle.tscn` 内嵌技能卡和卡表生成器；记录所有脚本路径、UID、字段、子资源及旧元数据作为回滚基线。
2. 将 69 个技能卡和 Battle 内嵌技能卡切换到 `skill_card_data.gd`，只清理对应旧 `script_class` / C# UID 元数据；保持所有业务字段、CombatSkillData 子资源、效果数值、顺序和资产 UID。
3. 删除怪物/CombatSkill 资产中未使用的旧 SkillCardData Script ext_resource，并更新 `card_table/export_current_cards.py` 生成新脚本路径、UID 和类标头；保留 `SkillCardData.cs` 及其 UID 文件。
4. 扩展 GodotAI 聚焦契约，锁定 69 个生产资产、代表性字段/默认值、battle 内嵌资源、怪物与 CombatSkill 无旧冗余引用，以及生成器不会写回 C# 路径。
5. 使用 GodotAI 完成文件系统扫描、代表性 Resource 加载、SkillCardData/GameplayPort/Inventory/reusable_gathering 回归、Battle 与 Main 冒烟及增量日志检查；任一资源加载或战斗错误立即停止扩展。
6. 执行严格 UTF-8、无 BOM 和旧路径扫描，确认生产 `.tres` / `.tscn` / 生成器对 `SkillCardData.cs` 的引用为 0，只允许 C# 兼容源码、测试对照、UID 与任务记录继续保留。

### EquipmentData / ToolData 生产切换

1. 复核两张生产 ToolData 资产、Debug 动态装备工厂、生产 Inventory/Equipment/ItemStack 脚本和全部 C# / GDScript 消费者，确认强类型阻塞已经解除。
2. 将 `Ax.tres`、`Pickaxe.tres` 切换到 `tool_data.gd`，只清理旧 C# 类标头和自定义脚本元数据；保持所有字段、值和资产 UID。
3. 将 `debug_generated_equipment_entry.gd` 的 EquipmentData、ToolData 与 ItemStack 工厂切换到生产 GDScript，保持槽位、CardId、属性范围、工具判定和随机属性行为。
4. 更新 DebugLoadout、Inventory 与 reusable_gathering 聚焦契约，分别验证生产脚本路径、字段、Resource 身份、装备/采集行为及旧 C# ToolData 兼容输入。
5. 使用 GodotAI 运行脚本符号解析、生产 Resource 加载、DebugLoadout、Inventory、reusable_gathering 和 Main 冒烟；随后检查增量日志、UTF-8、BOM 与旧 C# 路径。

### CurrentMapBackgroundResolver 生产切换

1. 将 `WorldCombatScenePresenter` 的 C# 静态 Resolver 调用改为固定 GDScript 路径、动态 Script 工厂和稳定方法协议，保持背景为空时继续进入战斗。
2. 扩展现有背景聚焦契约，锁定 Presenter 使用 GDScript 路径且不再静态调用旧 C# 类型；旧 C# Resolver 文件继续保留。
3. 使用 GodotAI 运行 Resolver 聚焦、reusable_gathering、GameplayPort 回归，并从 Main 发起真实遭遇确认战斗场景收到 `MapBackground`。
4. 检查 Main/战斗游戏日志、editor 增量日志、UTF-8 与旧 C# Resolver 路径；不扩展到怪物数据、CombatSkill 或 AttributeModifierData。

### TimeSystem 生产 Autoload 切换

1. 盘点全部 `TimeSystem.Instance`、强类型字段、信号订阅和时间属性调用，把生产消费者统一降为 `/root/TimeSystem` Node 与稳定属性/方法/信号协议。
2. 通过 `WorldInteractionContext` 和 `TerrainInteractionBuildContext` 把同一时间节点传给 PassTime、可重复采集记录和旧 C# 交互构建；旧兼容文件不删除。
3. 仅将 `project.godot` 的 TimeSystem Autoload 切换到 `res://core/autoloads/time_system.gd`（UID `uid://dd7cqlb6a72pe`），保持其他 Autoload、时间常量、信号顺序、地图移动和七日天赋语义不变。
4. 扩展 GodotAI TimeSystem 聚焦契约，运行 reusable_gathering、GameplayPort、TimePanel 回归；在新 Main 进程验证真实脚本身份、PassTime/PassMapMoveTime、信号及状态，并检查增量日志。
5. 执行严格 UTF-8/BOM 与旧路径/静态 Instance 扫描，确认只保留 TimeSystem.cs 源码/UID及明确测试文档后，同步进度和学习反馈。

### BoardCardView 生产切换

1. 盘点棋盘卡场景、BoardController 的卡牌集合/信号/动画入口，以及 WorldInteractionCoordinator/TerrainInteractionExecutor 的视图调用；保留 BoardCardState、RoomTerrainStore 和战斗系统为本批明确排除项。
2. 新增等价 `core/board/board_card_view.gd`，保留地形/掉落初始化、标题图标、堆叠数量、3 倍地形缩放、散射/飞行动画、禁用灰显和五个信号；生产场景切换脚本路径，旧 C# 视图不删除。
3. 将 BoardController 的视图集合与信号参数降为 `Node2D`，以 `InitializeTerrain`/`InitializeLoot`、`Get*`、`Play*` 和稳定信号协议连接；保持 ItemStack/TerrainInstance 引用、卡牌顺序、散射半径与移除时序。
4. 将 WorldInteractionCoordinator 和 TerrainInteractionExecutor 的视图入口同步降型，继续由 C# 持有交互、时间、遭遇和库存规则，不复制任何玩法逻辑。
5. 增加 `board_card_view_contract` 及根目录测试转发器，使用编辑器 `@tool` 实例锁定场景脚本、方法/信号、地形与掉落字段、数量、缩放和禁用状态。
6. 使用 GodotAI 文件系统扫描、脚本符号解析、BoardCardView 聚焦测试、`reusable_gathering`、Inventory、ItemStack 回归和 Main helper 冒烟；检查日志仅保留既有图片 UID/编辑器警告，最后执行 UTF-8、BOM 与旧 C# 路径扫描并同步任务反馈。

### EncounterManager 编译兼容与 PassageGuardMonsterResolver

1. 盘点两个局外 C# 消费者、Main 中 EncounterManager 节点、GameplayPort 倍率桥和驻守控制器；明确不迁移遭遇概率、怪物缩放、战斗请求或存档格式。
2. 将 `WorldInteractionCoordinator` 与 `TerrainInteractionExecutor` 的 EncounterManager 依赖降为 `Node`，通过稳定方法名动态调用并保留缺失方法的中性回退，解决跨程序集刷新时的 `CS0246`。
3. 新增 `core/map/passage_guard_monster_resolver.gd`，切换 `passage_guard_controller.gd` 和驻守契约测试；旧 C# Resolver、EncounterManager 与结果类型继续保留为兼容垫片。
4. 使用 GodotAI 清理日志、文件系统扫描，运行驻守 Resolver 1/1、`reusable_gathering` 58/58、GameplayPort unnamed 套件 4/4 契约，并在独立 Main 场景中验证倍率和遭遇方法动态调用。
5. 执行 UTF-8/BOM 与旧路径扫描；编辑器 Errors 面板中仅保留此前失败夹具产生的历史 3 条错误，当前游戏日志无新增 SCRIPT ERROR、Parse Error、资源、信号或类型错误。

### BoardCardState 生产切换

1. 盘点 `BoardCardState` 的两个派生状态、BoardController 创建/分支路径和已有 ItemStack 跨语言协议；明确不迁移 RoomTerrainStore、存档或战斗链。
2. 新增 `core/board/board_card_state.gd`，以 RefCounted 保存 terrain/loot 状态、原始 Resource 身份、掉落数量和显示判断，并保留无效输入拒绝行为。
3. 将 `BoardController` 的状态创建与分支消费改为脚本方法协议；保留旧 C# 状态类、文件和 UID，失败时抛出等价异常。
4. 使用 GodotAI 扫描、符号解析、棋盘 ItemStack 契约和 Main 场景冒烟；检查游戏日志无新增 SCRIPT ERROR、Parse Error、资源、信号或类型错误。
5. 执行 UTF-8/BOM 与旧 C# 路径扫描；仅允许旧 BoardCardState 文件、测试对照和任务记录保留 C# 路径。

## 停止条件

任一阶段出现脚本解析错误、场景无法打开、Resource 无法实例化、信号参数不匹配、C# 编译失败或主场景启动错误时，停止扩展迁移范围并先修复该阶段。
