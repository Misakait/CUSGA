# 大小地图生成：运行验证

日期：2026-09-27

环境：

- Godot：4.7.1-stable（官方版本）。
- 项目：CUSGA。
- 编辑器会话：`cusga@0f954027e46bb2f0`。
- 验证结束后仅停止运行中的游戏，未关闭 Godot 编辑器。

## 文件系统与静态检查

- `filesystem_manage(op="scan")` 完成，Godot 全局类表正常。
- `gdlint scripts/map_scripts/UIWorldMapCanvas.gd scripts/map_scripts/UIMiniMap.gd scripts/map_scripts/UILargeMap.gd`：通过。
- `gdformat --check` 检查以上三个新增生产脚本：通过，三个文件均无需继续格式化。
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

- 总用例：4。
- 通过：4。
- 跳过：0。
- 失败：0。

覆盖内容：

- 房间与桥生成、去重和当前房间纹理切换。
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
- 初始状态：
  - 当前坐标：`(7,6)`。
  - Model 已探索房间：1。
  - MiniMap：1 个房间、0 座桥。
  - LargeMap：1 个房间、0 座桥。
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

## 已知边界

- `RunSnapshot.save_change_signals()` 沿用现有空数组协议。房间探索和当前房间变化会进入下一次局内快照采集，但不会单独触发 SaveManager 的 0.5 秒防抖落盘；其他参与者请求保存或正常退出时会采集。是否改成每次跨房立即请求保存属于后续存档策略决定。
- 大地图的暂停协调、战斗期间显示协调、鼠标拖拽、滚轮缩放、图钉、迷雾、图例和房间内精确玩家位置不属于本轮。
- 全仓库仍有任务外历史 GDScript 风格债务。本轮只要求并确认三个新增生产 UI 脚本通过 gdlint 与 gdformat。
