# 局外商店系统 — 技术设计

> 配套 `prd.md`。本文件只写技术设计：边界、契约、数据流、取舍、兼容性与回滚形状。

## 1. 变更切片

| 切片 | 文件 | 语言 | 说明 |
|---|---|---|---|
| 规则层 | `core/shop/*.cs` | C# | 纯规则 + 接口 + 跨语言桥接节点；规则部分可在控制台测试里脱离场景树运行 |
| 数据层 | `resources/item/ItemData.cs` + 88 个 `.tres` | C# / 资源 | 纯增量新增两个价格字段 |
| 全局状态 | `core/autoloads/PlayerWallet.cs` + `project.godot` | C# | 新增 autoload |
| 表现层 | `scenes/Shop/*.tscn` + `scripts/shop/*.gd` | GDScript | 商店场景 |
| 接线 | `SceneManager.gd`、`Warehouse.tscn`、`warehouse_control.gd` | GDScript | 入口/出口 |
| 测试 | `tests/CUSGA.Tests/Program.cs` | C# | 买卖规则回归 |

不使用 `scripts/generated/`，不新增编辑器插件。

## 2. 数据层：`ItemData` 价格字段

```csharp
[Export] public int BuyPrice { get; set; }   // 买入价；<= 0 表示不出售该商品
[Export] public int SellPrice { get; set; }  // 卖出价
```

**兼容性**：纯增量。既有 105 个 `.tres` 不含这两个键，Godot 反序列化时落到 `int` 默认值 `0`，**无需数据迁移**。买价 0 恰好就是「不出售」的语义，与旧数据天然一致。

**为什么不放在单独的 catalog 资源里**：价格是物品自身的属性，Godot 检查器里逐项可调；`resource-data-guidelines.md` 明确要求「可编辑游戏数据放 `resources/**`，不要编码进管理类」。

**价格分层规则**（88 个商品 = `items/items` 36 + `items/equip` 31 + `items/tool` 16 + `items/element` 5）：

`items/element`（5）：统一 **150**。

`items/equip`（31）：`买价 = 品阶基准 × 部位系数`

| 品阶 | 基准 | | 部位 | 系数 |
|---|---|---|---|---|
| 皮革 `Leather*` | 80 | | 头盔 | 1.00 |
| 铁 `Iron*` | 240 | | 胸甲 | 1.50 |
| 金 `Golden*` / `Gloden*` | 700 | | 护腿 | 1.20 |
| | | | 鞋子 | 0.80 |
| | | | 护手 | 0.70 |
| | | | 腰带 | 0.90 |
| | | | 项链 | 1.10 |
| | | | 戒指 | 0.80 |

`items/tool`（16）：`买价 = 品阶基准 × 类型系数`（基准同上：基础工具 80 / 石 80 / 铁 240 / 金 700）

| 类型 | 系数 | 结果（基础/石、铁、金） |
|---|---|---|
| 剑 | 1.30 | 100 / 310 / 900 |
| 锤 | 1.35 | 110 / 320 / — |
| 斧 | 1.15 | 90 / 280 / 800 |
| 镐 | 1.15 | 90 / 280 / 800 |
| 长棍 | 0.90 | 70 / — / — |
| 铲子 | 0.90 | 70 / — / — |
| 钓鱼竿 | 0.90 | 70 / — / — |

`items/items`（36，已排除 `item1/2/3`）：按稀有度分 5 档

| 档位 | 买价 | 物品 |
|---|---|---|
| 凡品 | 20 | leaf branch littlerock sand snow ice powder berry apple wheat sugarcane aloe bug birdegg |
| 良品 | 60 | fish applechips applecore bakedapplecore cookedmeat roastfish processedfish deliciousfish broth fishsoup eggsoup delicioussoup leather |
| 器物 | 150 | woodenbowl stonebowl flametorch ironingot goldingot |
| 道具 | 90 | sleepingbag tent |
| 极品 | 300 | lifepotion magicpotion |

统一 `SellPrice = BuyPrice / 2` 向下取整。

