# 开局角色与背包初始化（只带入仓库所选物品）

## Goal

每局开局时把角色与其背包置于一个**确定、可复现的初始状态**：背包内容**完全等于**玩家在局外仓库「带入栏」中选定要带入的物品堆叠——不多一件，不少一件；并被**消耗**（带入后带入栏清空）；同时让这次初始化成为**唯一的开局入口**，解除当前调试开局配置对它的覆盖。

## Background（已核实事实，带证据锚点）

- **玩家每个开局都是全新实例**：`scenes/player_scenes/player.tscn:56` 起，`InventoryComponent`、`BattleDeckComponent`、`EquipmentComponent` 三个组件在场景里**都没有预置内容**。因此实现上「初始化」等价于「先清空、再按带入栏装入」，不需要额外还原任何上一局残留。
- **带入栏 → 局内的现有链路**：
  - 导出：`scripts/warehouse/warehouse_control.gd:111`（`exit()`）把带入栏中实际占用的栏位写入 autoload `ItemsControl.warehouse_to_player` 与 `warehouse_to_player_cnt`（`core/autoloads/ItemsControl.gd:12`）。
  - 消费：`scripts/map_scripts/map_control.gd:24`（`_ready()`）遍历这两个数组调用 `player._inventory.AddItem(item_data, amount)`，随后清空数组（同文件 `:29`）。
- **现有实现的三处缺陷**（本任务要修的对象）：
  1. **会被调试配置覆盖**：`scenes/Main.tscn:94` 挂有 `DebugLoadoutSeeder`（`core/debug/debug_loadout_seeder.gd`），其 `_ready()` 用 `call_deferred("ApplyLoadout")`（同文件 `:44`）延迟执行；deferred 在整棵树 `_ready` 之后运行，因此它在 `map_control` 装入带入物品**之后**再清空背包、清空出战卡组、卸下全部装备（同文件 `:20-27` 三个 `Clear*BeforeApply` 默认为 `true`），最后塞入调试物品。**结论：需求「只带入仓库里选择带入游戏的物品」当前实际不成立。**
  2. **职责错位**：带入逻辑写在 `map_control`（地图控制器）里，而不是开局初始化本身。
  3. **越界访问玩家内部成员**：直接读写 `player._inventory`（私有字段），不符合项目「按稳定方法协议交互」的既有约定。
- **带入栏权威状态当前活在场景实例里**：`_carry_items` 是仓库场景实例的成员（`scripts/warehouse/warehouse_control.gd:61`），而仓库场景被 `SceneManager` **长期缓存复用**（`core/autoloads/SceneManager.gd:13`、`:70`）。因此带入栏内容在离开仓库后仍然保留，**且 Main 侧无法可靠地清空它**——这是「带入即消耗」必须解决的结构性障碍。
- **带入栏规格**：硬上限 10 个栏位（`scripts/warehouse/warehouse_control.gd:18`），**可用**栏位数由 `PlayerProgression` 的带入栏升级决定（基础 5，每级 +1，上限 5 级；`core/progression/player_progression.gd:26-30`、`:101`）。
- **账户级数据与角色运行态的边界**：`PlayerWallet`（`core/autoloads/player_wallet.gd:19`）、`PlayerProgression`（`core/progression/player_progression.gd:17`）、`PlayerLevel`（`core/progression/player_level.gd:26`）都是 autoload，在同一次进程内**跨场景保留**（只是不落盘）。因此本任务的「初始化角色」只重置**角色运行态**。
- **局外仓库开局时是空的**：`core/autoloads/global_warehouse.tscn` 没有任何预置内容，全工程只有测试按钮 `tests/huhu9/test_fish.gd` 与商店购买会向仓库写入。因此严格按带入栏初始化后，**新会话默认就是空手开局**。
- **局内 → 局外回写链路未实现**：`ItemsControl.player_to_warehouse` 只有消费点（`scripts/warehouse/warehouse_control.gd:202`），**没有任何生产者**。

## Requirements

### R1 唯一的开局初始化入口

- 开局初始化必须收敛到**一个显式入口**，不再散落在 `map_control._ready()` 里。
- 该入口必须广播一个**开局初始化完成信号**，供后续环节（开局技能卡抽取）挂接，使「初始化 → 抽卡」的顺序确定且唯一。
- 入口必须**幂等**：同一次开局内重复触发不得把带入物品装入两次。

### R2 背包初始化语义

- 初始化后，玩家背包内容**严格等于**带入栏中选定要带入的物品堆叠：物品身份、堆叠数量一一对应。
- 带入栏为空、或玩家本次运行从未进入过仓库时，背包必须为空——不得出现任何未经玩家选择的物品。**空手开局是预期行为**。
- 初始化必须先清空背包再装入，保证可重复执行不累积。
- 写入必须经过组件暴露的稳定接口（`Capacity` / `TryClearStackAt` / `AddItem` 等既有协议），**不得**再直接访问玩家私有字段。
- 背包容量不足导致放不下时，必须产生可诊断的警告；放不下的部分**不退回带入栏**（与 R3 的消耗语义一致）。

