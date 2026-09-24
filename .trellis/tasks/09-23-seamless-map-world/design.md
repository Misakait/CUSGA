# 技术设计

## MVC 边界

### Model：地图世界状态

新增 `core/map/map_world_model.gd`，只保存不依赖场景树的地图世界状态：

- 当前地图坐标和地图生成器提供的坐标关系。
- 地图坐标到 `MapSceneResource` 的资源缓存。
- 场景路径到 `PackedScene` 的共享缓存。
- `map` 与 `scene_to_scene` 的邻接关系查询。
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