**写价方式**：一次性工具脚本 `scripts/tools/apply_shop_prices.gd`（`extends SceneTree`，`--headless --script` 运行）。用 `load()` + `ResourceSaver.save()` 写回，脚本内置上面的规则表，**保留在仓库里作为可复现的来源**。
- 风险：`ResourceSaver` 会重排属性顺序并可能丢掉 `metadata/_custom_type_script`。
- **回滚点 R1**：跑完先看 `git diff --stat` 与逐个 `git diff`，确认只多了两行价格、UID 未变、`metadata` 未丢；若有损坏则 `git checkout -- items/` 回滚，改用文本插入方案。
- 执行前先 `git status` 确认 `items/` 干净。

## 3. 规则层：`core/shop/`

对齐 `core/crafting/` 的既有范式（纯 C# sealed 类 + 接口依赖 + `Try*`/失败枚举 + 控制台可测）。

### 3.1 `IPlayerWallet.cs`

```csharp
public interface IPlayerWallet
{
    int Gold { get; }
    bool TrySpend(int amount);
    void Add(int amount);
}
```

### 3.2 `IShopInventory.cs`

```csharp
public interface IShopInventory
{
    bool CanAddItem(ItemData item, int amount);
    int AddItem(ItemData item, int amount);          // 返回没放下的数量
    bool TryRemoveItem(ItemData item, int amount);
    int ItemCnt(ItemData item);
}
```

**零成员改动复用**：`InventoryComponent` 已存在这四个方法的**精确签名**（`entities/components/InventoryComponent.cs:229/283/319/365`），因此只需要在类声明上加一个接口名：

```csharp
public partial class InventoryComponent : Node, ICraftingInventory, IShopInventory
```

不新增、不修改任何成员；实体子类 `WarehouseInventoryComponent` 自动继承。

**为什么不直接复用 `ICraftingInventory`**：它的成员是够的，但名字表达的是「合成材料来源」，语义不符；且它缺少卖方向需要的 `ItemCnt`。新增一个窄接口比把一个合成语义的接口扩散到商店更清晰。

### 3.3 `ShopFailureReason.cs`

```csharp
public enum ShopFailureReason
{
    None = 0,
    InvalidItem = 1,      // 物品为空 / 没有有效价格
    InvalidQuantity = 2,  // 数量 <= 0 / 总价溢出
    NotEnoughGold = 3,    // 余额不足
    NotEnoughSpace = 4,   // 仓库放不下
    MissingItem = 5,      // 仓库里没有足够数量可卖
    NotConfigured = 6,    // 钱包或仓库未接好（跨语言入口专用）
}
```

显式数值是刻意的：GDScript 侧以具名常量镜像这份枚举，显式数值让两侧对应关系可被测试断言。`NotConfigured` 只由跨语言入口 `TryBuyWithReason` / `TrySellWithReason` 在依赖缺失时返回——C# 入口对 `null` 依赖直接 `ArgumentNullException.ThrowIfNull`（装配缺陷应当立刻暴露），但跨语言入口不能抛异常，否则 GDScript 拿不到可映射的提示，商店界面会无反馈地卡住。

对齐 `CraftingFailureReason`：`ShopService.TryBuy/TrySell` 返回 `bool` + `out ShopFailureReason`。

### 3.4 `ShopService.cs`

`public sealed class ShopService`，无 Godot 场景依赖。

```csharp
public bool CanBuy(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity = 1)
public bool TryBuy(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity, out ShopFailureReason failureReason)
public bool CanSell(IShopInventory inventory, ItemData item, int quantity = 1)
public bool TrySell(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity, out ShopFailureReason failureReason)
public static int ResolveSellPrice(ItemData item)
```

**先校验后变更（关键顺序契约）**——`error-handling.md` 要求「Avoid partial mutation on failure」。`TryBuy` 的顺序必须是：

1. 校验 `item != null && item.BuyPrice > 0` → 否则 `InvalidItem`
2. 校验 `quantity > 0` → 否则 `InvalidQuantity`
3. 用 `long` 算 `totalPrice = (long)item.BuyPrice * quantity`，溢出 `int` → `InvalidQuantity`
4. 校验 `wallet.Gold >= totalPrice` → 否则 `NotEnoughGold`（`wallet` 为 `null` 是调用方装配缺陷，入口处已 `ThrowIfNull`）
5. 校验 `inventory.CanAddItem(item, quantity)` → 否则 `NotEnoughSpace`
6. **此时才** `wallet.TrySpend(totalPrice)`；若仍失败（并发/异常）→ `NotEnoughGold`，且**尚未改动仓库**
7. `int remaining = inventory.AddItem(item, quantity)`
8. 若 `remaining > 0`（理论上第 5 步已排除）：**回滚** `wallet.Add(totalPrice)`，返回 `NotEnoughSpace`

