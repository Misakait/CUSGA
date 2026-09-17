# 仓库改造与容量升级系统 — 执行计划与验证结果

> 配套 `prd.md` + `design.md`。本任务在用户口头批准方案与升级数值后执行，本文档在执行完成后回填实际结果。

## 阶段总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | 商店商品目录（`ShopCatalog` + 桥接解析 + 测试）| ✅ |
| 2 | 升级系统 C#（规则 / 状态 / 组件扩容 / autoload）| ✅ |
| 3 | 共享格子场景迁移（`ShopSlot` → `ItemSlot`）| ✅ |
| 4 | 仓库场景与控制器重写 | ✅ |
| 5 | 清理旧脚本 + 全量回归 + 视觉确认 | ✅ |

---

## 阶段 1 — 商店商品目录

- [x] 新建 `core/shop/ShopCatalog.cs`（`[GlobalClass]`，`Goods` / `AlsoIncludeEveryPricedItem` / `DefaultBuyPrice` / `ContainsExplicitly`）。
- [x] 新建 `resources/shop/shop_catalog.tres`，默认 `AlsoIncludeEveryPricedItem = true`（保持既有 88 件行为）。
- [x] `ShopTradeBridge` 增加 `[Export] Catalog`、`BuildStockList()`、目录感知的买/卖价解析。
- [x] `ShopService` 为买/卖各加显式单价重载；原签名委托保留；删除重复的 `*WithReason`。
- [x] `shop_control.gd` 改为把全部物品交给桥接，上架与排序规则收敛到 C# 一处。
- [x] `Shop.tscn` 把 `.tres` 接到桥接的 `Catalog` 上。

**验证**：`shop_trade_tests.gd` 从 9 个用例扩到 14 个并全过；运行中游戏把 `items/environment/tree.tres`（`BuyPrice = 0`）拖入目录后，可购买性 `false → true`、解析单价 `100`、商品数 `88 → 89`、位于第 1 位（显式顺序优先）。

**踩坑**：新建脚本的 `.uid` 需要一次编辑器扫描才会进 Godot 的 UID 缓存，否则 `.tres` 会报 `invalid UID` 警告（会回退到文本路径，功能正常但输出有噪音）。跑一次 `--headless --editor --quit` 即可。

---

## 阶段 2 — 升级系统（C#）

- [x] `core/progression/UpgradeKind.cs`。
- [x] `core/progression/UpgradeService.cs`（纯静态规则表 + `ClampLevel`）。
- [x] `core/progression/PlayerProgression.cs`（autoload：读取等级、扣款、写盘、下发容量、发信号）。
- [x] `InventoryComponent` 新增公开 `SetCapacity()`（只增不减 + 未初始化守卫）。
- [x] `project.godot` 注册 `PlayerProgression`，位置在 `GlobalWarehouse` 与 `PlayerWallet` 之后。

**验证（运行中游戏 `game_eval` 断言）**：

| 用例 | 结果 |
|---|---|
| 初始状态 | 仓库 27 / 等级 0 / 带入栏 5；下一级费用 300 与 200 |
| 升仓库 | 容量 27 → **36**、金币 −300、下一级费用 300 → 600 |
| 升带入栏 | 5 → **6**、金币 −200 |
| 余额不足 | 返回 false，容量 36 → 36、等级 1 → 1、零副作用 |
| 连升到满级 | 等级 [2, 3]、容量 **54**、`IsWarehouseMaxLevel = true`、下一级费用 0、再升返回 false |
| 持久化 | `user://settings.cfg` 写入 `warehouse_level=3`、`carry_level=1`、`gold=98399` |

**踩坑**：验证过程写脏了玩家存档，验证后已复位为 `gold=1200 / level=0 / level=0`。

---

## 阶段 3 — 共享格子场景迁移

- [x] `scripts/shop/shop_slot.gd` → `scripts/ui_scripts/item_slot.gd`（`class_name ShopSlot` → `ItemSlot`）。
- [x] `scenes/Shop/shop_slot.tscn` → `scenes/ui/item_slot.tscn`（节点名与脚本路径同步）。
- [x] `shop_control.gd` 更新 preload 路径、类型标注与常量名（`SHOP_SLOT_SCENE` → `ITEM_SLOT_SCENE`）。
- [x] 跑一次编辑器扫描注册 `ItemSlot` 全局类。

