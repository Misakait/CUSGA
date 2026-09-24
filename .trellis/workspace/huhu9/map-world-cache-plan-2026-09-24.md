# 历史记录：无缝地图资源缓存与三乘三实例窗口

> 本文记录资源缓存和 3×3 实例窗口的早期需求与验证。“暂不增加房间边界”的决定已被后续需求覆盖。继续开发时以 [地图 MVC 与房间模块化架构](./map-world-mvc-architecture-2026-09-24.md) 为准。

日期：2026-09-24

## 用户要求

> 当玩家抵达下一个场景的时候，该场景要实例化出来；
> 当玩家处于某个场景时，它周围八个场景都要实例化出来，而以外的场景就要做缓存；
> 缓存就缓存地图场景资源，而不是直接缓存整个场景；
> 生成场景时，如果没生成过，就给予一份资源，如果生成过，就复用这份资源。

## 当前问题

- `MapInstantiator` 当前把已经实例化的 `Node2D` 长期放在 `map_scene` 和场景树中。
- 初始流程只预加载四方向连接房间，没有维护当前房间周围八个网格位置的活跃窗口。
- 没有把“地图场景资源缓存”和“运行时场景实例缓存”分开。

## 目标架构

采用 MVC 加两级缓存：

1. **Model：`MapWorldModel`**
   - 保存 `MapPositionCreate` 生成的地图、坐标到场景路径的映射、当前房间坐标和固定房间尺寸 `1280x720`。
   - 新增按地图坐标保存的 `MapSceneResource` 缓存。资源中只保存场景路径、场景名和可复用的 `PackedScene`，不保存运行时节点。
   - 提供“取得或创建资源”“计算当前坐标周围三乘三有效位置”“记录/移除活跃实例”的协议。

2. **View：`MapInstantiator`**
   - 只从 Model 取得 `MapSceneResource` 并实例化 `Node2D`。
   - 以当前房间为中心维护最多九个有效房间实例：中心、上/下/左/右和四个对角位置。
   - 玩家进入新房间时先确保新中心的三乘三窗口，再释放窗口外节点；释放节点不释放 Model 中的资源缓存。
   - 保留 `current_scene`、`current_position`、`map_scene` 和 `on_entered_room` 兼容接口。

3. **Controller：`MapWorldController`**
   - 继续只读取玩家世界坐标并通知 View 切换当前房间。
   - 不传送玩家、不增加边界限制、不扣地图行动值、不请求通道驻守战斗。
   - 文件末尾继续保留未来的边界限制和驻守战斗接口。

## 计划修改和新增文件

### 代码

- `core/map/map_world_model.gd`：加入资源缓存、三乘三有效坐标计算和实例生命周期协议。
- `scripts/map_scripts/map_instantiator.gd`：改为资源缓存与活跃实例窗口分离，窗口外实例释放。
- `scripts/map_scripts/map_world_controller.gd`：继续调用新的 View 窗口更新协议，保留未来接口。
- `tests/test_seamless_map_world.gd`：增加资源复用、九格窗口、窗口外释放和玩家坐标不变的测试。

### 新增

- `resources/map/map_scene_resource.gd`：地图场景资源对象；只持有序列化场景路径/名称和可复用的 `PackedScene`，不持有节点实例。

### 明确不改

- `scripts/map_scripts/map_position_create.gd` 的地图生成算法和 normal 群系内容。
- 玩家 WASD 移动脚本。
- `RoomBoardPresenter`、背景解析器的兼容协议。
- 旧传送门、旧按钮、`DoorController` 和驻守战斗脚本；它们保留但不接入新的自由跨界流程。
- 未来边界限制和驻守战斗接口的当前行为。

## 依赖与引用审计

- `MapControl` 连接 `MapInstantiator.on_entered_room`，并转发给小地图及外部观察者。
- `MapWorldModel` 读取 `MapPositionCreate.map`、`scene_to_scene`、`start_position`。
- `MapInstantiator` 通过 `MapTypes.from_name_get_road` 得到 normal 场景路径，并维护 `current_scene`。
- `MapWorldController` 读取 `MapControl.player_char.global_position`，调用 `MapInstantiator.load_scene_at`。
- `core/map/room_board_presenter.gd` 通过进入房间信号使用场景节点上的地形配置。
- `core/gameflow/current_map_background_resolver.gd` 通过 `MapInstantiator.current_scene` 取得当前背景。
- `MapLittle` 只接收当前坐标并维护小地图节点，不参与世界实例缓存。

## 验证计划

1. 用 Godot 编辑器 MCP 执行 `seamless_map_world` 测试套件。
2. 验证初始房间周围最多九个实例，窗口外节点不在场景树中而资源缓存仍存在。
3. 验证跨越 `1280x720` 边界后目标房间已实例化、玩家位置连续、当前坐标更新。
4. 返回旧坐标，验证同一坐标复用原 `MapSceneResource`，且不会重复加载 `PackedScene`。
5. 通过 `project_run` 启动主场景并读取游戏日志，确认没有脚本解析、资源加载或运行时错误。
6. 重新读取 `git status` 和 `git log`，确认 Godot 编辑器没有写入无关文件。