第 8 步是纵深防御：容量预检与实际写入之间若出现不一致，钱必须退回去，绝不允许「扣了钱没拿到货」。

`TrySell` 的顺序：

1. 校验 `item != null` → 否则 `InvalidItem`
2. 校验 `quantity > 0` → 否则 `InvalidQuantity`
3. `int unitPrice = ResolveSellPrice(item)`；`unitPrice <= 0` → `InvalidItem`
4. 校验 `inventory.ItemCnt(item) >= quantity` → 否则 `MissingItem`（**不做部分出售**）
5. 用 `long` 累加 `totalGold`，溢出 → `InvalidQuantity`
6. `inventory.TryRemoveItem(item, quantity)`；失败 → `MissingItem`（**尚未加钱**）
7. `wallet.Add(totalGold)`

**`ResolveSellPrice` 的回退**：优先用 `item.SellPrice`；若 `<= 0` 而 `item.BuyPrice > 0`，回退为 `BuyPrice / 2`；两者都 `<= 0` 则返回 `0`（不可卖）。这样「可卖的默认全部配卖价」的意图即使某个 `.tres` 漏写卖价也成立。

`ShopService` 自身**无状态**，可安全复用单例实例；不注册全局单例，由商店场景 `_ready()` 里 `new` 一个。

## 4. 全局状态：`PlayerWallet`

```csharp
public partial class PlayerWallet : Node, IPlayerWallet
{
    public const string SettingsSection = "player";
    public const string SettingsKey = "gold";
    public const int DefaultGold = 1200;

    [Signal] public delegate void GoldChangedEventHandler(int gold);

    public int Gold { get; private set; }
    public bool TrySpend(int amount);   // 余额不足返回 false 且不改变 Gold
    public void Add(int amount);
}
```

**为什么必须是 C# 而不是 GDScript**：`ShopService` 依赖 `IPlayerWallet` 接口来保持可测试；GDScript 类无法实现 C# 接口。若钱包写成 GDScript，规则层就必须退化成 `Call()` 动态调用，`ShopService` 也就无法在控制台测试里注入假钱包。这是本次架构的硬约束。

**为什么可以新增这个 autoload**（`frontend/directory-structure.md` 要求先检查既有 autoload）：`GlobalEventBus`(信号总线)、`TimeSystem`(时间)、`WeatherManager`(天气)、`ItemsControl`(物品表)、`GlobalWarehouse`(仓库库存)、`SceneManager`(场景)、`ScreenTransitions`(转场)、`SettingsManager`(本地设置) —— 没有任何一个拥有**玩家货币**这个状态。货币天然跨场景（仓库、商店，未来还有合成/局内），不存在「局部拥有者」，因此新增是合理的，而不是把功能局部状态提升为全局。

**持久化**：走既有 `SettingsManager`，不自己 `ConfigFile.load`（`state-management.md` 明确禁止各场景自建文件路径）。C# 侧通过动态边界访问 GDScript autoload：

```csharp
private Node? _settingsManager;                       // 缓存，避免每次读写都查树
private Variant ReadSetting(string key, Variant fallback) =>
    _settingsManager?.Call("get_setting", SettingsSection, key, fallback) ?? fallback;
```

- 读：`_ready()` 里 `ReadSetting("gold", DefaultGold)`，**领域校验**：`null` / 非整数 / 负数一律回退 `DefaultGold`（对齐 `state-management.md` 的「领域拥有者校验后回退默认值」）。
- 写：`Add` / `TrySpend` 成功后 `Call("set_setting", ...)`；返回 `false`（落盘失败）时 `GD.PushWarning`，但**内存值保留**，当前会话继续正确——与 `SettingsManager` 的既定契约一致。
- 找不到 `SettingsManager` 时 `GD.PushError` 并退化为纯内存模式，不让游戏崩。

**autoload 注册**：`project.godot` 里 `PlayerWallet="*res://core/shop/PlayerWallet.cs"`（对齐 `TimeSystem` 的「脚本直接作为 autoload」）。

**信号语义**：`GoldChanged` 只在余额**实际变化**时发射，参数是新余额。`TrySpend` 失败不发信号。

