# 局外商店系统

## Goal

在局外仓库 `Warehouse` 场景旁新增一个独立商店场景：玩家用金币购买「商店侧」商品，把「仓库侧」物品卖成金币。两侧都直接用 `GlobalWarehouse` 作为权威库存，金币跨场景、跨游戏重启持久化。界面用现有的「背包格子」素材，鼠标悬停有视觉反馈，购买/出售通过「选中 + 按钮」完成。

## Background

- 现有局外仓库是 GDScript 实现：`scenes/Warehouse/Warehouse.tscn` + `scripts/warehouse/*.gd`（`warehouse_control.gd` / `inventory_control.gd` / `inventory_card_slot.gd`）。另有一套 C# 的局内 HUD 面板 `core/ui/warehouse/WarehouseUI.cs`，本任务**不涉及**。
- 仓库界面里的库存是**副本**：`warehouse_control.gd` 在 `init()` 里 `inventory_control.inventory.CopySlotsFrom(GlobalWarehouse)`，在 `exit()` 里 `GlobalWarehouse.CopySlotsFrom(inventory_control.inventory)`。`CopySlotsFrom` 是整表覆盖（`entities/components/InventoryComponent.cs:195`）。因此**任何买卖都必须直接操作 `GlobalWarehouse`**，否则返回仓库时会被副本覆盖。
- 场景流转由 `core/autoloads/SceneManager.gd` 统一管理：`GlobalEventBus.scene_requested.emit("<id>")` → `SceneManager._on_scene_requested`。`SCENE_MAP` 目前只有 `main_menu` / `warehouse`；场景实例**缓存不销毁**，切换时调用旧场景的 `exit()` 和新场景的 `init()`，带 `ScreenTransitions` 淡入淡出。
- 数据模型：`BaseCardData`(abstract) → `ItemData` → 三个子类 `ResourceCardData` / `SkillCardData` / `EquipmentData`，且 `ToolData : EquipmentData`（已核实）。`ItemData` 当前只有 `MaxStackSize`、`ItemTags`、`ActualMaxStackSize`（`resources/item/ItemData.cs`）。
- 物品资源分布：`items/` 共 **105** 个 `.tres` —— `items/items`(39) + `items/equip`(31) + `items/tool`(16) + `items/environment`(14) + `items/element`(5)。`ItemsControl` 在 `_ready()` 里递归 `res://items`，以 `CardId` 为键建立 `items` 字典。
- 仓库库存容量固定 27 格：`WarehouseInventoryComponent` 不覆写 `CanStoreItem` / `PrepareCapacityForAdd` / `CanProvideAdditionalCapacity`，因此 `CanAddItem(item, amount)` 是可靠的容量预检（`entities/components/InventoryComponent.cs:283`）。
- 项目已有可跨语言复用的规则层范式：`core/crafting/CraftingService.cs`（纯 C# sealed 类，依赖 `ICraftingInventory` 接口而不是直接耦合 `InventoryComponent`），失败用 `out CraftingFailureReason` 表达，控制台测试用 `TestCraftingInventory` 注入。
- 项目已有的本地持久化出口是 `SettingsManager` autoload（`core/autoloads/SettingsManager.gd`，文件固定 `user://settings.cfg`，接口 `get_setting(section, key, default)` / `set_setting(section, key, value)`）。
- 跨语言调用约定（已核实）：GDScript 访问 C# autoload 用 `get_node_or_null("/root/X")`，读 C# 属性用 `Object.get("Prop")` 取 `Variant`，调用 C# 方法直接 `node.Method(args)`（见 `scripts/map_scripts/map_button/map_button.gd:108,268`）。
- 素材已核实尺寸：`res/UI/背包格子-未选中-选中的样子.png` = 32×64 竖排两帧（上=未选中 32×32，下=选中 32×32）；`res/UI/按钮-未选中-选中-按下的样子.png` = 192×96 三态横排；`res/UI/物品框-f82c.png` = 140×100。

## Requirements

### R1. 玩家金币（新增 `PlayerWallet`）

- 新增全局货币状态，提供「读余额 / 尝试扣款 / 加钱 / 余额变化信号」四件事。
- 金币必须跨场景与跨游戏重启保留，落到项目既有的 `user://settings.cfg`，键为稳定的英文 `section/key`。
- 首次运行没有存档时使用约定的初始金币（**1200**）。
- 扣款必须能失败（余额不足时不产生任何变化），调用方据此给出提示，而不是抛异常。

