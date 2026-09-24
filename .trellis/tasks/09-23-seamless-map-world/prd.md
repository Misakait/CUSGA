# 无缝地图房间衔接

## 目标

将 `MapControl` 从“通过传送点移除旧房间、加载新房间”改造成“缓存已生成地图对应的场景资源，并把当前房间与八邻域中的有效完整场景摆放在同一个连续世界中”。玩家继续使用现有 WASD 移动，在房间边界处自然走入相邻房间。

## 需求

- 保持现有地图生成规则和 `MapPositionCreate` 的坐标生成结果。
- 当前只启用 `normal` 生态群系；每个房间继续使用现有瓦片地图场景。
- 同一个地图坐标只创建一份 `MapSceneResource`；同一路径只缓存一份 `PackedScene`。
- View 只保留当前房间与八邻域中的有效房间实例，3×3 窗口外的完整场景节点必须释放。
- 返回已访问坐标时，必须复用该坐标的 `MapSceneResource` 和共享的 `PackedScene`，再创建新的运行时节点。
- 新流程不能通过传送点切换地图，不能修改玩家位置，不能播放地图切换过场。
- 玩家跨房间时不触发旧的通道驻守战斗，不扣除地图移动行动值。
- 玩家不得从地形边缘、无桥桥口或窄桥侧边进入空白世界；有效桥向允许沿桥中心连续跨入相邻房间。
- `Boundary` 是 Ground 常设地形边界，始终不随 Bridge 状态切换。
- `BridgeWithBoundary` 在无桥方向保留桥口阻挡；存在桥时关闭阻挡桥口的边界，使桥中心保持可通行。
- `BridgeBoundary` 只阻挡有效窄桥的两侧，不阻挡桥中心；`BridgeContainer` 根据地图连接状态显示/隐藏对应方向的桥。
- Bridge、BridgeWithBoundary、BridgeBoundary、Ground、Obstacle 和 Boundary 使用各自的单一职责 UI Controller；MapContainer 通过协调 Controller 统一传递 RoomContext。
- 为后续通道驻守战斗保留接口，但当前流程不调用；该接口放在相关代码文件的最后。
- 保留 `current_scene`、`current_position`、`on_entered_room` 等现有兼容接口，避免棋盘和战斗背景解析器失效。
- 旧传送门和旧按钮脚本暂不删除，先从新流程断开，待运行验证后再决定是否清理。

## 非目标

- 本次不改变地图随机/过渡场景选择算法。
- 本次不改变 TileMap 瓦片内容和地图生成算法；房间边界限制与已有 Bridge 的跨房通行属于本次目标。
- 本次不迁移或重写旧的通道驻守战斗、时间系统和地图行动值模块。
- 本次不扩展非 `normal` 群系。

## 验收标准

- [x] 主场景加载后，`MapControl` 能显示初始房间及按邻接关系生成的相邻房间。
- [x] 玩家使用 WASD 可以连续跨越房间边界，跨越时位置连续，没有传送、淡入淡出或场景树抖动。
- [x] 当前房间与八邻域中的有效房间已实例化，运行时活跃房间不超过九个。
- [x] 已访问地图坐标离开 3×3 窗口后释放节点，但再次进入时复用原 `MapSceneResource` 与 `PackedScene`。
- [x] 跨界不会调用通道驻守战斗，不会读取或扣除地图移动行动值。
- [x] `current_position` 和 `on_entered_room` 仍能通知现有棋盘/背景解析器。
- [x] 后续边界限制和通道驻守接口存在于代码末尾，但当前未被调用。
- [x] 无连接方向的 `BridgeWithBoundary` 保留阻挡；有效连接方向关闭桥口阻挡，且玩家可沿桥中心进入相邻房间。
- [x] 有效方向的 `BridgeBoundary` 阻挡桥的窄边，桥中心和正常可走地面没有阻挡碰撞。
- [x] Ground 常设 `Boundary` 在连接有无变化时保持相同显示和碰撞状态。
- [x] Bridge、BridgeWithBoundary、BridgeBoundary、Ground、Obstacle、Boundary 控制器各自只管理直接子节点；MapContainer 控制器只分发同一 RoomContext。
- [x] 所有唯一 normal 房间场景及其 TileSet 均经逐项盘点并接入适用模块；不假定房间方向桥或容器结构相同。
- [x] Godot 4.7.1 编辑器运行 `map_control.tscn` 和 `Main.tscn` 时无新增脚本解析错误、加载错误或运行时错误。

## 验收证据

见本目录 runtime-validation.md。按用户要求不截图；跨房连续性通过原有移动输入、逐物理帧坐标、节点生命周期、信号及游戏日志验证。12 个新增契约用例已在游戏进程完整通过。