## 5. 表现层：商店场景

### 5.1 场景结构

```
scenes/Shop/Shop.tscn
└── Shop (Node2D)                      ← scripts/shop/shop_control.gd
    ├── ShopTradeBridge (Node)         ← core/shop/ShopTradeBridge.cs（跨语言桥接，见 §3.5）
    ├── Background (ColorRect 1280x720)
    └── UILayer (CanvasLayer)
        └── Root (Control, full rect, mouse_filter=IGNORE)
            ├── TitleLabel            "商  店"
            ├── GoldLabel             "金币：1200"（右对齐）
            ├── WarehousePanelBg (Panel)
            ├── WarehouseHeader       "我的仓库（可出售）"
            ├── WarehouseGrid (GridContainer, columns=4)
            ├── WarehousePrev / WarehousePage / WarehouseNext
            ├── ShopPanelBg (Panel)
            ├── ShopHeader            "商 品（可购买）"
            ├── ShopGrid (GridContainer, columns=4)
            ├── ShopPrev / ShopPage / ShopNext
            ├── SelectedLabel         "先点选左侧的仓库物品或右侧的商品"
            ├── HintLabel             "买价 90 · 直接卖出可得 45"
            ├── BuyButton             "购 买"
            ├── SellButton            "出 售"
            ├── StatusLabel           "购买成功" / "金币不足" 等提示
            └── ExitButton            "离开商店"
```

上面是**实际节点名**，`shop_control.gd` 的 `_resolve_nodes()` 用的就是这些路径；改节点名必须同步改脚本。

布局坐标（1280×720 视口，`Root` 为整屏全锚点，故均为绝对坐标）：

| 区域 | 位置 |
|---|---|
| 标题 / 金币 | `(40,14)-(640,66)` / `(800,14)-(1240,66)` 右对齐 |
| 仓库面板 | `(16,72)-(478,606)` |
| 商品面板 | `(802,72)-(1264,606)` |
| 两侧网格 | 4 列 × 4 行，格子 96×104、间距 8 → 网格 408×440 |
| 两侧翻页 | 面板底部 `y=566..598` |
| 中间动作区 | `x=488..792`，选中名 / 提示 / 购买 / 出售 / 状态纵向排布 |
| 离开商店 | `(560,612)-(720,692)` |

中间动作区之所以是**竖向**而不是左右并排：两块面板各占 462 宽后中间只剩 314，放不下两个 160 宽的按钮加间距。

```
scenes/Shop/shop_slot.tscn
└── ShopSlot (Button, custom_minimum_size 96x104)   ← scripts/shop/shop_slot.gd
    ├── Icon       (TextureRect, 64x64 居中, stretch=keep_aspect_centered)
    ├── CountLabel (Label, 右上角, "x12"，仅出售侧显示)
    ├── NameLabel  (Label, 名称行, 超长省略号截断)
    └── PriceLabel (Label, 价格行, "买 120" / "卖 60")
```

### 5.2 格子视觉（R3 / AC5 / AC6）

**素材实测**（像素采样，不是肉眼判断）：

- `res/UI/背包格子-未选中-选中的样子.png` = 32×64，竖排两帧。上帧 `Rect2(0, 0, 32, 32)` 中心色 `#847E87`（亮度 128.8）= **未选中**；下帧 `Rect2(0, 32, 32, 32)` 中心色 `#9D97A0`（亮度 153.8）= **选中**。
- `res/UI/按钮-未选中-选中-按下的样子.png` = 192×96，实际是 **3 列颜色 × 3 行状态**，每格 64×32，**不是**交接文档所说的「三态横排」。行序 = 常态 / 悬停 / 按下；列色 = 黄（购买）/ 青（出售）/ 红（离开商店）。

**两帧要同时表达「悬停」和「选中」，必须分开**：悬停只做提亮，下帧（真正的「选中样子」）严格留给选中态。若两者共用下帧，玩家分不出自己是「正指着」还是「已经选中」。

