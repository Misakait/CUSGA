# design.md — 跨运行存档系统

> 本文件只记录技术设计与取舍，需求与验收标准见 `prd.md`，执行清单见 `implement.md`。

## 1. 架构总览

```
                    ┌──────────────────────────────────────────┐
user://save/        │ SaveManager (Autoload #1)                │
  game_save.json ──▶│  · 文件生命周期（读/原子写/.bak/版本）      │
  game_save.json.bak│  · 参与者注册表 + 协议校验                  │
  game_save.json.tmp│  · global / run 作用域分流                │
                    │  · 变更信号订阅 + 合并延迟落盘              │
                    └───────┬──────────────────────────────────┘
                            │ register_participant(self)
      ┌─────────────────────┼──────────────────┬────────────────┐
      │                     │                  │                │
 ItemsControl        GlobalWarehouse     PlayerProgression  PlayerWallet
  key="carry"          key="warehouse"     key="player_progression"  key="player_wallet"
  scope=global         scope=global        scope=global      scope=global
  注册即应用（见 §4）   └─ 容量在此推导（level → 27 + 9×level）
```

> `PlayerLevel` **不在参与者之列**：用户定调等级与经验是局内（一局之内）的概念，局外（主菜单、仓库）没有它，因此归入将来的 `data.run`，不进本次局外存档。另注：**单独持久化 `level` / `experience` 是禁止项**——会让"等级保留、属性分配归零、且因等级已满不再发点"，永久销毁玩家已投入的属性点。完整论证见 `prd.md` Background「等级与经验系统的实际状态」与 Out of Scope。

**核心决策**：`SettingsManager` 继续只做**玩家偏好**（`battle/operation_mode`、`battle/feedback_intensity`）；玩法进度一律走新的 `SaveManager`。理由：把「可丢弃的偏好」与「不可丢的存档」放进同一个 `ConfigFile`，会让损坏恢复策略、备份策略与写入原子性互相牵制——偏好读坏了应当无痛回退默认值，存档读坏了必须保留现场并告警，两者的正确行为不同。

## 2. 存档文件契约

### 2.1 路径与产物

| 路径 | 作用 |
|---|---|
| `user://save/game_save.json` | 主存档（UTF-8 JSON） |
| `user://save/game_save.json.bak` | 上一次成功写入的版本；主档损坏时从这里**自动恢复** |
| `user://save/game_save.json.tmp` | 原子写入的中间文件，正常情况下不存在 |
| `user://save/game_save.json.corrupt` | 主档读取失败时保留的损坏现场，供人工排查；存在即说明上一次启动回退过 |

选择 JSON 而非 `ConfigFile` 或二进制：仓库槽位是**嵌套结构**（槽位数组里套字典），JSON 能直接表达且可人工阅读/比对，对本项目当前阶段（无存档体积压力、需要频繁手工验证）是收益最大的一档。代价是数值统一被解析为 `float`，因此每个数值字段都必须显式 `int()` 转换并做类型校验（见 §5.3）。

### 2.2 结构

```json
{
  "format_version": 1,
  "saved_at_unix": 1758672000,
  "data": {
    "global": {
      "player_wallet":      { "gold": 1200 },
      "player_progression": { "warehouse_level": 0, "carry_level": 0 },
      "warehouse":          { "slots": [ null, { "card_id": "wood_01", "amount": 3 } ] },
      "carry":              { "slots": [ null, null, null, null, null,
                                         null, null, null, null, null ] }
    },
    "run": {}
  }
}
```

- `data.global.<save_key>` 的键名就是参与者的 `save_key()`，存档层**不解释**其内部结构。
- `data.run` 本次恒为空对象，但**必须存在**：它是后续「局内进度」的落点，且它的存在让「跨运行文件里禁止出现 run 数据」这条约束可以被测试直接断言。
- 空槽位统一用 `null`，不省略下标——槽位序号本身是玩家可见的排列信息，稀疏写法会把「第 3 格是空的」和「没有第 3 格」混为一谈。