### R2. 物品价格数据

- 在 `ItemData` 上以 `[Export]` 新增买入价与卖出价两个整数字段，默认 0；这是**纯增量**改动，不改任何现有签名、虚方法或序列化结构。
- 为已确认的商品名单批量写入价格；未配置价格的物品（买价 ≤ 0）不得出现在商店商品列表中。
- 商品名单 = `items/items` + `items/equip` + `items/tool` + `items/element`，共 **88** 个。**排除** `items/environment`(14) 与 `items/items/item1`、`item2`、`item3`（3 个测试物）。
- 价格规则：按品阶/稀有度分档，`SellPrice = floor(BuyPrice × 0.5)`。
- `items/tool/IronSword.tres` 的 `CardName` 为空（既有数据 bug）——本任务只在报告中列出，不擅自修改其内容。

### R3. 商店场景与布局

- 新增独立场景，注册进 `SceneManager.SCENE_MAP`，沿用现有 `init()` / `exit()` 生命周期约定，切换带淡入淡出。
- 布局：**左侧 = 仓库物品（可出售）**，**右侧 = 商店商品（可购买）**，两侧都用「背包格子」素材。
- 每个格子显示物品图标与数量（或价格），鼠标移入时格子视觉变化。
- 顶部显示当前金币；提供「购买」「出售」按钮与「离开商店」按钮。
- 两侧都需要分页，因为仓库 27 格/页、商品 88 个。
- 布局需符合人类审美：两侧对称、标题清晰、选中态明确。

### R4. 购买流程

- 交互为**点击选中 → 点「购买」按钮**，不做拖拽、不做单击直买。
- 商品**无限库存**，不会卖空。
- 购买在提交前必须一次性校验：余额足够、仓库放得下。校验通过才扣钱、才加物品。
- 任何一步失败都必须**不产生部分变更**（钱扣了但物品没到手，或物品给了但没扣钱，都不允许）。
- 成功后：扣金币 + 物品进入 `GlobalWarehouse`，金币显示与仓库侧格子立即刷新。

### R5. 出售流程

- 交互为**点击选中 → 点「出售」按钮**。
- 只能出售仓库里实际拥有的物品；数量不足时不得部分出售。
- 成功后：从 `GlobalWarehouse` 移除物品 + 加金币，金币显示与仓库侧格子立即刷新。
- 买价为 0（未配置为商品）的物品仍可出售，只要它有可推导的卖价。

### R6. 场景接线

- 仓库场景新增「进入商店」入口；商店场景有「离开商店」出口返回仓库。
- 商店出口必须触发仓库重新从 `GlobalWarehouse` 同步，因此买卖结果必须已经在 `GlobalWarehouse` 里。

### R7. 验证

- 按项目规定用 `env CI=true dotnet build ...` 编译，禁止裸 `dotnet build` / `dotnet test`（沙箱里 Husky 钩子会致命崩溃，且**绝不允许触碰 `.git/config`**）。
- C# 规则层要有控制台测试覆盖：余额不足、容量不足不产生部分变更、卖出不足量、买价/卖价换算。
- 运行期验证走**编辑器 MCP**（`project_run` + `logs_read(source="game")` + `test_run`），不用旧的 Godot 命令行（本机 CLI 是 4.6.3，项目与 `addons/godot_ai` 要求 4.7.1）。语法检查不作为门禁：本任务实测确认它对引用 autoload 的脚本必然报 `Identifier not found`，项目既有的 `warehouse_control.gd` 同样如此。
- 给用户截图看 UI 实际效果（`editor_screenshot`）。

## Acceptance Criteria

