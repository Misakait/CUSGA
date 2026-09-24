# implement.md — 跨运行存档系统执行清单

> 需求见 `prd.md`，技术设计与取舍见 `design.md`。本文件只记录**执行顺序、验证命令、风险点与回滚点**。
>
> 本机验证边界（务必遵守）：项目已无任何 `.cs` / `.csproj` / `.sln`，`AGENTS.md` 与部分 spec 里的 `dotnet build` 门禁在本仓库**没有对象**；唯一可用的门禁是 Godot 编辑器 MCP。编辑器必须处于打开状态（当前已验证：4.7.1，`readiness = ready`）。

## 0. 改动清单

### 新增

| 文件 | 作用 |
|---|---|
| `core/save/save_manager.gd` | 存档层 Autoload：文件生命周期、原子写、`.bak`、版本、参与者注册表、作用域分流、去抖落盘 |
| `core/save/save_slot_codec.gd` | 槽位编解码（`CardId` + 数量 + 洗炼属性），仓库与带入栏共用，查表函数注入 |
| `tests/godot/test_save_system_contract.gd` | 新契约套件（`suite_name() == "save_system_contract"`） |
| `tests/test_save_system_contract.gd` | 4 行转发壳（`test_run` 只扫 `res://tests` 顶层且只认 `test_*.gd`） |

### 修改

| 文件 | 改动 |
|---|---|
| `project.godot` | `[autoload]` 段把 `SaveManager` 插到**第一项**（`GlobalEventBus` 之前） |
| `entities/components/warehouse_inventory_component.gd` | 加 `_ready()`（`super()` + 注册）与 5 个协议方法（key `warehouse`） |
| `core/autoloads/ItemsControl.gd` | 新增 `carry_items_changed` 信号；`_ready()` 改为 `_ensure_carry_capacity()`；注册（key `carry`） |
| `core/autoloads/player_wallet.gd` | 移除 `PersistAcrossRuns` / `SettingsManager` 读写；注册（key `player_wallet`） |
| `core/progression/player_progression.gd` | 同上（key `player_progression`）；容量仍由 level 推导 |
| `tests/godot/test_logic_family_contract.gd` | 反转 `test_player_data_policy_switch_parity` 的 `PersistAcrossRuns = false` 断言（钱包 + 升级两处） |
| `docs/游戏机制与玩法内容.md` | 新增「存档系统」一节；第 217 行「等级与经验不跨运行保存」的结论**保留**，补一句指向新的存档系统一节 |

**不动**：`core/progression/player_level.gd` 与 `tests/godot/test_player_level_contract.gd`（等级与经验是局内概念，用户明确本次不制作；其既有断言继续充当「等级系统不得私自持久化」的守卫）、`core/autoloads/SettingsManager.gd`（继续只做偏好）、仓库界面 / 商店界面、`ItemsControl.player_to_warehouse` 回写链路、`AGENTS.md`。

## 1. 建立基线（必须先做）

```text
test_run()                                        # 全量；记录 failed / suites_run / total
logs_read(source="editor")                        # 记录 next_cursor 与既有错误条目
```

- 基线里**已知的既有输出**：`core/map/room_terrain_store.gd` 的负路径 `push_error`、`core/gameflow/run_start_initializer.gd` 的夹具警告、`GlobalEventBus.gd` 的未使用信号警告。
- `tests/godot/test_talent_selection_contract.gd` 曾出现在旧日志里的 `TALENT_SCREEN_SCENE_PATH not declared` 解析错误**已被修复**（该常量在第 20-21 行），若基线里再次出现则先确认真实来源，不要误判为本任务回归。
- 若基线本身 `failed > 0`：**先记录，不要在本次任务里顺手修**（除非失败项正是本任务要改的两个套件）。基线失败会让"本任务是否引入回归"无法判定。

**回滚点 A**：此时工作区应仍是干净的（除既有的 `scenes/Main.tscn` 改动）。

## 2. 存档层（先写核心，不碰玩法）

1. 写 `core/save/save_slot_codec.gd`：
   - `static func encode_entry/encode_slots/decode_entry/decode_slots`
   - `decode_*` 接受 `lookup: Callable`（`card_id → Resource`）；洗炼属性的属性键白名单取自物品 `AttributeBonuses`，且**仅在该字段非空时才生效**（为空表示「无法判断」，此时只做类型校验、不丢弃数据）
   - 返回结构必须能区分「结构损坏」与「该项被跳过」