| `Button` 状态 | StyleBox | 映射 | 说明 |
|---|---|---|---|
| `normal` | `idle` | `Rect2(0, 0, 32, 32)` | 未选中 |
| `hover` | `hover` | 同 `idle` 区域 + `modulate_color = Color(1.12, 1.12, 1.12)` | 提亮到约 (148,141,151)，夹在未选中 (132,126,135) 与选中 (157,151,160) 之间 |
| `pressed` | `selected` | `Rect2(0, 32, 32, 32)` | 选中 |
| `disabled` | `idle` | — | 空格子外观同未选中但不可点 |
| `focus` | `idle` | — | 格子是 `focus_mode = 0`，实际用不到（`Shop.tscn` 的按钮另用 `StyleBoxEmpty`，理由见下） |

**为什么 `pressed` 能安全承载选中态**：`Button.get_draw_mode()` 的优先级是 `disabled > pressed > hover > normal`，而 `toggle_mode` 打开后 `button_pressed == true` 会让 `status.pressed` 持续为真。因此**已选中的格子即使被鼠标悬停也仍画 `pressed`（下帧）**，不会被悬停样式盖成「看起来没选中」。这是整套映射成立的前提。

尺寸：格子 96×104 = 素材 32×32 的**整数 3 倍宽**；图标 64×64 = 物品图标原生 32×32 的**整数 2 倍**。整数倍缩放配合项目已设的 `default_texture_filter=0`（最近邻）才不会发虚。多出来的 8px 高度留给物品名称行。

**格子必须显示物品名称**（用户明确要求）：格子的内容是「图标 / 名称 / 价格」三行 + 右上角数量角标。名称放在图标下方（`NameLabel`），超长用省略号截断（`text_overrun_behavior = 3`）。这一条直接决定了格子高度从 96 变成 104，也决定了 4×4 的分页与中间动作区改为竖向排布。

**名称缺失的回退**：既有数据里存在 `CardName` 为空的物品（`items/tool/IronSword.tres`）。`shop_slot.gd` 的 `_resolve_display_name()` 回退到 `CardId`，让这类物品在界面上仍可辨认——留空会让玩家以为格子坏了，也会掩盖数据问题。

**按钮的 `focus` 样式必须置空**：Godot 会把 `focus` 样式**叠画在按钮之上**，若沿用同一张按钮贴图就会渲染出双重边框（实测可见）。`Shop.tscn` 里所有按钮的 `theme_override_styles/focus` 指向一个 `StyleBoxEmpty`，既消掉重影又保留键盘焦点能力。

**选中态的实现**：`toggle_mode = true` + `button_pressed`，复用主题的 `pressed` 样式，代码里不手写样式切换。**选中的是哪一个格子由 `shop_control.gd` 统一持有**（单一选中源），格子只负责显示——两侧必须互斥选中，状态存在格子里会让两个列表各持一份、必然出现「两侧同时亮着」。

### 5.3 `shop_slot.gd` 契约

```gdscript
signal slot_clicked(slot: Control)

func bind(item: ItemData, amount: int, price: int, price_kind: StringName) -> void
func clear_slot() -> void
func set_selected(selected: bool) -> void
```

- `price_kind`：`&"buy"` / `&"sell"`，决定 `Price` 标签前缀（买入侧显示「买 120」，卖出侧显示「卖 60」）。
- `amount <= 0` 时视为空格子：`Icon.texture = null`、`Count` 隐藏、`button_disabled = true`。
- 空格子不可点击，避免选中空气。

### 5.4 `shop_control.gd` 契约（对齐 `warehouse_control.gd`）

```gdscript
extends Node2D

const PAGE_SIZE := 16          # 4 列 × 4 行
var _bridge                   # ShopTradeBridge 节点（跨语言唯一出口）
var _warehouse                # /root/GlobalWarehouse
var _wallet                   # /root/PlayerWallet
# 上面三个刻意不写类型标注：声明成 Node 会让静态分析拒绝调用 Bridge 上的自定义 C# 方法，
# 项目里 map_button.gd 访问 TimeSystem 时也是这么写的。

var _warehouse_page: int
var _shop_page: int
var _selected: Dictionary      # {"side": &"shop"/&"warehouse", "index": int}

func init() -> void            # SceneManager 进入时调用
func _ready() -> void          # 直接运行 Shop.tscn 时也能看到界面
func exit() -> void            # SceneManager 离开时调用
```

**⚠️ 场景节点引用不能用 `@onready`**（实现期踩到的坑，务必保留这条约束）：