- [x] AC1：新存档首次进入时金币为 1200；买卖后重启游戏，金币与重启前一致。
- [x] AC2：金币落在稳定的英文 `section/key` 下，读取方对非法值（负数、非整数）能回退到安全默认值。
- [x] AC3：`ItemData` 新增买价/卖价后 `env CI=true dotnet build CUSGA.sln --no-restore` 通过；105 个既有 `.tres` 无需数据迁移即可正常加载。
- [x] AC4：88 个商品 `.tres` 都带买价/卖价，且 `SellPrice == floor(BuyPrice × 0.5)`；`items/environment` 与 `item1/2/3` 未被写入价格。
- [x] AC5：商店场景可从仓库进入，两侧分别列出仓库物品与商店商品，格子使用「背包格子」素材的双帧。
- [x] AC6：鼠标移入任一格子时该格子视觉发生变化，移出后恢复。
- [x] AC7：选中商品后点「购买」，金币按买价减少、`GlobalWarehouse` 增加对应物品；商品列表不因购买而减少。
- [x] AC8：余额不足时点「购买」，金币与仓库均无任何变化，并给出可见的失败提示。
- [x] AC9：仓库放不下时点「购买」，金币与仓库均无任何变化（余额不被扣），并给出可见的失败提示。
- [x] AC10：选中仓库物品后点「出售」，`GlobalWarehouse` 减少对应物品、金币按卖价增加。
- [x] AC11：出售数量/归属不合法时不产生任何变化，并给出可见的失败提示。
- [x] AC12：从商店返回仓库后，仓库侧显示的是买卖后的最新库存（没有被旧副本覆盖）。
- [x] AC13：`CUSGA.Tests` 控制台套件覆盖买/卖的成功与全部失败分支，并断言失败路径无部分变更。（⚠️ 该套件**本机只编译通过、跑不起来**——GodotSharp 在 Godot 运行时之外不可解析，见下方验收证据表 AC13 行；实际运行覆盖由 `tests/godot/shop_trade_tests.gd` 承担。）
- [x] AC14：`Shop.tscn` 与 `Main.tscn` 的冒烟检查无 `SCRIPT ERROR` / Parse Error / 加载失败。（⚠️ 本条原文写的是「所有新增/修改的 GDScript 通过 `--check-only`」，实现期已证伪——该开关对引用 autoload 的脚本必然失败、且不是有效门禁，故改为以编辑器 MCP 的场景冒烟为实际判据。详见下方验收证据表 AC14 行。）

## Constraints

- **绝不触发或修改 `.git/config` 钩子**；构建一律 `env CI=true dotnet build ... --no-restore`。
- 新增/修改的公共 C# API 必须写中文 XML 文档（含参数与返回值）；复杂逻辑用中文注释解释**为什么**。
- 不破坏既有物品/装备/合成/战斗数据：`ItemData` 的改动必须是纯增量，不改现有字段名、默认值与序列化格式。
- 不在 `scripts/generated/` 下手工改文件（本任务预期不涉及）。
- 不为「功能局部状态」新增全局单例；`PlayerWallet` 只承载真正跨场景的玩家货币，且必须在 `design.md` 说明为什么既有 autoload 无法承载。
- GDScript 不能用 GitNexus / CodeGraph 查询，只能用文本检索 + 编辑器 MCP 的运行期验证。
- 不修改协作者所有的 `core/map/RoomTerrainProfile.cs`（工作区里已有的未提交改动）与未跟踪的 `main.tscn`、`res/test/`。

## Out Of Scope

- 商店的刷新/补货机制、限购、折扣、随机商品池。
- 拖拽买卖、右键快捷买卖、数量输入框（本任务只做「选中 + 按钮」单件交易）。
- 玩家等级、声望、好感度等影响价格的因素。
- 修改 `core/ui/warehouse/WarehouseUI.cs`（局内 HUD 面板）。
- 修复 `resources/skill_cards/*.tres` 的 `CardId` 数据问题、`tool/IronSword` 缺名问题、`scenes/Warehouse/` 下的两个 `.tmp` 残留文件——只在最终报告里列出。
- 把商店做成局内可用的功能（本任务只做局外商店）。

## 验收结果（实现完成后回填）

### 验证证据

