# 仓库改造与容量升级系统 — 技术设计

> 配套 `prd.md`。本文件写技术设计：边界、契约、数据流、取舍与回滚形状。

## 1. 变更切片

| 切片 | 文件 | 语言 | 说明 |
|---|---|---|---|
| 升级规则 | `core/progression/UpgradeService.cs` | C# | 纯静态规则表，无 Godot 依赖 |
| 升级状态 | `core/progression/PlayerProgression.cs` | C# | autoload，持久化 + 扣款 + 下发容量 |
| 升级枚举 | `core/progression/UpgradeKind.cs` | C# | 两个升级项 |
| 组件扩容 | `entities/components/InventoryComponent.cs` | C# | 新增公开 `SetCapacity()` |
| 商品目录 | `core/shop/ShopCatalog.cs` + `resources/shop/shop_catalog.tres` | C# / 资源 | 拖 `.tres` 即上架 |
| 目录解析 | `core/shop/ShopTradeBridge.cs`、`core/shop/ShopService.cs` | C# | 显式单价重载 + 清单构建 |
| 共享格子 | `scenes/ui/item_slot.tscn`、`scripts/ui_scripts/item_slot.gd` | GDScript | 从 `scenes/Shop/shop_slot.tscn` 迁移并改名 |
| 仓库界面 | `scenes/Warehouse/Warehouse.tscn`、`scripts/warehouse/warehouse_control.gd` | GDScript | 整场景重写 |
| 接线 | `project.godot` | 配置 | 注册 `PlayerProgression` autoload |

不使用 `scripts/generated/`。

## 2. 升级规则：`UpgradeService`

纯静态表，不依赖 Godot、不持有状态，因此任何 runner 都能验证。

```csharp
public static int  GetMaxLevel(UpgradeKind kind);
public static int  ClampLevel(UpgradeKind kind, int level);
public static int  GetValue(UpgradeKind kind, int level);          // 该等级下的容量/栏位数
public static bool IsMaxLevel(UpgradeKind kind, int level);
public static int  GetCost(UpgradeKind kind, int level);           // 已满级返回 0
public static int  GetRemainingTotalCost(UpgradeKind kind, int level);
```

| 项 | 初始 | 每级 | 上限 | 费用（索引＝升级前等级）|
|---|---|---|---|---|
| `WarehouseCapacity` | 27 | +9 | 54（3 级）| 300 / 600 / 1000 |
| `CarrySlots` | 5 | +1 | 10（5 级）| 200 / 350 / 550 / 800 / 1100 |

**为什么数值集中在 C# 而不是 GDScript**：升级按钮要显示「下一级多少钱」，规则层要判断「钱够不够扣」，两处必须用同一份数据。若 GDScript 自己写一份费用表，一旦改价就会出现「界面显示 300、实际扣 600」。

**为什么用 `ClampLevel` 而不是信任存档**：存档是玩家本机文件，可能被改成负数或超大值。所有对外入口先收窄，避免算出负容量之类的荒唐结果；实际发生收窄时记 `PushWarning`，让手改存档这件事可被发现。

## 3. 升级状态：`PlayerProgression`（autoload）

```csharp
public const string SettingsSection = "player";   // 与 PlayerWallet 共用分组，键不同

[Signal] public delegate void UpgradeChangedEventHandler(string kind, int value);

public int  GetWarehouseLevel();  public int GetWarehouseCapacity();
public int  GetWarehouseNextCost(); public bool IsWarehouseMaxLevel();
public bool TryUpgradeWarehouse();
public int  GetCarryLevel();      public int GetCarrySlotCount();
public int  GetCarryNextCost();   public bool IsCarryMaxLevel();
public bool TryUpgradeCarrySlots();
```

**为什么必须是 C# autoload**：它要**扣金币**，而扣款只能通过 `IPlayerWallet` 接口；GDScript 无法实现 C# 接口，界面也就无法安全地代它扣款。持久化走既有的 `SettingsManager`。

**为什么对 GDScript 只暴露具名方法**：GDScript 无法引用 C# 的枚举类型，传裸整数会让界面出现 `TryUpgrade(0)` 这种不可读的调用。具名方法（`TryUpgradeWarehouse` / `TryUpgradeCarrySlots`）自解释，也不需要跨语言镜像枚举值。

