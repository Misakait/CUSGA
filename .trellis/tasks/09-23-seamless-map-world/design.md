# 技术设计

> 初版设计中的“暂不增加房间边界”已被后续需求替代。当前 MVC、房间子模块、Bridge 开口和边界碰撞的依据为 .trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md。

## 房间内部模块

- Model 保存生成结果、连接校验、MapSceneResource/PackedScene 缓存和纯数据 RoomContext；不操作场景树。
- UIMapWorldView 实例化完整房间后，只经房间根节点 `configure_room_context(context)` 入口初始化，不直接查找模块内部节点。
- MapContainer 通过 `UIMapContainerController` 将同一上下文下发给 BridgeContainer、BridgeWithBoundary、BridgeBoundary、Ground、Obstack、Boundary 六个单一职责 Controller。
- `Boundary` 承载 Ground 常设地形边界，不因桥开或关闭而变化；场景节点仍与 Ground 同为 MapContainer 的直接子节点。
- `BridgeBoundary` 只限制对应窄桥的两侧；桥中心必须保留连续无碰撞通路。
- `BridgeWithBoundary` 处理方向桥口阻挡：无连接时封住桥口；存在连接时关闭阻挡桥口的边界，使桥中心通行。
- `UIMapWorldController` 观察玩家连续世界坐标，Model 再校验相邻连接；Bridge 不触发传送，也不直接修改 Model。
- 12 个 normal 场景和它们引用的 TileSet 都要逐一核对，不能假定所有房间拥有相同方向桥、子层数量或碰撞配置。

| Map Model 的方向连接 | BridgeContainer | BridgeWithBoundary | BridgeBoundary | Boundary 中的常设地形边界 |
|---|---|---|---|---|
| 无连接 | 隐藏该方向桥 | 保留桥口阻挡 | 关闭该方向桥侧边界 | 保持场景配置，不切换 |
| 有连接 | 显示该方向桥 | 关闭阻挡桥口的边界 | 启用桥两侧边界，桥中心不阻挡 | 保持场景配置，不切换 |

## MVC 边界

### Model：地图世界状态

新增 `core/map/map_world_model.gd`，只保存不依赖场景树的地图世界状态：

- 当前地图坐标和地图生成器提供的坐标关系。
- 地图坐标到 `MapSceneResource` 的资源缓存。
- 场景路径到 `PackedScene` 的共享缓存。
- `map` 与 `scene_to_scene` 的邻接关系查询。
- 房间坐标、连接方向掩码、房间尺寸和场景资源组成的纯数据 `RoomContext`。
- 房间尺寸、坐标到世界位置的转换参数。

模型不负责实例化节点、不移动玩家、不触发战斗或时间系统。

### View：房间节点呈现

由 `scripts/map_scripts/UIMapWorldView.gd` 负责把模型给出的完整房间资源实例化到统一世界根节点，并按地图坐标设置位置：

- 当前坐标变化时补齐当前房间与八邻域中的有效完整场景。
- 3×3 窗口外的运行时节点立即从活跃字典移除并释放。
- 再次访问同一坐标时复用 Model 中的 `MapSceneResource` 与 `PackedScene`，重新创建显示节点。
- 保留 `current_scene`、`current_position` 和 `on_entered_room` 兼容接口。
- 不处理玩家输入，不调用 `TimeSystem`、`PassageGuardController` 或过场系统。

### Controller：玩家跨界协调

新增 `scripts/map_scripts/UIMapWorldController.gd`，绑定 `MapControl`、Model 和玩家节点；旧 `map_world_controller.gd` 只保留兼容包装：

- 每帧读取玩家 `global_position`。
- 根据统一房间原点和房间尺寸计算玩家所在地图坐标。
- 坐标变化时只调用 Model 更新当前坐标，由 View 监听 Model 信号并刷新实例窗口。
- `UIMapWorldView` 发出 `on_entered_room`，再由 `UIMapControl` 转发给 `RoomBoardPresenter` 等观察者。
- 不改变玩家位置，不创建传送，不扣行动值，不启动驻守战斗。

文件末尾保留两个未来接口：

- `can_enter_room_with_boundaries(...)`：未来根据 TileMap 限制区域判断是否允许进入。
- `request_passage_guard_encounter(...)`：未来接入通道驻守战斗；当前返回未启用并且不被跨界流程调用。

房间模块 Controller 不承担地图邻接业务。MapContainer 协调器按顺序下发上下文；各子 Controller 只修改自己直接拥有的 TileMapLayer：

- `UIBridgeContainerController`：按连接掩码显示/隐藏方向桥。
- `UIBridgeWithBoundaryController`：无桥时保留桥口阻挡，有桥时关闭阻挡桥口的边界。
- `UIBridgeBoundaryController`：有桥时限制窄桥两侧，无桥时关闭该方向边界。
- `UIGroundController`、`UIObstacleController`：管理各自图层与 TileSet，不改写其他模块碰撞。
- `UIBoundaryController`：保留 Ground 常设边界；不读取连接掩码来切换碰撞。

TileSet 碰撞仅配置到真实需要阻挡玩家的地形边界、障碍和桥侧瓦片。可走 Ground 与桥中心保持无阻挡碰撞；最终 TileSet 物理层须匹配玩家 collision layer/mask。

## 数据流

```text
MapPositionCreate(map, scene_to_scene, start_position)
        -> MapWorldModel(坐标/邻接/资源缓存状态)
        -> UIMapWorldController(读取 Player.global_position 并调用 Model)
        -> UIMapWorldView(实例化 3×3 有效完整场景并按坐标摆放)
        -> current_position/on_entered_room
        -> RoomBoardPresenter / CurrentMapBackgroundResolver
```

## 兼容性

- `Main.tscn` 继续把 `Player` 和 `PlayerChar` 注入 `MapControl`。
- `RoomBoardPresenter` 继续监听 `MapControl.on_entered_room`。
- `WorldInteractionCoordinator` 继续使用 `MapSystem` 节点路径；本次不改变战斗隐藏/恢复地图契约。
- `current_map_background_resolver.gd` 继续从 `MapInstantiator.current_scene` 解析当前背景。
- `MapPositionCreate` 的生成算法和 `normal_biome.tres` 资源不改。
- 旧 `MapButton`、`DoorController`、`Door`、传送场景和驻守控制器保留，以便回滚和兼容旧测试，但不再连接到新的跨界路径。

## 风险与处理

- 房间步长不从 TileMap 使用范围推断；normal 群系场景统一按设计尺寸 `1280x720` 拼接，避免不同瓦片内容改变世界坐标。
- 相邻房间同时存在时，`current_scene` 必须仍指向玩家所在房间，避免背景解析器读取错误房间。
- 运行时节点严格受 3×3 窗口限制；长期复用的是资源配置，不是完整场景节点。
- normal 房间内承载 TileMap 的容器必须是 `Node2D`，房间标题不得设置 `top_level`，否则房间根节点位移不会传递到瓦片和标题。
