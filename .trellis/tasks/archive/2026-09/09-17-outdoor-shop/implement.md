# 局外商店系统 — 执行计划

> 配套 `prd.md` + `design.md`。按顺序执行；每个阶段末尾都有验证命令与评审门。

## 阶段总览

| 阶段 | 内容 | 回滚点 | 依赖 |
|---|---|---|---|
| 0 | 前置确认（工作区、分支、构建基线） | — | — |
| 1 | C# 规则层 + 钱包（纯逻辑，可测） | R2 | — |
| 2 | 数据层：`ItemData` 价格字段 + 88 个 `.tres` 刷价 | **R1** | 阶段 1 |
| 3 | 商店场景（`.tscn` + GDScript） | R3 | 阶段 1、2 |
| 4 | 场景接线（SceneManager / 仓库入口 / 商店出口） | R4 | 阶段 3 |
| 5 | 全量验证 + 截图 | — | 全部 |

---

## 阶段 0 — 前置确认

- [ ] 0.1 确认工作区 = `C:\Users\huhu9\Desktop\Alldocument\Godot_v4.6.3-stable_mono_win64\CUSGA`，分支 `main`。
- [ ] 0.2 `git status` 记录既有未提交内容，**全程不碰**：`core/map/RoomTerrainProfile.cs`（他人改动）、`main.tscn`、`res/test/`、`.trellis/workspace/huhu9/`（本会话初始化产生）。
- [ ] 0.3 建立构建基线（改动前必须已通过，否则不是本次引入的问题）：
  ```
  env CI=true dotnet build CUSGA.sln --no-restore
  ```
- [ ] 0.4 记录 Godot 可执行文件绝对路径：
  `C:\Users\huhu9\Desktop\Alldocument\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe`

**禁止**：裸 `dotnet build` / `dotnet test`；任何触碰 `.git/config` 的操作。

---

## 阶段 1 — C# 规则层 + 钱包

### 1.1 `ItemData` 价格字段（G1）

- [ ] 在 `resources/item/ItemData.cs` 的 `ItemTags` 之后新增：
  ```csharp
  // 商店买入价；<= 0 表示该物品不在商店出售。
  [Export] public int BuyPrice { get; set; } = 0;

  // 商店卖出价；<= 0 时由 ShopService 按买价折半回退。
  [Export] public int SellPrice { get; set; } = 0;
  ```
- [ ] 中文 XML 文档 + 注释解释**为什么**默认 0（= 不出售，与既有 `.tres` 反序列化默认值天然一致，无需迁移）。

### 1.2 `IShopInventory` + `InventoryComponent` 挂接口（G2）

- [ ] 新建 `core/shop/IShopInventory.cs`（命名空间 `CUSGA.core.shop`），声明 `CanAddItem` / `AddItem` / `TryRemoveItem` / `ItemCnt`，配中文 XML 文档。
- [ ] `entities/components/InventoryComponent.cs` 类声明加接口：
  ```csharp
  public partial class InventoryComponent : Node, ICraftingInventory, IShopInventory
  ```
  **不新增、不修改任何成员**——四个方法签名已精确匹配。
- [ ] 先跑影响面确认（AGENTS.md 要求改 C# 符号前做 impact 分析）：
  - GitNexus MCP 工具本会话未接入，改用文本检索列出 `InventoryComponent` / `ItemData` 的全部引用点，并在最终报告里给出人工影响面结论与风险评级。
  - 因改动仅为「新增接口名 + 新增两个 `[Export]` 字段」，预期风险 🟢 低。