**依赖顺序**：`PlayerProgression._Ready()` 要调用 `GlobalWarehouse.SetCapacity()`，而后者必须在 `InventoryComponent._Ready()` 建好内部槽位数组之后。因此 `project.godot` 里 `PlayerProgression` 注册在 `GlobalWarehouse` 与 `PlayerWallet` **之后**。

### 3.1 契约：`TryUpgrade` 的固定顺序

```
1. 读当前等级
2. 已满级 → false（不扣钱）
3. 取升级费用；取不到（等级与表不一致）→ PushError + false（绝不当作免费升级）
4. 扣款：_wallet.TrySpend(cost) 失败 → false，等级原封不动
5. 等级 +1、写盘、下发仓库容量
6. 发 UpgradeChanged
```

**先校验后变更**：第 4 步失败时等级必须没动，否则会出现「没花钱却升了级」。落盘失败**不回滚**内存值，与 `PlayerWallet` 的既定契约一致（本次运行内有效，但不能声称已跨重启保存）。

### 3.2 校验与错误矩阵

| 条件 | 行为 | 结果 |
|---|---|---|
| 金币不足 | `TrySpend` 返回 false | 等级 / 容量 / 余额全不变，返回 false |
| 已满级 | 直接返回 false | 不扣钱；`GetNextCost` 返回 0 |
| 存档等级为负 / 超上限 | `ClampLevel` 收窄 + `PushWarning` | 使用合法等级继续 |
| 存档值不是数值 | 回退 0 级 + `PushWarning` | 使用默认等级 |
| 找不到 `PlayerWallet` | `PushError` | 升级一律失败，界面禁用按钮 |
| 找不到 `GlobalWarehouse` | `PushError` | 等级仍可升，但容量不下发 |
| 写盘失败 | `PushWarning` | 内存值保留，本次运行内有效 |

### 3.3 持久化策略：`PlayerDataPolicy`

```csharp
public static class PlayerDataPolicy
{
    public const bool PersistAcrossRuns = false;   // 发布时改为 true
}
```

金币在 `PlayerWallet`、等级在 `PlayerProgression`，分属两个类。开关集中一处是为了避免发布时只改一边，出现「金币存了、等级没存」的错位。

关闭时（开发期）：
- `ReadStoredGold` / `ReadLevel` 直接返回初始值，**不读存档**。
- `PersistGold` / `SaveLevel` 直接返回，**不写存档**。
- `_Ready()` 顺带调用 `erase_setting` 清掉遗留的玩家键，避免将来打开开关时把开发期随手改出来的数值当成正式存档读回来。战斗操作模式等其它偏好不受影响。

**为什么不是直接删掉持久化代码**：发布时需要它。留一个常量开关，恢复只需改一行，两边读写代码都不用动。

**副作用**：`SettingsManager.gd` 原本只有 get/set，为清键补了 `erase_setting(section, key)`（键不存在时视为成功）。它本身就是 get/set 的自然补充，不只为本次服务。

## 4. `InventoryComponent.SetCapacity`

```csharp
public void SetCapacity(int capacity);   // 只增不减；_slots 未建立时 PushError 并忽略
```

新增而不是复用 `EnsureCapacityAtLeast`（它是 `protected`）。**只增不减**是刻意的：缩容会让已有物品失去落脚点。内部 `_slots` 为 `null` 时（组件未 `_Ready`）报错忽略，避免把空引用炸在 `Array.Resize` 上。

## 5. 商品目录：`ShopCatalog`

```csharp
[GlobalClass] public partial class ShopCatalog : Resource
{
    [Export] public Godot.Collections.Array<ItemData> Goods { get; set; } = [];
    [Export] public bool AlsoIncludeEveryPricedItem { get; set; } = false;
    [Export(PropertyHint.Range, "0,999999,1,or_greater")] public int DefaultBuyPrice { get; set; } = 100;
    public bool ContainsExplicitly(ItemData item);
}
```

**目录即唯一真相**：`AlsoIncludeEveryPricedItem` 默认 **false**。开着它会让「物品自己配了买价」也变成上架条件，于是上架有两个入口、下架还得回头改物品资源。默认关闭后，商店卖什么完全由 `Goods` 决定。

