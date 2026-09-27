# 大小地图生成：运行验证

日期：2026-09-27

环境：

- Godot：4.7.1-stable（官方版本）。
- 项目：CUSGA。
- 编辑器会话：`cusga@0f954027e46bb2f0`。
- 验证结束后仅停止运行中的游戏，未关闭 Godot 编辑器。

## 文件系统与静态检查

- `filesystem_manage(op="scan")` 完成，Godot 全局类表正常。
- 原始实现阶段的 `UIWorldMapCanvas.gd`、`UIMiniMap.gd`、`UILargeMap.gd` 静态检查通过；RoomTemplate 拆分后的最终脚本检查见本文件后续补充。
- `git diff --check`：通过。

## 编辑器测试

### map_world_contract

- 总用例：8。
- 通过：6。
- 跳过：2。
- 失败：0。
- 跳过项依赖真实运行时跨帧房间实例，已由 Main 场景运行验证覆盖。

本轮新增断言验证：

- 成功进入新房间只发一次 `room_discovered`。
- 失败、越界、非相邻、单向连接和资源缺失均不揭示房间。
- 探索集合幂等、可查询，并按 row/column 稳定排序返回副本。

### map_ui_contract

- 总用例：5。
- 通过：5。
- 跳过：0。
- 失败：0。

覆盖内容：

- 房间与桥生成、去重和当前房间纹理切换。
- `RoomsContainer → RoomTemplate → RoomView/BridgeContainer` 的职责结构。
- 默认显示通往未探索邻居的真实连接桥，以及切回旧显示策略。
- 水平桥保持原角度，纵向桥旋转 90 度。
- MiniMap 和 LargeMap 使用两个独立画布实例，生成结果一致。
- 三个地图场景接线、旧 `MapLittle` 节点与四个公开兼容入口。
- 探索坐标快照编码、解码、去重，以及损坏坐标跳过。

测试发现器每次仍报告 `test_item_room_content.gd` 无法实例化的旧解析问题。该文件不属于本任务，目标套件实际发现并执行成功；本轮新增脚本与场景运行均未出现对应加载错误。

## 场景冒烟

### MiniMap.tscn

- `res://scenes/map_scenes/map_view/MiniMap.tscn` 独立启动成功。
- `current_run_errors=[]`。
- 截图确认右上角边框、遮罩区域和裁切布局正常。
- 未绑定 Model 时保持空画布，不输出缺少 Model 的运行错误。

### LargeMap.tscn

- `res://scenes/map_scenes/map_view/LargeMap.tscn` 独立启动成功。
- `current_run_errors=[]`。
- 运行时确认 `ViewportControl/WorldMapCanvas` 存在。
- `ViewportControl.size = Vector2(1200, 656)`。
- 根节点默认隐藏，符合由 `open_map` 控制显示的约定。

### Main.tscn

- `res://scenes/Main.tscn` 启动成功，`current_run_errors=[]`。
- 原始实现阶段的初始状态：
  - 当前坐标：`(7,6)`。
  - Model 已探索房间：1。
  - MiniMap：1 个房间；当时旧策略下为 0 座桥。
  - LargeMap：1 个房间；当时旧策略下为 0 座桥。
  - 两个 WorldMapCanvas 实例 ID 不同。
  - 两张地图的当前房间纹理均为 `Room-With-Me.png`。
- 运行时选择一个真实双向连接的相邻房间，成功从 `(7,6)` 进入 `(6,6)`：
  - Model 已探索坐标为 `[(6,6), (7,6)]`。
  - MiniMap：2 个房间、1 座桥。
  - LargeMap：2 个房间、1 座桥。
  - 两张地图的新当前房间均使用 `Room-With-Me.png`。
  - MiniMap 实际位置与计算中心值均为 `Vector2(-275, -308)`。
  - LargeMap 实际位置与计算中心值均为 `Vector2(312, 40)`。
- 实际发送 M 键按下和释放：
  - `LargeMap.visible == true`。
  - 截图确认红色当前房间、绿色旧房间和唯一一座纵向桥位于大地图中心附近。
- `RunSnapshot.capture_save_data()` 运行验证：
  - Model 探索坐标为 `[(6,6), (7,6)]`。
  - payload 的 `discovered_rooms` 为 `["6,6", "7,6"]`。
- 游戏日志只有正常地图生成、房间呈现和既有地形卡输出，没有本轮引入的 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或资源加载错误。

## 2026-09-27 RoomTemplate 拆分与桥策略补充验证

- `gdlint` 与 `gdformat --check` 覆盖 `UIWorldMapCanvas.gd`、`UIWorldMapRoomsContainer.gd`、`UIWorldMapRoomTemplate.gd`、`UIWorldMapRoomView.gd`、`UIWorldMapBridgeContainer.gd`、`UIWorldMapBridgeVisibilityPolicy.gd` 和 `test_map_ui_contract.gd`：全部通过。
- `map_ui_contract` 更新为 5 个用例、53 个断言：5 通过、0 失败。覆盖 `RoomsContainer → RoomTemplate → RoomView/BridgeContainer`、默认未探索方向桥、旧策略切换、共享桥去重与方向旋转。
- MiniMap、LargeMap 与 Main 场景均重新启动成功，`current_run_errors=[]`；游戏日志没有本轮引入的脚本或资源加载错误。
- Main 起始坐标 `(7,6)` 在本次随机地图中有 3 个真实连接：MiniMap 与 LargeMap 均生成 1 个 `RoomTemplate`、3 座方向桥，当前纹理均为 `Room-With-Me.png`。
- 切换为模式 `1` 后，起始时桥数量从 3 变为 0；恢复模式 `0` 后回到 3。探索相邻 `(6,6)` 后，模式 `1` 只显示双方已探索的 1 座共享桥；模式 `0` 显示两间已探索房间的全部 5 个唯一出口桥。
- 跨房后的 5 座桥全局位置出现次数全部为 1，证明两个相邻模板没有重复绘制共享桥。小地图与大地图截图均确认房间图标、水平桥和纵桥对齐，没有明显重叠、错位或裁切异常。
- 最终策略脚本拆分完成后再次启动 Main：本次随机起始房连接掩码为 `15`，即上、右、下、左四向均连通；MiniMap 与 LargeMap 均为 1 个 `RoomTemplate`、4 座桥。切换模式 `1` 后桥数为 0，恢复模式 `0` 后桥数为 4；`current_run_errors=[]`，日志无本轮引入错误。

## 已知边界

- `RunSnapshot.save_change_signals()` 沿用现有空数组协议。房间探索和当前房间变化会进入下一次局内快照采集，但不会单独触发 SaveManager 的 0.5 秒防抖落盘；其他参与者请求保存或正常退出时会采集。是否改成每次跨房立即请求保存属于后续存档策略决定。
- 大地图的暂停协调、战斗期间显示协调、鼠标拖拽、滚轮缩放、图钉、迷雾、图例和房间内精确玩家位置不属于本轮。
- 全仓库仍有任务外历史 GDScript 风格债务。本轮最终确认 6 个地图 UI 生产脚本与 `test_map_ui_contract.gd` 均通过 `gdlint` 和 `gdformat --check`。