### 2.3 版本与兼容

- `format_version` 必须存在、可转为整数、且**等于** `SaveManager.FORMAT_VERSION`。不等时判定为「无法读取」。

**读取失败的处理顺序**（2026-09-24 实现期修正）：把损坏的主档另存为 `.corrupt` 保留现场 → 尝试从 `.bak` 恢复 → `.bak` 也不可用时才以默认值启动，并 `push_error` 说明原因。**绝不把损坏内容写回 `.bak`**：`.bak` 的意义是「上一份**好**档」，是主档损坏时唯一的自动恢复来源，覆盖它就等于毁掉恢复路径。`has_save()` 的语义相应为「成功读出了一份可用存档（来自主档或 `.bak`）」。
- 本次没有历史存档（三个既有的 `PersistAcrossRuns = false` 拥有者都在 `_ready()` 里主动删掉旧键，从未真正写过任何值；其中 `player_level.gd` 本次不动，但这不影响本结论），因此**不需要迁移代码**。`user://settings.cfg` 里若残留 `[player]` 段属于惰性数据，不再读取也不影响行为；本任务**不写**清理代码（见 §8 取舍 4）。
- 未知的 `data.global` 键（例如未来版本新增、或参与者已被移除）忽略并 `push_warning`，不视为损坏——这是让「删掉一个参与者」不会让旧存档失效的代价最小的做法。
- 缺少 `data.global.<key>` 视为「该参与者没有存档」，参与者必须回退自身默认值（`prd.md` R2.3）。

## 3. 参与者协议

参与者是**任意实现了以下 5 个方法的 `Node`**（不做继承约束：参与者是 autoload，无法继承 `RefCounted` 基类；用鸭子类型 + 注册期校验，与项目既有的 `SetCapacity` / `TakeCarryItems` 稳定方法协议一致）。

```gdscript
func save_key() -> String                       # 稳定键名，发布后不可修改
func save_scope() -> String                     # "global" | "run"
func save_change_signals() -> Array             # 需要触发自动存档的信号名列表，可为空
func capture_save_data() -> Dictionary          # 序列化自身状态
func apply_save_data(data: Dictionary) -> bool  # 用存档恢复自身状态；data 为空字典表示"无存档"
```

- **注册期校验**：`register_participant()` 逐个 `has_method()` 检查，缺方法时 `push_error` 并**拒绝注册**。理由：把协议错误暴露在启动期，而不是等到玩家关窗存档时才发现少了个方法。
- **参与者不需要知道 `SaveManager` 的存在**（除了一行注册调用）：变更信号由 `SaveManager` 按 `save_change_signals()` 订阅，参与者不反向调用 `request_save()`。这让参与者可以在 `test_run` 环境（无 autoload）里被独立构造与断言。
- `save_change_signals()` 里的信号统一接到 `_on_participant_changed(_a = null, _b = null)`：项目里的变更信号最多带 2 个参数（`ExperienceChanged`、`UpgradeChanged`），带默认值的形参可以同时接住 0/1/2 参数的信号。

### 3.1 为什么不需要「应用优先级」

初稿曾引入 `save_apply_priority()` 来解决「容量必须先于物品生效」。最终**去掉**了它，因为注册即应用（§4）的模型下两条顺序都能自洽：

- `GlobalWarehouse`（autoload #3）先注册时：它按存档槽位数 `EnsureCapacityAtLeast(...)`，容量先涨到能装下存档内容；随后 `PlayerProgression`（#8）按 `warehouse_level` 调 `SetCapacity(27 + 9×level)`。`EnsureCapacityAtLeast` **只增不减**，而存档里的槽位数必然 ≤ 存档里那个 level 对应的容量，因此最终容量恰好等于 level 对应值，没有任何物品变成「存在但 UI 看不见」。
- 顺序反过来（仓库排在升级之后）同样成立：容量已经是正确值，`EnsureCapacityAtLeast` 退化为空操作。

