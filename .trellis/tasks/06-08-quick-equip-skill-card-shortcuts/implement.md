# 快捷装备与技能卡交互 Implementation Plan

## Checklist

- [x] 在 `tests/CUSGA.Tests/Program.cs` 添加组件级快捷移动和快速装备测试。
- [x] 运行测试项目编译，确认新增测试因缺少目标 API 失败。
- [x] 在 `InventoryComponent` 添加无替换快捷移动和批量移动方法。
- [x] 在 `EquipmentComponent` 添加快速选择装备槽并从背包装备的方法。
- [x] 在 `SlotUI` 添加 Shift / Alt 左键输入识别与回调。
- [x] 在 `InventoryUI` 绑定槽位快捷回调并按来源执行技能卡/装备操作。
- [x] 运行 `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`。
- [x] 运行 `env CI=true dotnet build CUSGA.sln --no-restore`。
- [x] 如 Godot 可用，运行相关 headless 编译或脚本检查。
- [x] 运行 `gitnexus_detect_changes` 检查影响范围。

## Validation Commands

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
env CI=true dotnet build CUSGA.sln --no-restore
godot-mono --headless --path . --build-solutions --quit
```

## Risk Points

- `SlotUI._GuiInput` 必须只响应左键按下，避免破坏拖拽开始事件。
- 批量移动扫描来源槽时，容量和槽内容会变化，循环必须使用当前槽状态。
- 快速装备替换目标槽时必须保留现有 `EquipFromInventory` 的替换回源格语义。

## Verification Results

- `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`：通过。
- `env CI=true dotnet build CUSGA.sln --no-restore`：通过。
- `godot-mono --headless --path . --build-solutions --quit`：通过；退出时仍有 Godot RID/ObjectDB 泄漏警告。
- `godot-mono --headless --path . --script res://tests/godot/battle_deck_capacity_tests.gd`：通过；资源 UID fallback 警告为既有资源导入问题。
- `godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5`：通过；资源 UID fallback 警告为既有资源导入问题。
- `env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj`：未作为通过门禁；本地缺少 `GodotSharp, Version=4.6.3.0` 运行时程序集，属于当前环境限制。
- `git diff --check`：通过。
- `gitnexus_detect_changes`：完成；报告 critical 是因为长文件插入导致行号级 touched 过度归因，实际 diff 只新增快捷操作 API、UI 分发和测试。

## Spec Update Judgment

本任务复用了既有 `InventoryUI`/`SlotUI`/`EquipmentComponent` 分层和测试模式，没有引入新的跨项目规范、资源格式或命令/API 契约。具体快捷键行为已经由本任务 PRD、设计和测试记录，不需要更新 `.trellis/spec/`。