`SceneManager._ready()` 会对**初始场景**调用 `init()`（`core/autoloads/SceneManager.gd`），而那一刻该场景**还没进树**，`@onready` 变量全是 `null`。用 `--scene res://scenes/Shop/Shop.tscn` 直接跑本场景走的正是这条路径，整屏引用会集体失效。

因此 `shop_control.gd` 与 `shop_slot.gd` 都改成在用到之前用 `get_node_or_null()` 解析一次（子节点在 `instantiate()` 之后就存在，与是否进树无关）。项目的 `warehouse_control.gd` / `inventory_control.gd` 用 `@export` NodePath 也正是为了绕开这一点。

> 顺带发现的**既有**问题（非本任务引入，已用「改动前的版本」复现确认）：`warehouse_control.gd` 的 `init()` 里访问 `inventory_control.inventory`，而后者是 `inventory_control.gd` 的 `@onready`。把 `Warehouse.tscn` 当初始场景直接运行时必然报
> `Nonexistent function 'CopySlotsFrom' in base 'Nil'`。走 `main_menu → SceneManager 切换`的正常流程不会触发。

**`init()` 做四件事**：
1. `_resolve_nodes()` 解析场景节点，`_selected` 清空、两侧页码归 1。
2. 从 `ItemsControl.items` 生成商店目录：取 `values()`，经桥接 `IsPurchasable()` 过滤，按 `CardId` 升序排序（**必须显式排序**——`ItemsControl` 用 `DirAccess` 递归装入 `Dictionary`，顺序不是稳定契约，不排序会导致翻页时商品跳动）。
3. 绑定 `_wallet` 的 `GoldChanged` 信号（**先连接再刷新**，对齐 `state-management.md` 的「Connect before triggering」），刷新金币标签。
4. `_refresh_all()`：两侧格子按当前页填充，动作区复位；若选中的仓库堆叠已被卖空则清掉选中。

**`exit()`**：断开 `GoldChanged` 连接，清空 `_selected`。**不**碰 `GlobalWarehouse`——买卖已经直接写进去了。

**`_ready()` 也调一次 `init()`**：SceneManager 之后还会再调一次。`init()` 幂等，多调一次只是多刷新一遍；好处是「直接用 `--scene` 运行 Shop.tscn」也能看到完整界面，开发调试与截图都依赖这一点。

**幂等性**：`SceneManager` 会缓存场景实例并反复调用 `init()`/`exit()`，所以连接必须在 `init()` 里先 `is_connected` 判断，或在 `exit()` 里确保断开，避免重复连接导致一次变化刷新多次。格子视图另用 `_slots_built` 保证只创建一次。

### 5.5 交易流程（R4 / R5）

```
选中格子 → _selected 记录 (side, index) → 刷新动作区文案
点「购买」 → _do_buy() → _shop_service.call("TryBuy", wallet, warehouse, item, 1, <out>)
```

**跨语言调用约定**（已核实项目惯例，见 `scripts/map_scripts/map_button/map_button.gd:107-108` 的注释「经 Object.get 跨越 C# 自动加载边界」）：

- GDScript 取 C# autoload 节点：`get_node_or_null("/root/PlayerWallet")`
- 读 C# 属性：`node.get("Gold")` → 显式声明 `Variant`
- 调 C# 方法：`node.call("TrySpend", amount)`
- C# 信号：`node.has_signal("GoldChanged")` 守卫后 `connect`

**为什么必须经过一个 C# 桥接节点**（本设计在实现期修正过一次）：

1. Godot 只允许 GDScript 访问派生自 `GodotObject` 的 C# 类型，而 `ShopService` 按 `CraftingService` 的范式是**不依赖 Godot 的普通类**，GDScript 无法 `ShopService.new()`。
2. Godot 的 C# 方法绑定只支持 `GodotObject` 派生或 Variant 兼容的参数类型，**接口类型参数无法跨语言传递**，因此 `TryBuyWithReason(IPlayerWallet, ...)` 不能直接暴露。
3. GDScript 无法接收 C# 的 `out` 参数。

因此新增 `core/shop/ShopTradeBridge.cs`（`public partial class ShopTradeBridge : Node`）作为唯一的跨语言出口：它用 `Node` 接收参数、在内部转换成接口，并把失败原因以 `int` 返回。