也就是说**顺序无关**，多一个优先级字段只会增加必须被测试锁定的表面积。

## 4. 读档时机：注册即应用（关键决策）

### 4.1 问题

`SaveManager` 必须同时满足两件事：

1. 它要在任何参与者注册之前就存在（参与者要在自己的 `_ready()` 里注册）。
2. 读档结果要在 `Main.tscn` 的 `RunStartInitializer._ready()` 消费带入栏**之前**生效。

若把「分发存档」放到 `call_deferred()`（很自然的写法，用来等所有 autoload 注册完），就会踩一个**静默的功能缺陷**：

```
1. autoloads _ready()          → SaveManager 只排了一个 deferred 分发；参与者全部注册完毕
2. Main.tscn _ready()          → RunStartInitializer.Initialize() → ItemsControl.TakeCarryItems()
                                  此刻带入栏还是空的（存档尚未分发）→ 背包为空，带入栏被复位
3. deferred 分发                → 带入栏被恢复成存档内容
```

结果是「玩家上次选好的带入物品这次没带进游戏」，而且日志里没有任何错误——带入栏反而在开局之后又"变回"了存档内容，看起来像个显示 bug。

### 4.2 采用方案：同步 + 注册即应用 + 迟到补应用

- `SaveManager` 注册为 **`[autoload]` 的第一项**（在 `GlobalEventBus` 之前）。它只做文件 I/O 与注册表，不依赖任何其它 autoload，因此放第一项是安全的。
- `SaveManager._ready()`：`_load_from_disk()` 把文件读进内存并把 `_loaded` 置位。**不在这里分发**。
- `register_participant(node)`：校验协议 → 存入注册表 → 若 `_loaded` 则**立刻**把该参与者的数据分发下去（catch-up）；否则记为待分发，等加载完成时补发。
- 因此每个参与者都在自己的 `_ready()` 里**同步**拿到存档，`ItemsControl`（#2）在 `ItemsControl._ready()` 结束前带入栏就已经是存档内容；`Main.tscn` 之后才 ready，带入流程读到的就是正确内容。
- 迟到注册（未来每局新建的 run 参与者、测试夹具）走同一条补发路径，语义一致。
- `register_participant` 在分发期间置 `_is_applying = true`，压制这一过程产生的自动存档请求，避免「刚读进来就写回去」把文件重写一遍（也会掩盖真正的写入错误）。

### 4.3 代价与约束

- 必须锁定 `project.godot` 里 `SaveManager` 位于所有参与者之前：由契约测试断言（`prd.md` R7.3）。若将来有人把它挪到后面，测试会失败而不是静默丢档。
- `register_participant` 对「尚未加载完成」也做了兜底（存为待分发），因此即使顺序被误改也不会丢档，只会退回到「deferred 分发」的语义。

## 5. 序列化细节

### 5.1 槽位编解码复用一个工具

仓库槽位与带入栏条目都是「物品 + 数量（+ 洗炼属性）」，因此编解码下沉到 `core/save/save_slot_codec.gd`（`static` 函数，无状态），供两个参与者共用：

```gdscript
static func encode_entry(item: Resource, amount: int, rolled: Dictionary) -> Variant
static func encode_slots(slots: Array) -> Array
static func decode_entry(raw: Variant, lookup: Callable) -> Dictionary
    # → {"ok": bool, "item": Resource, "amount": int, "rolled": Dictionary, "reason": String}
```