- [ ] 编译：`env CI=true dotnet build CUSGA.sln --no-restore`
- [ ] 验证：`env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

### 1.3 `ShopFailureReason` + `ShopService`（G3）

- [ ] 新建 `core/shop/ShopFailureReason.cs`（6 个值，见 `design.md` §3.3）。
- [ ] 新建 `core/shop/ShopService.cs`：
  - `CanBuy` / `TryBuy` / `CanSell` / `TrySell` / `ResolveSellPrice` / `TryBuyWithReason` / `TrySellWithReason`
  - 严格遵守 `design.md` §3.4 的**先校验后变更**步骤顺序
  - 第 8 步的退款回滚必须实现并加注释说明为什么需要（纵深防御）
  - `TryBuyWithReason` / `TrySellWithReason` 是给 GDScript 用的返回原因码版本，注释说明为什么不直接暴露 `out` 参数
- [ ] 中文 XML 文档覆盖所有公共成员（含参数、返回值、失败原因）。

### 1.4 `IPlayerWallet` + `PlayerWallet`（G4）

- [ ] 新建 `core/shop/IPlayerWallet.cs`。
- [ ] 新建 `core/autoloads/PlayerWallet.cs`（autoload 脚本按 `frontend/directory-structure.md` 归入 `core/autoloads/`，与 `TimeSystem`/`SettingsManager` 同级；命名空间 `CUSGA.core.autoloads`；对齐 `TimeSystem` 不加 `[GlobalClass]`）：
  - `[GlobalClass] public partial class PlayerWallet : Node, IPlayerWallet`
  - `SettingsSection = "player"` / `SettingsKey = "gold"` / `DefaultGold = 1200`
  - `_ready()` 缓存 `/root/SettingsManager` 并读取余额，做领域校验（null / 非整数 / 负数 → 回退 1200）
  - `TrySpend` 负数或 0 或超额 → `false` 且不变；成功则写盘并发 `GoldChanged`
  - `Add` 负数直接忽略（不减少余额），成功则写盘并发 `GoldChanged`
  - 找不到 `SettingsManager` → `GD.PushError` + 纯内存模式
- [ ] `project.godot` 的 `[autoload]` 段新增 `PlayerWallet="*res://core/shop/PlayerWallet.cs"`（放在 `SettingsManager` 之后 —— `PlayerWallet._ready()` 依赖 `SettingsManager` 已就绪）。

### 1.5 C# 测试（G5）

- [ ] 在 `tests/CUSGA.Tests/Program.cs` 顶部测试清单里注册新用例，并实现 `design.md` §8 的 13 条。
- [ ] 新增本地假对象 `TestShopInventory` / `TestWallet`（对齐既有 `TestCraftingInventory` 的写法，放在同一文件内）。
- [ ] 每条失败用例都要断言**余额与仓库数量都没变**（AC13 的核心）。

### 1.6 阶段 1 验证门

```
env CI=true dotnet build CUSGA.sln --no-restore
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj
C:\...\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --build-solutions --quit
```

- [ ] 无编译错误；测试全绿；headless `--build-solutions` 无 `SCRIPT ERROR`。
- [ ] **回滚点 R2**：若测试或 headless 失败且短时间无法定位，`git checkout` 阶段 1 的既有文件改动 + 删除新增 `core/shop/*.cs`，回到干净基线。

---

## 阶段 2 — 数据层刷价

### 2.1 写刷价工具（G6）

- [ ] 新建 `scripts/tools/apply_shop_prices.gd`（`extends SceneTree`，`_initialize()` 里执行后 `quit()`）。
- [ ] 内置 `design.md` §2 的完整规则表：5 个 element、31 个 equip（品阶 × 部位）、16 个 tool（品阶 × 类型）、36 个 items（5 档稀有度）。
- [ ] **排除名单硬编码**：`items/environment/` 整个目录 + `item1` / `item2` / `item3`。
- [ ] 卖出价统一 `int(buy / 2)`。
- [ ] 每条路径都要 `load()` 成功 + `is ItemData` 校验，失败则 `push_error` 并计入失败计数。
- [ ] 结束后打印：写入数量、跳过数量、失败数量，并断言写入数 == 88。

### 2.2 执行前检查

- [ ] `git status --short items/` 必须为空（干净），否则先停下来问用户。

### 2.3 执行

```
C:\...\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --script res://scripts/tools/apply_shop_prices.gd
```

### 2.4 **回滚点 R1** — 逐项验证（不可跳过）

- [ ] `git diff --stat items/` 应恰好 **88 个文件**变更。
- [ ] 抽查 5 个不同目录的文件 `git diff`，确认：
  - 只新增 `BuyPrice` / `SellPrice` 两行
  - `uid="..."` 头未变
  - `metadata/_custom_type_script` 未丢
  - 原有字段（`CardId` / `CardName` / `CardIcon` / `Description` / `MaxStackSize` / `ItemTags` / `ValidSlots` …）未丢
- [ ] 确认 `items/environment/` 与 `item1/2/3` **零改动**。
- [ ] 校验 `SellPrice == floor(BuyPrice / 2)` 对 88 个文件全部成立（脚本化校验）。
- [ ] **任一不满足 → 立即 `git checkout -- items/` 回滚，改用文本插入方案重做。**
- [ ] headless 冒烟确认物品仍能加载：`--headless --path . --quit-after 3`（观察无资源加载错误）。

---

## 阶段 3 — 商店场景

### 3.1 格子脚本与场景（G7）

- [ ] 新建 `scripts/shop/shop_slot.gd`，实现 `design.md` §5.3 的契约（`bind` / `clear_slot` / `set_selected` / `slot_clicked`）。
- [ ] 新建 `scenes/Shop/shop_slot.tscn`：
  - `ShopSlot (Button)` + `Icon (TextureRect)` + `Count (Label)` + `Price (Label)`
  - 三个内联 `StyleBoxTexture` 子资源指向 `res://res/UI/背包格子-未选中-选中的样子.png`，`region_rect` 按 `design.md` §5.2
- [ ] `--check-only` 校验脚本。

### 3.2 商店主场景（G8）

- [ ] 新建 `scripts/shop/shop_control.gd`，实现 `design.md` §5.4 / §5.5：
  - `PAGE_SIZE = 16`，两侧独立页码
  - 商店目录：`ItemsControl.items.values()` → 过滤 `BuyPrice > 0` → **按 `CardId` 升序**（必须显式排序并注释为什么）
  - `_read_int(item, property_name)` 助手：经 `Object.get()` 取 `Variant`，`null` → 0
  - `init()` / `exit()` / `_refresh_all()` / `_do_buy()` / `_do_sell()` / 翻页 / 选中
  - `match` 把 `ShopFailureReason` 原因码映射成中文提示
  - 原因码常量镜像 + 注释说明必须与 `core/shop/ShopFailureReason.cs` 同步
- [ ] 新建 `scenes/Shop/Shop.tscn`，节点结构按 `design.md` §5.1；所有 `Button` 用 `按钮-未选中-选中-按下的样子.png`（192×96 三态）做入口/出口/买卖按钮的 `StyleBoxTexture`。
- [ ] 所有信号连接写入 `.tscn` 的 `[connection]` 段（与 `Warehouse.tscn` 的既有做法一致），避免运行时代码里散落 `connect`。
- [ ] `--check-only` 校验 `shop_control.gd`。

### 3.3 阶段 3 验证门

```
C:\...\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --check-only --script res://scripts/shop/shop_slot.gd
C:\...\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --check-only --script res://scripts/shop/shop_control.gd
C:\...\Godot_v4.6.3-stable_mono_win64_console.exe --headless --path . --scene res://scenes/Shop/Shop.tscn --quit-after 5
```

- [ ] 无 `SCRIPT ERROR` / Parse Error / `Failed to load script`。
- [ ] **回滚点 R3**：场景问题无法快速定位时，删除 `scenes/Shop/` 与 `scripts/shop/`，回到阶段 2 结束状态。

---

## 阶段 4 — 场景接线

- [ ] 4.1 `core/autoloads/SceneManager.gd` 的 `SCENE_MAP` 加 `"shop": "res://scenes/Shop/Shop.tscn"`。
- [ ] 4.2 `scenes/Warehouse/Warehouse.tscn`：在 `InventoryControl/Panel/ButtonControl/VBoxContainer` 的 `ExitButton` **之上**插入 `ShopButton`（`text = "进入商店"`，`layout_mode = 2`，`size_flags_vertical = 3`，字号 23 —— 与同级按钮一致），并加 `[connection]` 到 `InventoryControl._on_shop_button_button_down`。
- [ ] 4.3 `scripts/warehouse/warehouse_control.gd` 新增 `_on_shop_button_button_down()` → `GlobalEventBus.scene_requested.emit("shop")`（带中文注释说明这是局外商店入口）。
- [ ] 4.4 验证：
  ```
  --headless --path . --check-only --script res://core/autoloads/SceneManager.gd
  --headless --path . --check-only --script res://scripts/warehouse/warehouse_control.gd
  --headless --path . --scene res://scenes/Warehouse/Warehouse.tscn --quit-after 5
  --headless --path . --scene res://scenes/Main.tscn --quit-after 5
  ```
- [ ] 4.5 **回滚点 R4**：`git checkout` 这三个文件的改动。

---

## 阶段 5 — 全量验证与交付

### 5.1 全量验证

- [ ] `env CI=true dotnet build CUSGA.sln --no-restore`
- [ ] `env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj`
- [ ] `--headless --path . --build-solutions --quit`
- [ ] 逐个 `--check-only` 所有新增/修改的 `.gd`
- [ ] headless 冒烟：`Shop.tscn`、`Warehouse.tscn`、`Main.tscn`、`main_menu.tscn`
- [ ] `git status` + `git diff --stat` 复核：**只**动本任务范围内的文件；`core/map/RoomTerrainProfile.cs`、`main.tscn`、`res/test/` 保持原样

### 5.2 截图（AC5 / AC6 的人工确认）

- [ ] 打开 `Shop.tscn`，用编辑器截图给用户看布局效果。
- [ ] 至少两张：默认态（无选中）+ 选中态（某个格子选中、动作区显示价格、悬停态可见）。
- [ ] 若视觉明显不达标（错位、重叠、格子过小），回到阶段 3 调整后重新截图。

### 5.3 收尾

- [ ] 运行 `trellis-check` 做质量验证（spec 合规、复用、跨层数据流、一致性）。
- [ ] 运行 `gitnexus_detect_changes` 等价的改动范围复核（MCP 未接入时用 `git diff --stat` + 人工清单）。
- [ ] `trellis-finish-work`：写 journal、提示用户提交。
- [ ] 最终报告里列出**发现但未修改**的既有数据问题：`tool/IronSword` 缺 `CardName`、`resources/skill_cards/*.tres` 的 `CardId` 问题、`scenes/Warehouse/` 下两个 `.tmp` 残留。

---

## 评审门

| 门 | 时机 | 谁 |
|---|---|---|
| G0 | `prd.md` / `design.md` / `implement.md` 写完、`task.py start` 之前 | **用户 review**（强制） |
| G1–G4 | 各阶段验证命令全绿 | 自动 |
| G5 | 阶段 1 测试套件全绿 | 自动 |
| G6 | 阶段 2 的 88 文件 diff 逐项核对 | 自动（严格） |
| G7 | 阶段 5 截图 | **用户确认视觉** |
| G8 | 最终报告 | 用户 |

## 已知不做（避免范围蔓延）

- 拖拽买卖、数量输入、限购、补货、折扣、局内商店。
- 修复上面列出的既有数据问题。
- 重构 `InventoryComponent` 或引入通用「交易系统」抽象——本任务的复用边界就是 `IShopInventory` 这一个窄接口。