```csharp
public bool IsPurchasable(ItemData item);
public int  GetBuyPrice(ItemData item);
public int  GetSellPrice(ItemData item);
public int  GetGold(Node wallet);
public int  GetItemCount(Node inventory, ItemData item);
public bool CanBuy(Node wallet, Node inventory, ItemData item, int quantity);
public bool CanSell(Node inventory, ItemData item, int quantity);
public int  TryBuyWithReason(Node wallet, Node inventory, ItemData item, int quantity);   // 返回 (int)ShopFailureReason
public int  TrySellWithReason(Node wallet, Node inventory, ItemData item, int quantity);
```

节点参数转换失败（传进来的不是钱包/仓库）时返回 `NotConfigured` 而不是抛异常——跨语言调用一抛异常，GDScript 只会看到一次引擎报错而拿不到可映射的提示，商店界面会在没有可见反馈的情况下卡住。

桥接节点同时也是**价格与余额的唯一读取入口**，GDScript 因此完全不需要 `Object.get()` 反射 C# 属性，把跨语言类型假设集中在了一个文件里。

`shop_control.gd` 用一个 `match` 把原因码映射成中文提示（对齐 `CraftingUI` 把 `CraftingFailureReason` 映射成中文状态文案的既有做法）。

原因码枚举值在 GDScript 侧用**具名常量**镜像（`const FAILURE_NONE := 0` …），不硬编码裸数字散落在逻辑里；并在 `shop_control.gd` 顶部注释说明「值必须与 `core/shop/ShopFailureReason.cs` 保持一致」。理由是项目已有跨语言枚举漂移的先例（`SkillTargetingType` 专门写了代码生成器），但为一个 6 值的枚举引入生成器不划算——用常量镜像 + 一条测试断言值一致即可。

### 5.6 刷新策略

**不做事件驱动的细粒度刷新**，每次交易成功后整体 `_refresh_all()`。理由：

- 仓库只有 27 格、商店目录 88 项，每页只渲染 16 个格子，重绘成本极低。
- `GlobalWarehouse` 的 `InventoryChanged` 是 C# 信号，从 GDScript 订阅需要再跨一次语言边界；而交易入口只有本脚本，它自己就知道何时该刷新。
- 对齐 `inventory_control.gd` 的既有做法（`refresh_ui()` 全量刷新）。

代价是交易的刷新粒度较粗，但换来了「不可能忘记刷新某一侧」的简单性。

## 6. 场景接线

### 6.1 `SceneManager.gd`

```gdscript
const SCENE_MAP: Dictionary = {
	"main_menu": "res://scenes/main_menu_scenes/main_menu.tscn",
	"warehouse": "res://scenes/Warehouse/Warehouse.tscn",
	"shop": "res://scenes/Shop/Shop.tscn",
}
```

### 6.2 仓库入口

`scenes/Warehouse/Warehouse.tscn` 的 `InventoryControl/Panel/ButtonControl/VBoxContainer` 里，在 `ExitButton` 上方插入 `ShopButton`（`text = "进入商店"`，字号 23，与同级一致），并加连接：

```
[connection signal="button_down" from="InventoryControl/Panel/ButtonControl/VBoxContainer/ShopButton"
            to="InventoryControl" method="_on_shop_button_button_down"]
```

`warehouse_control.gd` 新增：

```gdscript
func _on_shop_button_button_down() -> void:
	GlobalEventBus.scene_requested.emit("shop")
```

### 6.3 商店出口

`shop_control.gd` 的 `ExitButton.button_down` → `GlobalEventBus.scene_requested.emit("warehouse")`。

**时序确认**：`SceneManager._switch_to` 先 `await ScreenTransitions.fade_complete`，再调旧场景 `exit()`，再调新场景 `init()`。
- 仓库 → 商店：仓库 `exit()` 把界面副本**写回** `GlobalWarehouse`，然后商店 `init()` 读到最新库存。正确。
- 商店 → 仓库：商店 `exit()` 只断信号；仓库 `init()` 里 `inventory_control.inventory.CopySlotsFrom(GlobalWarehouse)` 覆盖界面副本，读到买卖后的库存。**这就是 AC12 成立的机制**。
- 商店 `init()` 还会重放 `ItemsControl.player_to_warehouse`（局内带出的物品）——这是仓库侧既有逻辑，商店不参与，不影响。

### 6.4 商品价格与「不出售」的边界