- `lookup: Callable` 是 `card_id → Resource` 的查表函数（生产传入 `ItemsControl.get_item` 的绑定）。**注入而非直接引用 autoload**，使编解码可在 `test_run`（无 autoload）里完整测试。
- 物品身份只落 `CardId`（`StringName` → `String`），不落资源路径也不落显示名：`CardId` 是项目里唯一的稳定身份（`ItemsControl` 就是按它建索引），资源路径会随目录整理而失效，显示名会随文案改动而失效。
- `rolled`（装备洗炼属性）的键是 `AttributeType` 的**整型枚举**（实测 `{0: Vector2i(...)}`）。JSON 对象的键只能是字符串，因此写为 `{"0": 15}`，读回时 `int` 解析回整型键并要求值必须是数值——这一步就消掉了「枚举 → 字符串 → 枚举」的类型歧义。此外**仅当物品确实声明了 `AttributeBonuses`** 时才与该键集合求交集（不在集合里的键丢弃并计告警），用来挡住属性表被改动后的脏数据；物品没有声明时不做交集。理由：2026-09-24 运行期验证发现，无条件求交集会把普通物品（没有 `AttributeBonuses`）上的洗炼属性**全部销毁**——「无法判断」不等于「非法」，丢弃判断不了的数据比留下一个已无意义的键危险得多。

### 5.2 槽位数组

- 定长（写：`slot_count` 长度；读：以 `slots` 数组实际长度为准并夹紧到 `Capacity` 上限逻辑内）。
- 读档顺序固定为：**先清空全部槽位 → 再按存档写入**，保证「读档结果 == 存档内容」而不是叠加（`prd.md` R3.5）。`ItemsControl.carry_items` 同理先复位为全空条目。
- 水合失败（`card_id` 不存在 / 数量非法 / 槽位不是字典）只跳过该槽位并计入告警计数，**不**让整档读取失败（`prd.md` R3.3）。返回值 `apply_save_data()` 的 `bool` 表达的是「存档结构本身可用」，跳过个别槽位不影响它。

### 5.3 数值校验

JSON 数值统一是 `float`，因此每个字段都走同一套模式（沿用三个既有脚本已验证过的写法）：

```
读 → 检查 is int or is float → int() → 领域校验（非负 / 收窄到上下限）→ 越界则告警并用收窄值
```

各参与者的领域规则**保持不变**，只是数据来源从 `SettingsManager` 换成存档：金币非负否则回退 `DefaultGold=1200`；升级等级收窄到各自上限。

（`player_level.gd` **不在本次参与者之列**：用户定调等级与经验是局内概念，局外存档不含它。**单独持久化 level/experience 是禁止项**，原因见 `prd.md` Background「等级与经验系统的实际状态」。）

### 5.4 容量不进仓库存档

`warehouse` 参与者**只存槽位**，不存容量数值。容量是由 `warehouse_level` 推导出来的规则值（`27 + 9×level`），存两份会产生两个真相源，改公式时必然分叉。仓库侧只做防御性的 `EnsureCapacityAtLeast(存档槽位数)`（§3.1）。

## 6. 自动存档

### 6.1 触发面

| 触发 | 来源 | 机制 |
|---|---|---|
| 仓库内容变化 | `GlobalWarehouse.InventoryChanged` | `save_change_signals()` |
| 带入栏变化 | `ItemsControl.carry_items_changed`（**新增信号**） | `save_change_signals()` |
| 金币变化 | `PlayerWallet.GoldChanged` | `save_change_signals()` |
| 升级成功 | `PlayerProgression.UpgradeChanged` | `save_change_signals()` |
| 关窗 | `NOTIFICATION_WM_CLOSE_REQUEST` | 同步 `save_now()` |
| 退出场景树 | `NOTIFICATION_EXIT_TREE` | 同步 `save_now()`（幂等；覆盖编辑器「停止运行」这条不触发 WM_CLOSE 的路径） |

`ItemsControl` 目前**没有**任何变更信号，因此为带入栏新增 `carry_items_changed`：`SetCarryEntry` / `ClearCarryEntry` / `TakeCarryItems` 在实际改变了内容时发出。这是本次唯一一处对既有公开面的**新增**（纯追加，不删除、不改签名），并且「开局带入消耗」也需要它——不带入即消耗的落盘，玩家会靠重启把物品刷回来。