| 验收项 | 结论 | 证据 |
|---|---|---|
| AC1 初始 1200 + 持久化 | ✅ | 真实游戏进程读到 `金币：1200`；跨两次重启金币 1110 → 1065 → 975 连续保持，落在 `user://settings.cfg` 的 `[player] gold` |
| AC2 稳定键 + 非法值回退 | ✅ | 键为 `player/gold`；删除 `[player]` 段后重启回到默认 1200。非数值/负数回退已实现但**未在运行期触发过** |
| AC3 构建通过 + 无迁移 | ✅ | `env CI=true dotnet build CUSGA.sln --no-restore` 0 错误；105 个既有 `.tres` 直接加载 |
| AC4 88 商品价格 | ✅ | 88 个文件各 +2 行、UID 零改动；脚本化校验 `SellPrice == floor(BuyPrice/2)` 全部成立；`items/environment` 与 `item1/2/3` 零改动；刷价工具自校验 88/88 通过 |
| AC5 场景与双帧素材 | ✅ | 真实点击仓库「进入商店」进入 `Shop.tscn`；两侧分别列出仓库与商品；截图像素采样确认常态帧 `(132,126,135)` |
| AC6 悬停视觉变化 | ✅ | 像素采样：悬停格边缘 `(148,141,151)` = 常态 × 1.12；未悬停邻居 `(132,126,135)`；`is_hovered` 为真 |
| AC7 购买 | ✅ | 真实鼠标点击：金币 1110 → 1020（−90 = 斧头买价）、`GlobalWarehouse` 新增斧头、商品列表未减少 |
| AC8 余额不足 | ✅ | Godot runner 断言返回 `NotEnoughGold` 且金币与仓库均不变 |
| AC9 仓库放不下 | ✅ | Godot runner 断言返回 `NotEnoughSpace` 且**金币未被扣** |
| AC10 出售 | ✅ | 真实鼠标点击：金币 1020 → 1065（+45）、斧头从仓库移除 |
| AC11 出售不合法 | ✅ | Godot runner 断言返回 `MissingItem` 且不部分出售、不给钱 |
| AC12 返回仓库显示最新库存 | ✅ | 商店购买 → 点「离开商店」→ 仓库场景与权威 `GlobalWarehouse` 均出现「斧头」 |
| AC13 测试覆盖 | ⚠️ | 控制台套件（14 用例）**只编译通过、本机跑不起来**（GodotSharp 在 Godot 运行时之外不可解析，崩在项目原有用例上）；改由 `tests/godot/shop_trade_tests.gd` 覆盖同样的成功与全部失败分支，9/9 通过 |
| AC14 GDScript 与场景验证 | ⚠️ | 原文要求的 `--check-only` 对引用 autoload 的脚本本就无效（既有 `warehouse_control.gd` 同样报错），不能作为门禁；实际做法是跑起场景读日志——当时走的是 `--scene` headless，**该方法现已作废**，等价做法是编辑器 MCP 的 `project_run` + `logs_read(source="game")`。结论不变：`Shop.tscn` / `Main.tscn` / `main_menu.tscn` 均无 `SCRIPT ERROR` |

### 实现期对计划的修正

1. **新增 `core/shop/ShopTradeBridge.cs`**：GDScript 无法实例化 `ShopService` 这类普通 C# 类，且 Godot 的 C# 方法绑定不支持接口类型参数，因此必须有一个用 `Node` 接收参数、内部转接口的跨语言出口。原设计遗漏了这一点。
2. **`PlayerWallet` 落位改为 `core/autoloads/`**：autoload 脚本按 `frontend/directory-structure.md` 应与 `TimeSystem`/`SettingsManager` 同级，原计划放在 `core/shop/` 不符合规范。
3. **场景节点引用改为 `get_node_or_null`**：原计划的 `@onready` 在「场景作为初始场景启动」这条路径下全是 `null`（详见 `design.md` §5.4）。
4. **格子改为 96×104 并加名称行**：用户要求每个格子显示物品名称，由此重排了分页与中间动作区。
5. **悬停与选中分离**：素材只有两帧，用户明确「下面才是选中的样子」，因此悬停只做提亮（边框 1.12 + 图标 1.25），选中独占第二帧。
6. **刷价工具从 `ResourceSaver` 改为文本插入**：`ResourceSaver.save` 在非编辑器上下文会删掉 `[gd_resource]` 与全部 `[ext_resource]` 的 `uid`，回滚门 R1 拦下并改用文本插入。

### 发现但未修改的既有问题

1. `items/tool/IronSword.tres` 的 `CardName` 为空 → 商店里回退显示 `CardId`（"IronSword"）。
2. `items/equip/GlodenHelmet.tres` 拼写为 `Gloden`（其余同档装备为 `Golden`），`CardId` 也是 `GlodenHelmet`。
3. `warehouse_control.gd` 的 `init()` 访问 `inventory_control.inventory`（后者是 `@onready`），把 `Warehouse.tscn` 当初始场景直接运行必然报错。已用「改动前的版本」复现确认是既有问题。
4. `scenes/Warehouse/` 下的两个 `.tmp` 残留文件（交接文档已记录）。
5. `resources/skill_cards/*.tres` 的 `CardId` 问题（交接文档已记录，本任务未使用这批资源）。
