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
- 第一阶段当时使用横桥旋转 90 度显示纵桥；第二阶段已改为 `Room_Bridge_V.png` 且旋转为 0，须以第二阶段验证结果为准。
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
- 实际发送当时的 `open_map` 绑定键按下和释放；当前配置已经改为物理 T 键，并在后续补充验证中重新确认：
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

### 2026-09-27 第二阶段最终验证

- 新增地图标记、拖拽缩放、输入动作暂停、小地图 Tween、地图设置页与暂停菜单切页后，`git diff --check` 通过。
- 对本轮新增的 10 个地图与设置脚本执行 `gdlint`：0 个问题；`gdformat --check`：10 个文件均无需重排。
- 全量受影响脚本 lint 仍报告项目既有的定义顺序，以及 `item_view.gd` 既有 PascalCase 公共协议命名；本轮没有重命名这些兼容接口。
- Godot 编辑器 `filesystem_manage(op="scan")` 完成，全局类表稳定。
- 最终目标套件：`map_world_contract` 8 通过、2 跳过、0 失败；`map_ui_contract` 8 通过、0 失败；`pause_menu_contract` 10 通过、0 失败。
- `map_ui_contract` 新增 Item 标记回归：真实 `Item.tscn` 保留 `MarkerController/MarkerPoint` 与脚本接线；未探索房不注册，探索后注册一次，重复房间身份不重复，来源节点释放后 Model 仍保留记录。
- `MiniMap.tscn`、`LargeMap.tscn`、`option_panel.tscn`、`pause_menu.tscn` 独立启动均为 `current_run_errors=[]`；未绑定 Model 时保持安全空状态。
- `open_map` 输入动作使用真实按下/释放事件验证：原本未暂停时打开后 `paused=true`、关闭后 `paused=false`；原本已暂停时打开和关闭后仍保持 `paused=true`。当前 InputMap 已改为物理 T 键，生产脚本只读取 Inspector 导出的动作名。
- 小地图 Tween 实测从 `(7,6)` 进入 `(6,6)`：初始 `(-275,-372)`，事件当帧位置不变，`0.08 秒` 时为 `(-275,-360.155...)`，`0.28 秒` 完成后为 `(-275,-308)`，与计算中心完全一致。
- 大地图缩放请求低于和高于范围时分别夹取为 `0.5` 和 `4.0`；缩放完成后的拖拽起点为 `(197.75,14.5)`，鼠标从 `(300,260)` 移到 `(390,320)` 后画布移动 `(90,60)`，与鼠标位移一致。
- 真实鼠标连续左击两个位置后，大小地图 `PinesContainer` 都生成 `2` 个标记；在第一个位置右击释放后，两者同步降为 `1`。
- 运行时直接检查四向桥：上/下纹理均为 `Room_Bridge_V.png`，左/右纹理为 `Room_Bridge.png`，四座桥旋转全部为 `0`。
- 设置页把小地图缩放从 `2.0` 改为 `2.75` 时，运行中的 MiniMap 和内部画布即时同步；恢复默认后回到 `2.0`。暂停菜单切换主面板、设置页和返回时始终保持暂停。
- 大地图截图确认左侧地图视口、右侧固定宽度图例、滚动选项、绿色/蓝色图标、选中按下态与状态文字清楚，没有明显重叠或裁切。设置页截图确认标题、返回、地图分类、滑条、当前倍率和恢复默认布局清楚。
- 最终 Main 当前 run 日志只有正常地图生成和房间呈现输出，没有本轮引入的 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或资源加载错误。

### 2026-09-27 大地图输入改为 T 键

- `project.godot` 的 `open_map` 已从物理 M 键改为物理 T 键。
- `UILargeMap.open_map_action` 已导出到 Inspector，默认值为 `open_map`；生产脚本只调用 `event.is_action_pressed(open_map_action)`，没有 `KEY_T`、物理键码或其他具体按键判断。
- 静态检查：`UILargeMap.gd` 与 `test_map_ui_contract.gd` 通过 `gdlint` 和 `gdformat --check`；`git diff --check` 通过。
- Godot 4.7.1 运行时真实键盘事件验证：
  - 初始大地图隐藏时发送 M，大地图仍保持隐藏，证明 M 已不再触发 `open_map`。
  - 发送 T 后大地图显示且 `SceneTree.paused=true`。
  - 打开前已经暂停时，再次发送 T 关闭大地图后仍保持暂停。
  - 运行时先明确设置 `SceneTree.paused=false`，发送 T 打开后暂停，再次发送 T 关闭后恢复 `SceneTree.paused=false`。
- 编辑器测试运行器仍缓存着修改前的 `test_map_ui_contract.gd`，因此单独重跑新断言时显示旧文案“必须绑定物理 M 键”。磁盘测试源码和全新游戏进程均已验证为 T；这是 Godot 测试运行器返回的预加载缓存限制，不是生产实现失败。按项目规则没有关闭编辑器清理缓存。

- `RunSnapshot.save_change_signals()` 沿用现有空数组协议。房间探索和当前房间变化会进入下一次局内快照采集，但不会单独触发 SaveManager 的 0.5 秒防抖落盘；其他参与者请求保存或正常退出时会采集。是否改成每次跨房立即请求保存属于后续存档策略决定。
- 地图迷雾、购买地图或长椅揭示、专用商店/收集品规则，以及指南针精确玩家位置仍不属于本轮。
- 全仓库仍有任务外历史 GDScript 风格债务。本轮最终确认新增地图与设置脚本及 `test_map_ui_contract.gd` 通过 `gdlint` 和 `gdformat --check`。
- 测试发现器仍报告任务外旧文件 `test_item_room_content.gd` 无法实例化；三个目标套件均正常发现并通过，本任务所有独立场景和 Main 当前运行也没有对应加载错误。