### 6.2 合并延迟

- `request_save()` 只把 `_dirty` 置位；真正的写入由 `_process(delta)` 在 `_dirty` 持续超过 `SAVE_DEBOUNCE_SECONDS = 0.5` 后执行一次。
- 为什么不用"一次 `call_deferred` 就写"：拖拽/批量移动物品会在连续多帧里持续发 `InventoryChanged`，那种写法会变成每帧一次磁盘写入。
- 为什么不用 `Timer`：`Timer` 受 `get_tree().paused` 影响，而存档必须对暂停免疫（玩家可能暂停着整理仓库然后关窗）。`SaveManager` 直接设 `process_mode = Node.PROCESS_MODE_ALWAYS`，用自己的 `_process` 做去抖即可，不引入额外节点。
- `_is_applying` 期间到达的变化请求被丢弃（不是延迟）：它们的语义是"读档造成的回声"，落盘只会多写一次相同内容。

### 6.3 原子写入

```
1. 确保 user://save/ 目录存在（DirAccess.make_dir_recursive_absolute）
2. 目标文件存在时先复制为 .bak
3. 内容写入 .tmp 并 close（FileAccess 关闭即 flush）
4. DirAccess.rename_absolute(.tmp → 目标)
   失败时退化为 remove + rename
```

第 2 步先做 `.bak`，使第 4 步的退化路径（存在一个"目标文件不存在"的窗口）仍然可恢复。写入失败一律 `push_error` 并返回 `false`，**不**假装成功——内存里的状态仍然有效，但日志必须让"没存上"这件事可见。

## 7. 测试设计

`tests/godot/test_save_system_contract.gd`（套件 `save_system_contract`，配 `tests/test_save_system_contract.gd` 转发壳）。测试**不依赖 autoload**：用 `脚本.new()` 构造 `SaveManager`，用 `save_file_path` 指到临时路径，参与者用桩节点/桩 Callable。

| 组 | 断言要点 |
|---|---|
| 形状与注册 | 生产脚本存在、带 uid 旁车、无 `class_name`；`project.godot` 里 `SaveManager` 是 `[autoload]` 第一项且位于全部参与者之前；4 个参与者脚本都实现 5 个协议方法 |
| 协议校验 | 缺方法的桩参与者被拒绝注册、产生可诊断错误、不进入注册表 |
| 编解码往返 | `encode_slots` → `decode_slots` 后物品身份、数量、洗炼属性、槽位序号逐一相等；空槽位保持为 `null` |
| 未知物品 | 存档里 `card_id` 不存在时跳过该槽位、计数加一、其余槽位正常水合 |
| 洗炼属性校验 | `rolled` 里不属于该物品 `AttributeBonuses` 的键被丢弃并计数；物品未声明 `AttributeBonuses` 时只做类型校验、不丢弃 |
| 版本与损坏 | `format_version` 不符 / 非法 JSON / `data` 非字典 → 回退默认值、损坏内容保留为 `.corrupt`、必要时从 `.bak` 恢复、不抛错 |
| 无存档 | 文件不存在时 `has_save()` 为 false，参与者全部回退默认值 |
| 原子写入 | 连续两次 `save_now()` 后 `.tmp` 不存在、`.bak` 等于上一次写入的内容、主文件等于最新内容 |
| 作用域分流 | 注册 `scope="run"` 的桩参与者后 `save_now()`，主文件里 `data.run` 为空、`data.global` 不含它的 key；`clear_run_scope()` 后桩参与者的数据消失 |
| 去抖 | 连续 3 次 `request_save()` 后手动驱动 `_process`，只发生一次写入 |
| 幂等 | 同一份存档连续 `apply` 两次，参与者状态与只应用一次完全相同 |
| 参与者行为 | `warehouse` / `carry` / `player_wallet` / `player_progression` 的 `capture`→`apply` 往返等价；越界值被收窄并告警 |