2. 写 `core/save/save_manager.gd`：
   - 常量：`SAVE_DIRECTORY`（默认目录）/ `DEFAULT_SAVE_FILE_PATH` / `BACKUP_SUFFIX` / `TEMP_SUFFIX` / `CORRUPT_SUFFIX` / `FORMAT_VERSION` / `SCOPE_GLOBAL` / `SCOPE_RUN` / `SAVE_DEBOUNCE_SECONDS` / `PARTICIPANT_METHODS`
   - `@export var SaveFilePath`（测试可改指临时路径）；`.bak` / `.tmp` / `.corrupt` 路径由它推导（`get_backup_file_path()` 等），**写入目录也由它推导**（`get_save_directory()`）——用常量目录会导致覆写路径后建错目录、写入静默失败
   - 公开面：`has_save()` / `register_participant(node)` / `capture()` / `apply(data)` / `request_save()` / `save_now()` / `erase_save()` / `clear_run_scope()` / `get_loaded_data()`
   - `_ready()`：`process_mode = ALWAYS`，`_load_from_disk()`
   - `_notification`：`WM_CLOSE_REQUEST` 与 `EXIT_TREE` → `save_now()`
   - 全程禁止 `:=` 从 `Variant` 推断（本项目把该告警当错误）；一切跨脚本访问走 `call` / `get` / `has_method`
3. `project.godot`：把 `SaveManager="*res://core/save/save_manager.gd"` 插到 `[autoload]` 第一行。

```text
filesystem_manage(op="scan")     # 注册新脚本；确认 new_errors_since_last_call 不增
editor_state                     # 确认 Autoload 生效、无启动期报错
```

**回滚点 B**：若 `editor_state` 出现启动期解析错误，先 `git checkout -- project.godot` 并摘掉 `save_manager.gd` 的注册，定位后再继续。

## 3. 契约套件（先把测试立起来，再接连玩法）

1. 写 `tests/godot/test_save_system_contract.gd`（`@tool extends McpTestSuite`，套件名 `save_system_contract`；断言覆盖 `design.md` §7 表格里的 12 组）。
2. 写 `tests/test_save_system_contract.gd` 转发壳。
3. 运行：

```text
test_run(suite="save_system_contract")    # 必须 total > 0（total == 0 表示"没被发现"，不是通过）
```

**门禁 1**：`save_system_contract` 套件通过且 `total > 0`。

## 4. 参与者接线（逐个接，逐个验）

顺序刻意从「风险最高的容量耦合」到「纯标量」：

1. `core/progression/player_progression.gd`（`player_progression`）——容量推导的拥有者，必须最先可读档。
2. `entities/components/warehouse_inventory_component.gd`（`warehouse`）——**最容易出错的一环**：确认 `_ready()` 调了 `super()`、`apply_save_data` 先清空再写入、超容量时 `EnsureCapacityAtLeast`。
3. `core/autoloads/ItemsControl.gd`（`carry`）——新增信号 + `_ready()` 不再无条件复位。
4. `core/autoloads/player_wallet.gd`（`player_wallet`）。
5. **`core/progression/player_level.gd` 不做**（等级与经验是局内概念，用户明确本次不制作）。本步刻意留空占位，防止后续照抄清单时顺手把它接上。

> **禁止项**：不要给 `player_level.gd` 加存档协议。只存 `level` / `experience` 会让玩家在下次启动时等级保留、属性分配归零，而等级已满导致属性点再也不发放——玩家永久损失已投入的点数。完整论证见 `prd.md` Background「等级与经验系统的实际状态」。

每接完一个（或每接完仓库+带入+升级这三个有耦合的）：

```text
filesystem_manage(op="scan")     # 读 new_errors_since_last_call
test_run(suite="save_system_contract")
```

**门禁 2**：`save_system_contract` 覆盖到全部 4 个参与者（`player_progression` / `warehouse` / `carry` / `player_wallet`）的 `capture → apply` 往返。

**风险点（本任务最高）**：`inventory_component.gd` 是**共享基类**，玩家背包也用它。给 `warehouse_inventory_component.gd`（派生）加协议**不要**动基类；基类的 `_ready()` / `_slots` 语义必须逐字不变。改动后必须跑与库存相关的既有套件（`inventory_component_contract` 等）确认无回归。

## 5. 反转既有契约断言

1. `tests/godot/test_logic_family_contract.gd:304-330`：`test_player_data_policy_switch_parity` 改为断言「钱包与升级两个脚本都不再声明 `PersistAcrossRuns`，且都实现了存档协议」。
2. `tests/godot/test_player_level_contract.gd` **完全不动**：等级属局内概念，本次不制作，其既有断言（`PersistAcrossRuns = false` + Autoload 顺序）继续作为「等级系统不得私自持久化」的守卫。

**注意**：这两处是**有意设计被需求反转**，不是"测试挡路就删测试"。改完后失败的语义从「设计被破坏」变成「协议缺失」。

```text
test_run(suite="logic_family_contract")
test_run(suite="player_level_contract")
```

**门禁 3**：两个既有套件通过。

## 6. 运行期验证（真正的验收）

编辑器 `test_run` 没有 autoload，**无法**覆盖本任务的核心时序决策（`design.md` §4.2）。必须走真实游戏进程。

