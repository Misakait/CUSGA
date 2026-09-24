# 实施计划

## 代码范围

### 修改

- `scripts/map_scripts/UIMapWorldView.gd`：维护 3×3 活跃实例窗口，并从 Model 的资源缓存创建完整房间。
- `scripts/map_scripts/UIMapControl.gd`：接入 Model、View、Controller，保留现有兼容信号和外部注入接口。
- `scripts/map_scripts/UIMapLittle.gd`：适配当前坐标变化，不再假设旧房间已被移除。
- `scenes/map_scenes/map_control.tscn`：仅保留 `normal` 群系配置，移除新流程不需要的传送门接线，加入世界控制器。
- `scenes/map_scenes/map_env/normal/**/*.tscn`：让 `MapContainer` 传递 Node2D 位移，并让标题跟随房间根节点。
- 旧路径脚本保留为兼容包装，实际 View/Controller 实现使用 `UI` 前缀文件名。

### 新增

- `resources/map/map_scene_resource.gd`：单个地图坐标对应的纯资源配置。
- `core/map/map_world_model.gd`：地图世界状态和两级资源缓存协议。
- `scripts/map_scripts/UIMapWorldController.gd`：根据玩家世界坐标更新当前房间。
- `tests/test_seamless_map_world.gd`：覆盖资源复用、3×3 窗口、房间坐标摆放和旧流程隔离契约。

### 暂不删除或修改

- `scripts/map_scripts/map_button/map_button.gd`
- `scripts/map_scripts/DoorController.gd`
- `scripts/map_scripts/Door.gd`
- `scenes/map_scenes/map_trans_point/Transpoint.tscn`
- `scripts/map_scripts/passage_guard_controller.gd`（仅在必要时补充末尾接口，不接入新流程）

## 顺序

1. 读取并记录现有 MapControl、MapInstantiator、MapPositionCreate、Main、RoomBoardPresenter 和背景解析器的引用关系。
2. 对将要修改的 GDScript 入口执行原生引用审计；GitNexus 不可用时记录原因，不修改 C# 符号。
3. 新增 Model 和 Controller，先提供最小可运行协议。
4. 重构 View 的 3×3 活跃窗口和世界坐标摆放，保持旧公共字段和信号。
5. 修改 MapControl 场景接线，只启用 normal 群系。
6. 增加 Godot 运行时测试并修正接线/节点路径问题。
7. 先检查是否存在 `.sln`/`.csproj`；当前仓库没有 C# 项目，因此跳过 `dotnet build`。
8. 通过 Godot 4.7.1 编辑器 MCP 分别运行 `map_control.tscn` 与 `Main.tscn`，使用 `game_eval` 验证缓存和玩家跨界，再读取日志并停止运行。
9. 不再调用会导致本机编辑器断开的 `test_run(suite="seamless_map_world")`；测试脚本仅做源码契约复核，运行行为由真实场景覆盖。
10. 重新检查 Git 状态，确认没有编辑器自动改写的无关文件。

## 回滚点

- Model/Controller 可单独移除，恢复 MapControl 原有节点接线。
- View 保留旧 `current_scene`、`current_position` 和 `map_scene` 兼容字段，因此可以恢复旧显示逻辑而不影响外部调用方。
- 旧传送门脚本和资源不删除，方便逐项回退。