> **实现期修正**：初版默认值是 `true`（用开关达到「88 件照旧上架」的效果，从而让提交目录不改变既有行为）。用户随后指出「目录里什么都没配，商店却有东西」这件事难以理解——这个困惑本身就说明双入口的设计不合理。于是改为默认 `false`，并用一次性脚本把当时的 88 件商品固化进 `Goods`，随后删掉该脚本（它会覆盖手工编辑，留着重跑是陷阱）。迁移后 `Goods` 顺序按 `CardId` 升序，与迁移前完全一致，界面无可见变化。

**为什么做成独立 `Resource`**：直接挂在场景节点上更省事，但商店数据就绑死在某个场景里，将来做第二个商人要复制整个场景。做成资源后可复用同一套上架逻辑。

**清单构建**（`ShopTradeBridge.BuildStockList`）：
1. 先按 `Goods` 的**数组顺序**加入（拖拽顺序即货架顺序，去重）。
2. 仅当 `Catalog == null` 或 `AlsoIncludeEveryPricedItem` 为真时，才把其余 `BuyPrice > 0` 的物品按 `CardId` 升序追加。

自动补入必须显式排序——`ItemsControl` 用 `DirAccess` 递归装入字典，顺序不是稳定契约。

### 5.1 价格解析（关键取舍）

```
ResolveUnitBuyPrice(item):
    item.BuyPrice > 0                          → item.BuyPrice
    否则 if 目录显式包含 item 且 DefaultBuyPrice > 0 → DefaultBuyPrice
    否则                                        → 0（不上架）

ResolveUnitSellPrice(item):
    item.SellPrice > 0        → item.SellPrice
    否则 ResolveUnitBuyPrice/2（向下取整）
```

**兜底价只对显式列出的物品生效**：若对所有买价为 0 的物品都套兜底价，商店会把环境物（树木、石壁）也一并上架。

### 5.2 规则层的显式单价重载

`TryBuy` / `CanBuy` / `TrySell` / `CanSell` 都新增 `(…, int unitPrice, …)` 重载；原签名保留并委托给它，单价取 `item.BuyPrice`。理由：兜底价是**目录**的知识，规则层不该反过来去读目录。这样既有调用方与测试完全不受影响，目录又能把解析后的价格传进来。

> 同时删除了 `ShopService.TryBuyWithReason` / `TrySellWithReason`：桥接自带价格解析后它们成了重复实现，两处各写一份 null 处理是负债。

## 6. 仓库场景

### 6.1 交互模型

**点选 + 放入/取出**，无拖拽。选中态由 `warehouse_control.gd` 单一持有（`_selected = {"side": .., "index": ..}`），两侧天然互斥。

### 6.2 数据流（重要简化）

**仓库内容直接读写 `/root/GlobalWarehouse`，不再维护界面副本。**

旧实现是「`init()` 从 GlobalWarehouse 拷入 → 界面里改副本 → `exit()` 拷回」，任何一条路径漏写回就丢改动。新实现从根本上消除这一类问题：`exit()` 只需要把带入栏导出到 `ItemsControl`。

| 时机 | 动作 |
|---|---|
| `init()` | 消费 `ItemsControl.player_to_warehouse`（局内带回）→ 清空该数组 → 全量刷新 |
| 放入 | `GlobalWarehouse.TryRemoveItem(item, 整堆数量)` → 写入带入栏内存数组 |
| 取出 | 先 `CanAddItem` 预检 → `AddItem` → 清空带入栏该位 |
| 升级 | `PlayerProgression.TryUpgrade*()` → 全量刷新 |
| `exit()` | 只把带入栏非空位导出到 `ItemsControl.warehouse_to_player(+_cnt)` |

**契约不变**：`warehouse_to_player` / `player_to_warehouse` 的形状与语义完全保持，`map_control.gd` 一行都不用改（它只按数组长度遍历，对数量无感知）。

**放入/取出的失败语义**：`TryRemoveItem` 失败时不写带入栏（不会凭空多出物品）；取出前用 `CanAddItem` 预检，放不下就拒绝，避免物品从带入栏消失却进不了仓库（等于凭空销毁）。

### 6.3 场景结构