另外**更新** `tests/godot/test_logic_family_contract.gd` 里被本次需求反转的断言（钱包 / 升级的 `PersistAcrossRuns = false`）。它是项目用来锁定"有意设计"的机制，需求既然反转，断言就必须一起反转，而不是删掉。`tests/godot/test_player_level_contract.gd` **不动**——等级属局内概念，其既有断言继续充当「等级系统不得私自持久化」的守卫。

## 8. 取舍记录（为什么不是别的方案）

1. **不把存档塞进 `user://settings.cfg`**：`ConfigFile` 能存数组字典，技术可行，但偏好与存档的损坏恢复策略不同（§1），且后续局内进度会变成一份体积不小、需要版本管理的数据，混在偏好文件里会让"重置偏好"意外清档。
2. **不为存档新建第二个 autoload 去持有仓库副本**：仓库槽位的权威已经在 `GlobalWarehouse`，再放一份必然要同步（项目已经因为"界面持有一份副本"吃过亏，见 `ItemsControl.gd:24-28` 的注释）。参与者模式让每个模块继续持有自己的真相。
3. **不自造二进制/`ResourceSaver` 存档**：`ResourceSaver` 存 `ItemStack` 会把整个物品 `Resource` 序列化进存档，物品数值一改，旧档就带着旧数值——那等于在存档里冻结了一份内容数据。只存 `CardId` 才让"改数值"对所有存档同时生效。
4. **不写旧键清理代码**：三个脚本从未真正写入过玩法进度键，`[player]` 段的残留只可能来自更早的手工调试，且不再被任何代码读取。为一段惰性数据引入启动期写操作，收益低于它在存档层里增加的分支。
5. **不做优先级字段**（§3.1）：让正确性依赖"两个顺序都能自洽"的不变量，比依赖一个必须被测试锁定的排序字段更结实。
6. **不带玩家可见 UI**：用户明确选择"全自动，无 UI"。为了让测试者能回到新档状态，`erase_save()` 作为 API 暴露，并把手动删除文件的位置写进文档；开发者面板按钮列入 Out of Scope，避免本次改动扩散到场景文件与既有 UI 套件。

## 9. 风险与回滚

| 风险 | 缓解 |
|---|---|
| `project.godot` 里 autoload 顺序被改动 → 退化为 deferred 语义（带入栏丢失） | §4.3 的兜底 + 契约测试锁定顺序 |
| 仓库槽位在旧存档里超出当前容量 → 物品不可见 | §3.1 的 `EnsureCapacityAtLeast` + 读档顺序无关论证 |
| 新存档把玩家既有仓库/带入栏"重置" | 读档先清空再写入是**有意**的（存档是唯一真相源）；首次运行无存档时保持默认空状态，行为与现状一致 |
| 新增 `carry_items_changed` 影响仓库界面刷新 | 纯追加信号，现有界面仍走自己的显式刷新；不在本次改动中改为订阅式刷新 |
| 自动化存档引入每帧磁盘写入 | 0.5s 去抖 + 契约测试断言只写一次 |
| 写入失败被静默忽略 | `save_now()` 返回 `bool` 且失败 `push_error` |
| 门禁被既有失败污染 | 实施前先跑一次全量 `test_run` 建立基线；`logs_read(source="editor")` 的既有负路径输出已在 `prd.md` 记录 |

**回滚**：`git checkout -- <本任务改动的文件>`（4 个参与者脚本 + `project.godot` + `tests/godot/test_logic_family_contract.gd`）并删除 `core/save/`、`tests/**/test_save_system_contract.gd`；运行期回滚只需删除 `user://save/game_save.json`（下次启动回到默认值）。存档层与玩法代码之间只有"注册 + 声明信号"这一条边，删除参与者里的 5 个方法即可完全摘除，不留半连接状态。
