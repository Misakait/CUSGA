# 优化背包快捷移动性能 - 实施计划

## 1. 前置检查

- [x] 进入 Phase 2 前加载 `trellis-before-dev`，重新读取 backend/frontend 相关规范。
- [x] 确认工作区只包含本任务规划文件，记录用户已有改动并避免覆盖。
- [x] 在修改每个 C# 符号前复核 GitNexus/CodeGraph 影响；当前候选符号风险均为 LOW。

## 2. TDD：批量通知回归

- [x] 在 `tests/CUSGA.Tests/Program.cs` 注册并编写“单次移动来源/目标各通知一次”测试。
- [x] 编写“批量移动多个堆叠来源/目标各通知一次”测试。
- [x] 编写“批量没有实际移动时不通知”测试。
- [x] 补充批量移动后卡组尾部空槽和容量结果断言。
- [x] 使用 Godot C# 运行时探针确认批量通知测试以预期的计数差异失败，而不是编译或环境错误。

## 3. 合并 Alt 批量通知

- [x] 在 `InventoryComponent` 内增加不扩展公开 API 的私有移动核心，用布尔参数控制是否立即发送全局通知。
- [x] 保持公共单次移动方法即时通知行为和通知顺序不变。
- [x] 让 `MoveAllMatchingStacksTo` 在循环内抑制全局通知，并在实际移动后向来源、目标各通知一次。
- [x] 用中文注释解释为什么批处理中保留 `ItemStack.OnStackChanged`、延迟 `InventoryChanged`。
- [x] 为修改的公共方法补齐参数、返回值和行为的中文 XML 文档。
- [x] 运行 Godot C# 通知探针，完成 RED -> GREEN。

## 4. 槽位绑定与结构同步

- [x] 在 `SlotUI.Bind` 增加相同索引、背包和 `ItemStack` 引用的幂等早退。
- [x] 为 `SlotUI` 及修改的公开绑定方法补齐中文 XML 文档。
- [x] 将 `InventoryUI.GenerateSlots` 改为只追加缺少视图、只删除末尾多余视图，不再清空整个网格。
- [x] 确认新增槽位仍配置共享 tooltip、Shift/Alt 处理器，并在后续 Rebind 中绑定正确栈引用。
- [x] 确认排序后引用换位会绕过早退并正确重新绑定。

## 5. 隐藏 CraftingUI 门禁

- [x] 在 `CraftingUI.OnInventoryChanged` 使用 `IsVisibleInTree()` 跳过不可见界面的配方刷新。
- [x] 添加中文注释说明 `Open` 会主动同步，因此隐藏期间无需维护 UI 投影。
- [x] 保持现有绑定、改绑、退出树解除订阅和重新打开刷新流程不变。

## 6. 验证

- [x] `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`
- [x] 尝试 `env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj`；确认仅因独立运行环境无法定位 `GodotSharp 4.6.3` 失败，并改用 Godot runtime 聚焦验证。
- [x] `env CI=true dotnet build CUSGA.sln --no-restore`
- [x] `godot-mono --headless --path . --build-solutions --quit`
- [x] `godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5`
- [x] 检查输出中没有 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或 C# 构建失败。
- [x] 临时运行时探针验证：容量不变时保留全部槽位实例；容量增长 K 只新增 K 个视图；Alt 批量来源/目标各一次全局通知；隐藏合成界面不进入详情刷新。验证后已删除全部诊断代码和 UID。

## 7. 完成前检查

- [x] 运行 `trellis-check`，核对 PRD AC1-AC13、规范、测试和跨层数据流。
- [x] 运行 GitNexus `detect_changes`；汇总等级 HIGH 来自 5 个文件的差异块映射到 21 个相邻符号，复核其 6 条受影响流程均为既有 Crafting UI 刷新链，逐符号影响仍为 LOW。
- [x] 检查 `git diff`，确保没有生产 `.gd`、`.tscn`、资源或用户无关文件改动；仅新增聚焦 Godot 测试 runner。
- [x] 未经用户明确要求不创建提交；若要求提交，一个 commit 只包含本任务修复。

## 8. Brooks 审查修正

- [x] 增加批量筛选异常回归测试，并用 Godot C# 临时探针确认 RED：首个堆叠已迁移但批次未通知。
- [x] 将筛选阶段与迁移阶段分离，确认异常发生时来源和目标均保持不变；临时探针 GREEN 后已删除。
- [x] 用 Context7 的 Godot 4.6 文档确认 `IsVisibleInTree` 与 `VisibilityChanged` 覆盖 `CanvasLayer` 祖先可见性。
- [x] 为 `CraftingUI` 增加隐藏脏标记与有效可见性恢复刷新，显式 `Open` 完整刷新后清除脏标记。
- [x] 新增持久 Godot runner，覆盖槽位实例复用、排序改绑、卡组增量扩容和父级恢复后的合成补刷新。
- [x] 重新运行完整构建、Godot runner、场景烟测和 GitNexus `detect_changes`。

## 验证结果

- 解决方案构建：通过，0 warning / 0 error。
- 测试工程构建：通过，0 warning / 0 error；新增 5 个库存通知、尾部空槽和筛选异常回归测试已纳入 runner。
- 控制台 runner：纯 `dotnet run` 在进入测试前因缺少 `GodotSharp 4.6.3` 退出，符合项目测试规范记录的环境限制。
- Godot 红绿验证：批量通知由来源/目标各 2 次降为各 1 次；筛选异常由部分迁移修正为零迁移；相同容量与扩容后的已有 `SlotUI` 实例均保持；隐藏 `CraftingUI` 不刷新且父级恢复后补刷新。
- Godot 验证：`--build-solutions` 与 `Main.tscn --quit-after 5` 均成功；仅出现未涉及资源的既有无效 UID 警告。
- 持久 UI runner：`inventory_ui_performance_tests.gd` 通过；`battle_deck_capacity_tests.gd` 继续通过。
- 格式门禁：对本任务修改的 C# 文件运行 `dotnet format --verify-no-changes`，主工程与测试工程均通过。
- GitNexus：汇总 HIGH 来自 7 个差异文件映射到 27 个相邻符号；受影响流程仍集中在 7 条既有合成刷新链，逐符号前置影响分析均为 LOW。
- 完整测试程序集反射加载尝试：Godot 进程以 139 退出，未作为成功门禁；临时加载器已删除。

## 风险文件与回滚顺序

| 文件 | 风险 | 回滚点 |
|---|---|---|
| `entities/components/InventoryComponent.cs` | 批量通知和卡组尾部空槽时序 | 恢复逐次通知实现及对应计数测试 |
| `core/ui/SlotUI.cs` | 相同绑定早退可能掩盖未发栈事件的写入口 | 移除早退，恢复总是重绑 |
| `core/ui/InventoryUI.cs` | 增量增删节点与列表/场景树顺序 | 恢复全量 `GenerateSlots` |
| `core/ui/crafting/CraftingUI.cs` | 隐藏状态与重新打开刷新 | 移除可见性门禁 |
| `tests/CUSGA.Tests/Program.cs` | 测试 runner 注册和事件计数 | 随对应行为一起回滚 |
| `tests/godot/inventory_ui_performance_tests.gd` | 主场景 UI 回归夹具 | 删除 runner 与对应 UID |