### R3 带入即消耗

- 开局初始化取出带入栏内容后，带入栏必须**立即清空**：同一批物品不得在下一局被重复带入。
- 清空必须是**权威层面**的清空，而不是只清界面：玩家退回主菜单、再次进入仓库时，带入栏必须显示为空（不得因为仓库场景实例被缓存而复现已带入的物品）。
- 带入栏内容的权威状态必须能在**场景之外**被读取与清空，从而不受场景缓存生命周期影响。
- 玩家在**尚未开始游戏**时把带入栏内容「取出」退回仓库的既有行为必须保留不变。

### R4 与调试开局配置的关系

- 正式开局流程中，`DebugLoadoutSeeder` 不得再清空或覆盖按带入栏初始化的结果；其在 `scenes/Main.tscn` 上默认**不生效**。
- 调试开局配置脚本与 `resources/debug/default_inventory_loadout.tres` **保留**，可手动启用以「有意覆盖」开局带入（这是显式调试选择，不再默认发生）。

### R5 范围与约束

- 不修改仓库界面既有的交互模型（点选 + 放入/取出按钮）、容量升级与商店联动。
- 不实现「局内物品带回局外仓库」（`ItemsControl.player_to_warehouse` 当前无生产者），属于独立需求；该字段本次**原样保留**。
- 不重置账户级数据：金币、角色等级/经验、仓库与带入栏的容量升级等级保持现状。
- 不修改战斗内卡组与出牌规则。
- 不新增 autoload 单例：带入栏权威复用既有 `ItemsControl`（依据 `.trellis/spec/frontend/state-management.md:37`）。
- 不引入重复常量：仓库界面的 `CARRY_MAX_POSITIONS` 与权威的容量常量必须由测试断言保持同值。

## Acceptance Criteria

- [ ] 从主菜单点「Start」进入一局后，玩家背包内容与带入栏选定内容**逐项一致**（物品身份与堆叠数量都一致）。
- [ ] 带入栏为空时开局，玩家背包为空（当前被调试配置塞入的测试物品不再出现）。
- [ ] 开局带入后，退回主菜单再进入仓库，带入栏显示为**空**；再开一局不会重复获得同一批物品。
- [ ] 带入栏放入内容后开局，调试开局配置不再清空或覆盖背包/出战卡组/装备。
- [ ] 连续两次开局不会出现背包内容累积或数量翻倍。
- [ ] 开局初始化只执行一次；同一次开局内不得重复装入，且完成信号只广播一次。
- [ ] 玩家背包的写入全部通过组件稳定接口完成，代码中不再出现对玩家私有字段的直接访问。
- [ ] 带入栏权威容量常量与 `warehouse_control.CARRY_MAX_POSITIONS` 由测试断言同值。
- [ ] `tests/godot/test_run_start_loadout_contract.gd`（套件 `run_start_loadout_contract`）通过，覆盖「空带入栏 / 有内容 / 重复调用 / 取出后清空 / 容量不足」五种情形。
- [ ] 运行主场景与 `Main.tscn` 均无 `SCRIPT ERROR`；`logs_read(source="game")` 中无 `Nil` / `Invalid access` 一类错误。
- [ ] `game_eval` 在运行中的游戏里断言：开局后带入栏权威为空、背包条目与带入内容一致。
- [ ] `docs/游戏机制与玩法内容.md` 已新增「开局流程」一节，记录初始化时机、带入即消耗规则、带入栏上限 10 等数值。

## Out of Scope

- 「局内物品带回局外仓库」（`ItemsControl.player_to_warehouse` 的生产者）——**本轮不做**，开发者已明确选择。
- 死亡结算与「死亡损失」（`player_died` 当前无消费者，死亡不结束一局）。
- 局外仓库的初始内容来源：仓库保持为空，接受空手开局。
- 跨局/跨运行存档（沿用 `PersistAcrossRuns = false`）。
- 开局技能卡抽取（由子任务 `09-23-run-start-skill-card-draft` 承接）。

## Notes

- 本任务由父任务 `09-23-game-start-flow` 派生，承接源需求 SR-1。
- 本次与开发者确认的三项决策：①**带入即消耗**，开局带入后清空带入栏；②**本轮不做回写**，消耗造成的永久损失暂不补救；③**仓库保持为空、接受空手开局**，调试物品改由手动方式获取。
- 「初始化角色」的口径已按仓库证据收敛为：**重置角色运行态（背包/出战卡组/装备等节点级状态），不重置账户级数据**（金币、等级、仓库容量）。
- 与本任务相关的结构性问题（带入栏权威状态被场景缓存绑架、调试配置覆盖、职责错位）在 `design.md` 中给出统一解法；实现顺序与验证手段见 `implement.md`。