`BuyPrice <= 0` 的物品不进商店目录，但它们**仍可出售**（`ResolveSellPrice` 会回退到 `BuyPrice / 2`，两者都为 0 才不可卖）。因此 `items/environment` 里的「树木/石壁」如果因某种途径进了仓库，玩家依然能卖掉换钱——这符合「可卖的默认全部配卖价」的意图，且不需要给 environment 写价格。

## 7. 兼容性、风险与回滚

| 风险 | 影响 | 缓解 / 回滚 |
|---|---|---|
| `ResourceSaver` 重写 88 个 `.tres` 时丢字段 | 物品数据损坏 | 回滚点 **R1**：执行前 `git status` 确认干净，执行后逐个 `git diff` 验证；损坏则 `git checkout -- items/` 改用文本插入 |
| GDScript 读 `BuyPrice` 拿到 `null` | 商店目录为空 | 统一经 `_read_int(item, "BuyPrice")` 助手，`null` → 0；0 即「不出售」，行为安全 |
| `PlayerWallet` autoload 注册失败 | 商店拿不到钱包 | `shop_control.gd` 里 `get_node_or_null` 失败即 `push_error` 并禁用购买按钮，不崩溃 |
| 跨语言枚举值漂移 | 提示文案错位 | GDScript 用具名常量镜像 + C# 测试断言枚举值；文案错位不影响交易正确性（交易走 `TryBuyWithReason` 的返回值，不解析字符串） |
| `GoldChanged` 重复连接 | 一次变化多次刷新 | `init()` 里 `is_connected` 守卫；`exit()` 里断开 |
| 容量预检与写入不一致 | 扣钱没货 | `TryBuy` 第 8 步回滚退款（纵深防御） |
| 既有 `ItemData` 消费者受影响 | 编译/运行失败 | 纯增量改动，不改签名；靠 `dotnet build` + headless 冒烟兜底 |

**整体回滚**：本任务全部是新增文件 + 少量增量修改。回滚 = 删除新增文件、`git checkout` 那 4 个被修改的既有文件（`ItemData.cs`、`InventoryComponent.cs`、`SceneManager.gd`、`Warehouse.tscn`、`warehouse_control.gd`、`project.godot`）+ `git checkout -- items/`。无数据迁移、无持久化格式破坏（`settings.cfg` 多一个键，旧版本忽略即可）。

## 8. 验证设计

| 层 | 命令 | 覆盖 |
|---|---|---|
| 编译 | `env CI=true dotnet build CUSGA.sln --no-restore` | AC3 |
| C# 测试 | `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore` 后运行 | AC13 |
| GDScript 语法 | 逐个 `--check-only --script res://...` | AC14 |
| 场景冒烟 | `--headless --scene res://scenes/Shop/Shop.tscn --quit-after 5`、主场景、`Warehouse.tscn` | AC5 / AC14 |
| 人工 | Godot 编辑器截图商店场景 | AC5 / AC6 视觉确认 |

**C# 测试用例清单**（`tests/CUSGA.Tests/Program.cs`，用 `TestShopInventory` + `TestWallet` 假对象）：

1. 买 1 件成功：余额减 `BuyPrice`、仓库增加 1、返回 `None`。
2. 买 N 件成功：花费 `BuyPrice × N`。
3. 余额不足：返回 `NotEnoughGold`，**余额与仓库均不变**。
4. 容量不足：返回 `NotEnoughSpace`，**余额与仓库均不变**。
5. 买价 ≤ 0 的物品：返回 `InvalidItem`，无变更。
6. 数量 ≤ 0：返回 `InvalidQuantity`，无变更。
7. 大数量溢出：返回 `InvalidQuantity`，无变更。
8. 卖 1 件成功：仓库减 1、余额加 `SellPrice`。
9. 卖超过持有量：返回 `MissingItem`，**仓库与余额均不变**（不做部分出售）。
10. 无卖价但有买价：`ResolveSellPrice` 返回 `BuyPrice / 2`。
11. 买价卖价都为 0：`ResolveSellPrice` 返回 0，`TrySell` 返回 `InvalidItem`。
12. `ShopFailureReason` 的枚举名值对与 GDScript 常量镜像一致。
13. `PlayerWallet` 金额校验：`TrySpend` 负数 / 0 的行为、`Add` 负数不改变余额。
