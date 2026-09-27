# Journal - huhu9 (Part 1)

> AI development session journal
> Started: 2026-09-17

---

## 2026-09-27：大小地图生成与共享画布（规划）

- 创建任务 `.trellis/tasks/09-27-world-map-generation`。
- 已阅读用户提供的 `C:/Users/huhu9/Desktop/大小地图重构.txt`，仅把它作为类《空洞骑士》地图架构参考。
- 已核对用户新建的 `WorldMapCanvas.tscn`、`MiniMap.tscn`、`LargeMap.tscn`，以及 `Room.png`、`Room-With-Me.png`、`Room_Bridge.png` 三张 `16 × 16` 临时素材。
- 用户确认采用探索揭示：起始只显示起始房间，成功进入后永久加入大小地图，未探索房间不显示。
- 规划决定把探索集合放入 `MapWorldModel` 并接入 `RunSnapshot`；MiniMap 与 LargeMap 各自实例化同一 `WorldMapCanvas.tscn`，读取同一个 Model。
- 旧 `MapLittle` 保留为动态调用兼容适配器；`MapSystem/CanvasLayer`、`on_entered_room` 和无缝世界 3×3 加载协议保持不变。
- 当前仅完成 PRD、技术设计和实施计划，尚未修改产品代码或启动任务实施；等待用户审阅并明确批准最新规划。

## 2026-09-27：大小地图生成与共享画布（实现与验证）

- 用户批准后完成 `MapWorldModel` 探索集合、`room_discovered` 信号和查询/揭示接口；失败跨房不会泄露目标房间。
- `RunSnapshot` 的 `run_world` payload 增加 `discovered_rooms`，支持旧快照缺字段、重复坐标去重和损坏坐标跳过。
- `WorldMapCanvas.tscn` 通过拆分后的画布、房间模板、RoomView 与 BridgeContainer 生成房间和唯一连接桥；普通/当前房间分别使用 `Room.png` 与 `Room-With-Me.png`，左右桥用横桥、上下桥用 `Room_Bridge_V.png`，所有桥旋转为 0。
- MiniMap 与 LargeMap 各自实例化独立 WorldMapCanvas，并绑定同一个 Model；小地图裁切居中，大地图通过可配置 `open_map` 动作打开并聚焦当前房间，当前 InputMap 绑定物理 T 键。
- 旧 `MapLittle` 保留为兼容适配器，四个公开动态入口及 `MapSystem/CanvasLayer` 路径保留。
- `map_world_contract` 目标断言全部通过（6 通过、2 个运行时用例按设计跳过）；`map_ui_contract` 4 项全部通过。
- MiniMap、LargeMap 和 Main 场景均完成 Godot 4.7.1 冒烟；Main 实测从 1 房间/0 桥同步增长到两张地图各 2 房间/1 桥，大地图截图正确，快照 payload 得到两个探索坐标。
- 更新地图架构文档、《游戏机制与玩法内容》和 `.trellis/spec/backend/gameplay-system-patterns.md`；详细证据见任务目录的 `runtime-validation.md`。
- 当前改动未提交、未推送，任务保持 `in_progress`。后续若提交，必须先按 `agent.local.md` 逐文件报告并等待用户明确同意。

## 2026-09-27：大小地图交互、标记与设置页（实现与验证）

- 小地图换房使用可配置 Tween 平滑居中；实测从 `(7,6)` 进入 `(6,6)` 时触发当帧保留 `(-275,-372)`，0.08 秒时位于中间，0.28 秒后准确到达 `(-275,-308)`。
- 物理 T 键通过 `open_map` 动作打开大地图后暂停时间，关闭后只恢复打开前状态；动作名由 `UILargeMap.open_map_action` 导出，生产脚本不硬编码具体键位。
- 大地图滚轮以鼠标为中心缩放，拖拽按鼠标位移移动画布；缩放上下限、步长和拖拽阈值由 Inspector 导出。
- 图例使用可滚动列表和清楚选中态；真实鼠标连续左击与右击删除经 Model 同步到大小地图，实测两张地图标记数同时从 0→2→1。
- `MapMarkerConfig`、`MarkerController/MarkerPoint` 和场景标记接口完成；未探索房不注册，首次探索后自动注册并同步到两张地图。
- 暂停菜单参数设置页完成“地图”分类、小地图缩放、倍率显示、恢复默认和返回；实测 2.75× 即时生效并写入 `SettingsManager`，恢复默认回到 2.0×。
- 修复 `UIMapLegend` 把 `icon_max_width` 当普通属性导致的大地图运行时断点，改用 Button 主题常量覆盖；新增 Item 探索门控回归后，地图 UI 8/8、地图 Model 8 通过/2 跳过、暂停菜单 10/10 通过。
- 当前改动仍未提交、未推送；任务保持 `in_progress`，等待用户按本地协作规则决定是否提交。
- 用户最终指定大地图改为 T 键：`project.godot/open_map` 绑定物理 T，`UILargeMap.open_map_action` 导出到 Inspector，生产脚本不硬编码按键。运行时确认 M 不触发，T 可开关，并正确恢复打开前的暂停状态。