**为什么迁移**：仓库要复用这个格子，若让仓库 `preload("res://scenes/Shop/shop_slot.tscn")`，等于「仓库依赖一个叫 Shop 的预制体」，对后续维护者是误导。

**验证**：迁移后商店场景冒烟通过、14 个规则测试通过。

**踩坑**：`git mv` 在目标目录不存在时会直接失败（不会自动建目录），需要先建目录或改用普通移动。

---

## 阶段 4 — 仓库场景与控制器重写

- [x] `scenes/Warehouse/Warehouse.tscn` 整场景重写（保留原场景 UID `uid://dvu0wpxmytvk7`）。
- [x] `scripts/warehouse/warehouse_control.gd` 整文件重写。
- [x] 取消界面库存副本，直接读写 `/root/GlobalWarehouse`。
- [x] 保留 `ItemsControl.warehouse_to_player` / `player_to_warehouse` 契约，`map_control.gd` 零改动。

**验证（真实鼠标事件，运行中的游戏）**：

| 操作 | 结果 |
|---|---|
| 点仓库「鱼 ×8」| 选中态点亮，标签显示 `鱼 × 8`，放入可用 / 取出禁用 |
| 点「放入」| 带入栏出现鱼 ×8、仓库数量 10 → 9、状态「已放入带入栏」|
| 点带入栏鱼 → 点「取出」| 鱼 ×8 回仓库、带入栏清空、状态「已取回仓库」|
| 点「仓库扩容」| 容量 27 → 36、金币 −300、按钮费用 300 → 600、分页 1 → 1/2 |
| 点「带入栏 +1」| 5 → 6、金币 −200、按钮费用 200 → 350 |
| 未解锁栏位 | `modulate` 前 6 个 = 1.00、后 4 个 = 0.50，截图可见明显变暗 |

**踩坑（截图复核才发现）**：第一版把超出可用数量的带入栏位只做 `clear_slot()`（禁用），而禁用样式与「可用但为空」的外观完全一样，玩家看不出自己有几个栏位、也就看不出升级买到了什么。补上 `modulate` 压暗后才成立。

---

## 阶段 5 — 清理与全量回归

- [x] 删除 4 个已失去引用的旧仓库脚本（含 `.uid`）：`inventory_control.gd`、`inventory_grid.gd`、`inventory_card_slot.gd`、`inventory_user_card_slot.gd`。
- [x] 删除 `CUSGA.csproj.old` / `.old.1`（Godot 重写 csproj 前的机器备份），并在 `.gitignore` 加 `CUSGA.csproj.old*`。

### 验证结果

| 检查 | 结果 |
|---|---|
| `env CI=true dotnet build CUSGA.sln --no-restore` | 0 错误 |
| headless 冒烟 `Warehouse.tscn`（Godot 4.7.1）| 无 `SCRIPT ERROR` |
| headless 冒烟 `Shop.tscn` | 无 `SCRIPT ERROR` |
| headless 冒烟 `Main.tscn` | 无 `SCRIPT ERROR` |
| headless 冒烟 `main_menu.tscn` | 无 `SCRIPT ERROR` |
| `tests/godot/shop_trade_tests.gd` | 14/14 通过 |
| `tests/godot/battle_deck_capacity_tests.gd`（既有）| 通过 |
| 删除旧脚本后重跑上述全部 | 全部仍通过 |

### 交付后仍需注意

1. `tests/godot/shop_trade_tests.gd` 按用户要求**保留在本地、不提交**。注意仓库里其它 Godot runner 都是提交进版本控制的，这一条是例外。
2. 运行中的 Godot 编辑器会把 `.cs` 缩进从空格改成 Tab（违反 `.editorconfig` 的 `indent_style = space`）。用户已确认不再处理，照常提交即可。
3. `.trellis/spec/frontend/` 下三份规范（SceneManager 时序、Button 悬停/选中陷阱、本机验证工具链边界）已更新，属于本任务沉淀的经验。
