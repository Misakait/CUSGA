# 优化背包快捷移动性能 - 技术设计

## 1. 设计目标

在不改变公开快捷移动行为和现有 `InventoryChanged` 对外契约的前提下，消除三类浪费：

1. 普通移动后所有槽位重复解除/连接 `ItemStack.OnStackChanged` 并刷新视觉。
2. 出战卡组扩容时释放并重新实例化全部槽位节点。
3. Alt 批量移动按物品堆叠数重复触发来源与目标背包的全局通知。

同时阻止不可见的 `CraftingUI` 因背包变化重新计算配方和重建材料行，并保证重新打开时显示当前库存状态。

## 2. 当前数据流

```text
SlotUI Shift/Alt 输入
  -> InventoryUI.HandleSlotShortcut
  -> TryMoveStackToFirstAvailableSlot / MoveAllMatchingStacksTo
  -> target.MoveItemFrom
  -> 两个 ItemStack.OnStackChanged（局部视觉已更新）
  -> source.InventoryChanged（来源网格全量 Bind）
  -> target.InventoryChanged（目标网格全量 Bind）
```

Alt 路径在循环内重复执行整条单次移动链。出战卡组容量变化时，`InventoryUI.GenerateSlots` 又会释放并重建目标网格的所有节点。

## 3. 目标数据流

### 3.1 单次快捷移动

```text
移动两个稳定的 ItemStack 内容
  -> 两个 ItemStack.OnStackChanged 立即更新来源/目标槽位
  -> 来源与目标各发送一次 InventoryChanged
  -> UI 扫描槽位引用
       - 引用未变：Bind 直接返回
       - 排序导致引用换位：只重新绑定换位槽位
       - 容量增加：只追加缺少的槽位节点
```

保留全局 `InventoryChanged`，因为合成、仓库等订阅者仍需要知道库存整体发生过变化。优化集中在避免订阅者重复做结构性工作。

### 3.2 Alt 批量移动

`MoveAllMatchingStacksTo` 使用私有的“是否立即通知”移动核心：

- 第一遍只执行调用方提供的筛选条件并记录匹配索引；全部筛选成功后才进入迁移循环，避免条件异常留下未通知的部分迁移。
- 公共 `TryMoveStackToFirstAvailableSlot` 和 `MoveItemFrom` 继续保持现有即时通知语义。
- 批量循环调用不立即发送全局通知的私有路径。
- `ItemStack.OnStackChanged` 仍逐个触发，因此当前可见槽位内容不会失去同步。
- 只要至少移动了一个物品，循环结束后按原顺序向来源和目标各发送一次 `InventoryChanged`。
- 批次结束时目标背包执行一次尾部空槽保证，卡组扩容后的最终结构一次性同步到 UI。

该设计不新增公开事件类型，也不要求仓库、合成或其他订阅者迁移。

### 3.3 槽位绑定幂等化

`SlotUI.Bind` 在以下三项全部相同时直接返回：

- 槽位索引；
- `InventoryComponent` 实例；
- `ItemStack` 实例。

`ItemStack` 内容只能通过会触发 `OnStackChanged` 的方法修改，因此相同引用不需要再次刷新。排序会改变索引对应的 `ItemStack` 引用，仍会进入完整解绑/绑定逻辑。

### 3.4 槽位节点增量同步

保留 `InventoryUI.GenerateSlots` 私有入口，但把行为改为同步目标数量：

- `slotViews.Count < Capacity`：只实例化差额并完成 tooltip、快捷处理器的一次性配置。
- `slotViews.Count > Capacity`：只从末尾解除并释放多余视图。
- 数量相等：不创建或释放节点。

现有 `inventory_ui.tscn` 的背包与卡组网格没有静态占位子节点；生成节点均由对应 `slotViews` 列表持有，因此可以安全地增量维护。

### 3.5 隐藏合成界面

`CraftingUI.OnInventoryChanged` 首先使用 `IsVisibleInTree()` 判断当前节点是否真实可见：