### 6.1 首次启动（无存档）→ 写档

```text
project_run(mode="custom", scene="res://scenes/Main.tscn")
game_eval: /root/SaveManager 存在；4 个参与者已注册；
           默认值 = 金币 1200 / 等级 1 / 仓库 level 0。
game_eval: 往 /root/GlobalWarehouse 加两种物品（一堆数量 > 1）；
           /root/ItemsControl.SetCarryEntry(0, <某物品>, 2)；
           /root/PlayerWallet.Add(300)；
           /root/SaveManager.save_now()
logs_read(source="game")                       # 无 SCRIPT ERROR
project_manage(op="stop")
```

### 6.2 二次启动（有存档）→ 读档 + 带入时序

```text
project_run(mode="custom", scene="res://scenes/Main.tscn")
game_eval: /root/GlobalWarehouse 的槽位内容、槽位序号、堆叠数量与上次写入一致
game_eval: /root/SaveManager.has_save() 为 true；金币 = 1500
game_eval: 带入栏第 0 格已空（被 RunStartInitializer 消耗）
           且玩家 Components/InventoryComponent 里存在那件物品且数量为 2
```

这一条同时验证了三件事：①仓库物品与带入栏真的跨进程存活；②`apply` 发生在 `RunStartInitializer` **之前**（否则背包会是空的而带入栏在开局后又被"恢复"）；③自动存档没有把带入栏在开局后写回。

```text
project_manage(op="stop")
```

### 6.3 健壮性

```text
# 损坏档：把 user://save/game_save.json 写成非法 JSON 后启动
project_run(mode="custom", scene="res://scenes/main_menu_scenes/main_menu.tscn")
logs_read(source="game")     # 有明确错误、无崩溃；损坏内容已保留为 .corrupt；默认值生效

# 暂停下仍落盘
game_eval: get_tree().paused = true; 改仓库内容; SaveManager.save_now(); 读回校验
```

**门禁 4**：6.1 / 6.2 / 6.3 全部通过，且 `logs_read(source="game")` 无新增 `SCRIPT ERROR`。

### 6.4 全量门禁

```text
test_run()                                     # failed == 0，且 suites_run 含 save_system_contract
filesystem_manage(op="scan")                   # new_errors_since_last_call 不增（或逐条确认非本任务）
```

## 7. 文档

1. `docs/游戏机制与玩法内容.md`：
   - 第 217 行「等级与经验不跨运行保存」的结论**保留**（它仍然成立），补一句指向新的存档系统一节，并注明「等级/经验属局内概念，将随局内进度存档处理」，避免读者误以为整个存档系统尚未建立。
   - 新增「## 存档系统」一节：存档文件位置、存档内容范围（仓库物品 / 带入栏 / 金币 / 容量升级等级）、自动存档时机（0.5s 去抖 + 关窗兜底）、手动清档方法（删除 `user://save/game_save.json`）、以及「局内进度存档尚未实现，`data.run` 为预留落点」。
2. Phase 3.3 按 `trellis-update-spec` 把可复用的契约沉淀进 spec（候选：`.trellis/spec/frontend/state-management.md` 增加「跨运行存档的参与者协议与读档时机」小节）。
3. 本任务新增/推翻的规则若与 `AGENTS.md`、`.trellis/spec/backend/testing-guidelines.md`、`.trellis/spec/backend/quality-guidelines.md` 里仍在讲 `dotnet build` / `CUSGA.sln` 的段落冲突，在节内注明「本仓库已无 C#，该门禁无对象」，不要在本任务里大改这些文档。

## 8. 文件复查与回滚

```text
git status --porcelain
```

- 预期只多出 §0 列出的文件；运行 Godot 编辑器会改写受版本控制的文件，出现非预期改动要 `git checkout` 还原。
- 注意工作区**已存在**一处与本任务无关的改动：`M scenes/Main.tscn`（会话开始时即有）。不要把它一起提交，也不要误当成本任务引入的改动。

**回滚点 C（整体回滚）**：`git checkout -- project.godot entities/components/warehouse_inventory_component.gd core/autoloads/ItemsControl.gd core/autoloads/player_wallet.gd core/progression/player_progression.gd tests/godot/test_logic_family_contract.gd` + 删除 `core/save/`、两个新测试文件；运行期删除 `user://save/game_save.json`。（`player_level.gd` 与 `test_player_level_contract.gd` 不在改动集内，无需回滚。）

## 9. `task.py start` 前的自检

- [ ] `prd.md` / `design.md` / `implement.md` 三件套齐全，`prd.md` 的 Open Questions 为空。
- [ ] 用户已在**最终规划摘要**之后显式批准实现。
- [ ] Godot 编辑器已打开且 `editor_state.readiness == ready`。
- [ ] 基线（§1）已采集，能区分既有失败与本任务回归。