```
scenes/Warehouse/Warehouse.tscn
└── Warehouse (Node2D)                 ← scripts/warehouse/warehouse_control.gd
    ├── Background (ColorRect 1280x720)
    └── UILayer (CanvasLayer)
        └── Root (Control, full rect, mouse_filter=IGNORE)
            ├── TitleLabel            "仓  库"
            ├── InfoLabel             "仓库 7/36　带入 6/10"
            ├── GoldLabel             "金币：700"
            ├── WarehousePanelBg (Panel)   (16,72)-(672,606)
            ├── WarehouseHeader       "我的仓库"
            ├── WarehouseGrid (GridContainer, columns=6)  6×4=24/页
            ├── WarehousePrev / WarehousePage / WarehouseNext
            ├── CarryPanelBg (Panel)       (688,72)-(1264,606)
            ├── CarryHeader           "带入游戏"
            ├── CarryGrid (GridContainer, columns=5)  5×2=10 个栏位
            ├── SelectedLabel / HintLabel
            ├── PutInButton           "放 入"   黄
            ├── TakeOutButton         "取 出"   青
            ├── UpgradeWarehouseButton  "仓库扩容 300"  青（文案随费用变化）
            ├── UpgradeCarryButton      "带入栏 +1　200" 青
            ├── SortButton            "整理背包"  青
            ├── ShopButton            "进入商店"  黄
            ├── ExitButton            "返回主菜单" 红
            └── StatusLabel
```

格子尺寸沿用商店：96×104（素材 32×32 的整数 3 倍宽、图标 64×64 为 2 倍），格子场景与商店**共用同一个** `scenes/ui/item_slot.tscn`。

**为什么每页固定 24 格**：容量升级只影响**总页数**，不影响每页格子数。因此升级后不需要重建格子视图，只刷新即可（`_slots_built` 保持 true）。这消除了「扩容后旧格子引用失效」这一类 bug。

**为什么要迁移格子场景**：仓库若 `preload("res://scenes/Shop/shop_slot.tscn")`，会让「仓库依赖一个叫 Shop 的预制体」，对后续维护者是误导。因此把 `class_name ShopSlot` 改名为 `ItemSlot` 并移到 `scripts/ui_scripts/` 与 `scenes/ui/`（对齐项目既有的 `scripts/ui_scripts/` 约定）。

### 6.4 未解锁栏位的视觉

`_fill_carry_slots()` 对 `i >= 可用栏位数` 的格子 `clear_slot()` 并 `modulate = Color(0.5, 0.5, 0.56)`。

只禁用不变暗是不够的：`clear_slot()` 走的是 `disabled` 样式，与「可用但为空」的格子外观**完全一样**，玩家看不出自己有几个栏位、也就看不出升级买到了什么。第一版实现漏了这点，截图复核时才发现。

## 7. 兼容性、风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| 升级在 `GlobalWarehouse._Ready()` 之前下发容量 | `Array.Resize` 空引用 | autoload 注册顺序 + `SetCapacity` 内的 null 守卫 |
| 兜底价把所有零价物品变成商品 | 环境物上架 | 兜底价只对目录显式列出的物品生效 |
| `TryBuy` 重载把既有调用改坏 | 既有 88 件商品行为变化 | 原签名保留并委托，既有测试全部照跑 |
| 删掉旧仓库脚本后有隐藏引用 | 场景/脚本加载失败 | 删前全仓检索引用；删后 4 场景冒烟 + 规则测试 |
| 仓库直接写权威库存 | 与商店/局内互相干扰 | 两者本就都以 `GlobalWarehouse` 为权威，方向一致 |
| 格子场景迁移漏改引用 | 商店格子加载失败 | 迁移后立即跑商店冒烟与 14 个规则测试 |

**回滚形状**：全部是新增文件 + 少量增量修改。回滚 = 删除 `core/progression/`、`scenes/ui/`、还原 `scenes/Warehouse/Warehouse.tscn`、`scripts/warehouse/warehouse_control.gd`、把格子场景移回原位、`git checkout` 其余被改文件。存档只多两个键，旧版本忽略即可，无需迁移。

## 8. 验证设计

| 层 | 手段 | 覆盖 |
|---|---|---|
| 规则 | `tests/godot/shop_trade_tests.gd`（14 用例，含 5 个目录用例）| 目录上架、兜底价、买卖分支 |
| 升级 | 运行中游戏 `game_eval` 断言 | 升级成功 / 余额不足 / 满级 / 非法等级 |
| 交互 | 真实 `InputEventMouseButton` | 点选、放入、取出、两个升级按钮 |
| 视觉 | 运行中截图 | 布局、未解锁栏位变暗、与商店风格一致 |
| 回归 | 4 场景 headless 冒烟 + 既有 runner | 删除旧脚本与场景重写无副作用 |