- 不可见时只设置 `_needsInventoryRefresh`，不计算配方、不修改控件、不释放或创建材料行。
- 可见时保持现有 `RefreshSelectedRecipe` 行为。
- `VisibilityChanged` 在节点因自身或可见祖先发生有效可见性变化时触发；恢复可见且存在脏状态时只补做一次刷新。
- `Open` 仍主动完整刷新，并在 `Show` 前清除脏状态，避免自身重新显示时重复刷新。

选择可见性门禁和单个脏状态，而不是关闭时反复解除/重连背包信号，避免遗漏重连。Godot 的 `is_visible_in_tree()` 会同时考虑节点自身、场景树状态和 `CanvasLayer`/`CanvasItem` 可见祖先；`visibility_changed` 也覆盖树中有效可见性变化：https://docs.godotengine.org/en/4.6/classes/class_canvasitem.html

## 4. 兼容性

- 不改变 `InventoryChanged` 信号名称、参数或单次移动的通知次数和顺序。
- 不改变 `TryMoveStackToFirstAvailableSlot`、`MoveAllMatchingStacksTo`、`MoveItemFrom` 的公开签名。
- 不改变 `ItemStack` 的复制、堆叠或事件模型。
- 不改变卡组保留尾部空槽、普通背包固定容量、拖拽和装备快捷移动规则。
- 不修改生产 `.gd`、`.tscn` 或资源文件；新增一个聚焦的 Godot GDScript 测试 runner。

## 5. 测试策略

### 自动化回归

- 在 `tests/CUSGA.Tests/Program.cs` 先增加失败测试，证明：
  - 单次跨背包移动使来源与目标各通知一次；
  - 批量移动多个堆叠后来源与目标各只通知一次；
  - 没有实际移动时不发送批量通知；
  - 批量加入卡组后仍保留尾部空槽且数量正确；
  - 筛选条件抛异常时没有部分迁移或通知缺口。
- 保留并运行已有快捷移动、批量筛选、卡组扩容和普通背包容量测试。

### UI 与运行时验证

- `tests/godot/inventory_ui_performance_tests.gd` 在真实 `Main.tscn` 中记录槽位实例 ID，验证普通刷新保持节点、卡组扩容只追加节点、排序后引用正确改绑。
- 同一 runner 隐藏 HUD `CanvasLayer` 后修改库存，验证隐藏期间不重建材料行，父级恢复后材料数量补刷新。
- 使用 Godot headless 构建 C# 解决方案并烟测 `Main.tscn`，检查 C# 脚本加载、UI 场景绑定和运行时错误。

## 6. 风险与回滚

### 风险

- 批量路径延迟全局通知后，必须保证目标卡组最终仍执行尾部空槽扩容。
- `SlotUI.Bind` 早退依赖 `ItemStack` 所有内容变更都会发送 `OnStackChanged`；当前 `ItemStack` 的写入口符合该约束。
- UI 容量减少当前没有业务入口，但增量删除逻辑仍需正确解除旧栈订阅并只删除末尾视图。
- `CraftingUI` 的脏状态必须在显式 `Open` 或有效可见性恢复后清除，避免漏刷新或重复刷新。

### 回滚点

- 数据层通知合并可独立回滚 `InventoryComponent.cs` 和对应测试。
- 槽位幂等/增量同步可独立回滚 `SlotUI.cs`、`InventoryUI.cs`。
- 合成界面门禁可独立回滚 `CraftingUI.cs`。

## 7. 影响分析

GitNexus 对拟修改符号的上游影响均为 LOW：

- `SlotUI.Bind`：未识别到跨模块上游流程。
- `InventoryUI.GenerateSlots`：3 个直接调用点，仅影响 Inventory UI 流程。
- `InventoryComponent.MoveAllMatchingStacksTo`、`TryMoveStackToFirstAvailableSlot`、`MoveItemFrom`：仅影响 Components 模块内现有快捷移动调用。
- `CraftingUI.BindCrafting`、`Close`、`DisconnectInventorySignal`：仅影响 Crafting UI；最终设计无需修改这些方法，只在变更回调增加可见性门禁。

GitNexus 索引落后一个只包含 Trellis 工具更新的提交；按项目命令刷新时依赖下载超时。相关 C# 源码未落后，CodeGraph 当前 C# 索引正常。
