# 无缝地图 MVC 与房间模块化架构

初稿日期：2026-09-24

最后修订：2026-09-25

状态：本文件是地图系统当前架构的唯一设计依据。无缝地图的 3×3 房间实例窗口已完成并运行验证；房间内的桥、地面、障碍和三类边界控制器及瓦片碰撞现已接入代码；新增回归测试已编写。当前编辑器 MCP 被权限策略拦截，本轮运行验收尚未执行。

## 1. 目标与约束

- 保持 MapPositionCreate 当前地图生成算法、坐标和邻接结果不变。
- 当前只启用 normal 生态群系；每个房间仍是一个完整的 TileMap 场景，尺寸按 1280×720 拼接，不按瓦片实例化。
- 以完整 PackedScene 作为房间显示资源；Model 缓存 MapSceneResource 和共享 PackedScene，View 只保留当前房间周围 3×3 的运行时节点。
- 玩家通过现有 WASD 连续移动。相邻房间之间只有 Map Model 中存在连接的方向才允许通过；该方向的桥口边界关闭以保持桥面通行，桥两侧仍由 BridgeBoundary 阻挡。
- Boundary 承载 Ground 常设地形边界，不随桥连接状态切换；BridgeWithBoundary 负责各方向桥口的开闭，BridgeBoundary 负责各方向桥本身的边缘。
- 玩家跨房只更新世界状态和显示窗口，不传送、不扣地图行动值、不调用通道驻守战斗。
- 复杂房间功能按容器拆成多个小控制器。房间根脚本和 MapContainerController 都不能重新成为包含所有地图行为的“上帝脚本”。
- 所有表现层和控制器脚本文件以 UI 开头；Model 脚本不加 UI 前缀。

## 2. MVC 职责与依赖方向

### Model：地图事实、业务校验与资源配置

- 保存生成结果、房间连接、当前地图坐标、房间尺寸和地图场景资源缓存。
- 根据坐标返回房间资源与纯数据 RoomContext。
- 校验房间存在性、相邻关系和连接方向，并通过信号广播状态变化。
- 可依赖地图生成器、MapTypes 和纯数据 Resource；不得依赖场景树中的 View、玩家节点或输入事件。
- 不实例化 Node，不调用 add_child 或 queue_free，不绘制、不读取 UI。

### View：场景树、视觉呈现与输入感知

- 房间 .tscn、TileMapLayer、碰撞节点和 UI 节点构成 View。
- View 从 Model 取得资源和状态，把完整 PackedScene 实例化为场景树节点，并监听 Model 信号刷新显示。
- View 可以报告交互意图，但不能自行通过规则校验或修改 Model 状态。
- TileMapLayer 保留场景作者配置的瓦片和 TileSet 碰撞；运行时不逐瓦片创建节点。

### Controller：解释意图并协调 Model 与 View

- 世界 Controller 读取玩家移动结果，识别候选房间，调用 Model 校验跨房请求。
- 房间模块 Controller 只管理挂载节点的直接子节点，并消费同一份 RoomContext。
- Controller 可以协调 Model 与 View，但不得持有或修改不属于自身模块的子节点内部细节。

依赖原则：

    玩家移动意图 → UIMapWorldController → MapWorldModel → 状态信号 → UIMapWorldView
    UIMapWorldView → 房间根节点公开入口 → UIMapContainerController → 各房间子模块 Controller

Model 不依赖 View；View 读取 Model；Controller 依赖 Model 的公开接口，并通过 View 的稳定公开接口进行协调。

## 3. Model 层设计

### core/map/map_world_model.gd

唯一的地图运行状态入口，负责：

- 从 MapPositionCreate 读取 map、scene_to_scene 和 start_position。
- 从 MapTypes 查询场景路径，维护地图坐标到 MapSceneResource 的缓存。
- 按场景路径共享 PackedScene 缓存；缓存里不保存实例化后的 Node。
- 保存 current_position、room_size，并提供地图坐标与世界坐标换算。
- 查询 3×3 窗口中的有效坐标、方向连接和房间上下文。
- 只允许从当前房间沿生成结果中存在的相邻连接进入下一房间。
- 成功更新当前坐标后发出 current_room_changed(position)。

建议公开的稳定协议：

- get_scene_resource(position)：返回坐标对应的 MapSceneResource；无效坐标或资源加载失败时返回 null。
- get_room_context(position)：返回 RoomContext；坐标无效时返回 null。
- has_room(position)：判断生成网格中是否存在房间。
- is_connected(from_position, to_position)：只对相邻坐标检查生成器记录的双向连接。
- try_enter_room(to_position)：校验目标房间有效，且它与 current_position 直接相连；成功后更新状态并广播信号。
- get_window_positions(center)：返回当前中心周围有效的 3×3 坐标。
- world_origin_for(position) 与 map_position_for_world(world_position)：使用统一的 1280×720 房间步长。

方向索引继续服从 MapPositionCreate：0=上，1=右，2=下，3=左。地图网格坐标为 row/column；世界 X 对应 column，世界 Y 对应 row。

### 资源配置

- resources/map/map_scene_resource.gd：描述一个地图坐标使用的场景名、场景路径、共享 PackedScene 和房间尺寸。该资源不持有 Node2D 实例。
- core/map/room_context.gd：只读数据传输对象，包含房间坐标、连接方向掩码、尺寸和场景资源；不保存任何场景节点或玩家引用。
- 本架构不使用 RoomTraversalProfile 推算碰撞开口。桥口和边缘由完整房间场景中已布置的 TileMapLayer 表达，运行时只按连接掩码切换对应方向模块。

资源缓存生命周期：

    MapWorldModel：position → MapSceneResource；scene_path → PackedScene
    UIMapWorldView：position → 当前 3×3 内的 Node2D 实例

窗口外释放 Node2D，但保留 Model 的资源缓存。重新进入时用原 PackedScene 再实例化，不重新生成地图，不缓存整棵场景树。

### 继续使用的现有 Model/配置

- scripts/map_scripts/map_position_create.gd：地图生成算法与邻接数据来源，本次不改生成规则。
- scripts/map_scripts/map_types.gd：场景名、群系配置与场景路径查询。
- resources/map/biomes/normal_biome.tres、resources/map/map_attribute.gd、resources/map/biome_definition.gd：normal 群系与场景配置。
- core/map/room_terrain_profile.gd、core/map/room_terrain_store.gd：地形棋盘数据，不负责房间跨界碰撞。

## 4. View 层设计

### scripts/map_scripts/UIMapWorldView.gd

- 监听 MapWorldModel.current_room_changed。
- 从 Model 读取资源并通过 PackedScene.instantiate() 创建整个房间。
- 按 MapWorldModel.world_origin_for() 放置房间；固定房间步长为 Vector2(1280, 720)。
- 维护当前房间与八邻域的完整场景实例；新窗口准备完成后释放窗口外节点。
- 实例化后只调用房间根节点的 configure_room_context(context) 稳定入口，不直接访问 MapContainer 下各模块的内部节点。
- 保留 current_scene、current_position、map_scene 与 on_entered_room(position, scene) 兼容协议，供现有消费者使用。
- 昼夜背景变化属于 View 表现，不进入 Model。

### 房间场景本身

房间 .tscn 是一份可整体实例化的 View 资源。TileMapLayer 是场景中的批量瓦片表现，不是每个瓦片一个 Node。

以 clear_creek.tscn 为例，MapContainer 下已有 BridgeWithBoundary、BridgeBoundary、Boundary、BridgeContainer、Ground 和 Obstack。目标结构如下：

    ClearCreek (Node2D，保留 map_env_base.gd 的场景元数据/兼容入口)
    ├── MapContainer (Node2D，挂 UIMapContainerController.gd)
    │   ├── BridgeWithBoundary (Node2D，挂 UIBridgeWithBoundaryController.gd)
    │   │   ├── LeftBridgeWithBoundary (TileMapLayer)
    │   │   ├── RightBridgeWithBoundary (TileMapLayer)
    │   │   ├── UpBridgeWithBoundary (TileMapLayer)
    │   │   └── DownBridgeWithBoundary (TileMapLayer)
    │   ├── BridgeBoundary (Node2D，挂 UIBridgeBoundaryController.gd)
    │   │   ├── LeftBridgeBoundary (TileMapLayer)
    │   │   ├── RightBridgeBoundary (TileMapLayer)
    │   │   ├── UpBridgeBoundary (TileMapLayer)
    │   │   └── DownBridgeBoundary (TileMapLayer)
    │   ├── Boundary (Node2D，挂 UIBoundaryController.gd)
    │   │   └── 场景原有固定地形边界 TileMapLayer 子节点
    │   ├── BridgeContainer (Node2D，挂 UIBridgeContainerController.gd)
    │   │   ├── LeftBridge (TileMapLayer)
    │   │   ├── RightBridge (TileMapLayer)
    │   │   ├── UpBridge (TileMapLayer)
    │   │   └── DownBridge (TileMapLayer)
    │   ├── Ground (Node2D，挂 UIGroundController.gd)
    │   │   └── 场景原有 Ground TileMapLayer 子节点
    │   ├── Obstack (Node2D，挂 UIObstacleController.gd)
    │   │   └── 场景原有障碍 TileMapLayer 子节点
    └── Label 等房间表现节点

节点名 Obstack 是当前场景序列化中的历史拼写。第一轮实现保留节点名，仅把控制器文件命名为 UIObstacleController.gd；只有完成所有场景、脚本、资源和 NodePath 搜索后，才可另行决定是否改名。

### 其他 UI View

- UIMapLittle.gd：小地图格子、连接线和当前坐标高亮。
- UIRoomBoardPresenter.gd：监听 MapControl.on_entered_room，读取房间根节点 terrain_profile 并刷新地形棋盘。
- UICurrentMapBackgroundResolver.gd：从 MapInstantiator.current_scene 解析当前房间背景。
- 房间根节点 map_env_base.gd 保留 scene_type、terrain_profile、initialize_scene() 等已有兼容功能；只提供转发 configure_room_context() 的薄入口，不承担地面、障碍、桥或边界行为。

## 5. Controller 层与房间单一职责模块

### scripts/map_scripts/UIMapWorldController.gd：世界级跨房 Controller

- 只读取玩家 global_position，不拥有或重写玩家移动逻辑。
- 将世界坐标转换为候选房间坐标；与当前坐标不同才请求 Model。
- 由 Model 验证目标房间有效并且连接方向真实存在；非法目标不改变地图状态。
- 不实例化房间，不移动/重置玩家位置，不调用传送、过场、地图行动值或驻守战斗。
- 文件最后保留 can_enter_room_with_boundaries(...) 和 request_passage_guard_encounter(...) 两个后续接口；当前不从跨房路径调用它们。

Bridge 是场景内真实可通行的连接表现，不是传送点。玩家穿过已开放的边缘时，世界 Controller 从连续世界坐标观察到新房间；桥模块本身不直接修改 Model。

### scripts/map_scripts/UIMapContainerController.gd：房间组合 Controller

挂载于 MapContainer。它存在的原因是四个局部模块需要消费同一份上下文并以一致顺序配置，但不应由世界 View 逐一耦合各模块。

- 接收 configure_room_context(context)，校验上下文并保存当前房间绑定。
- 通过 Inspector 导出 NodePath 或明确的直接子节点引用取得六个模块 Controller。
- 按固定顺序把同一 RoomContext 下发给 Ground、Obstacle、Bridge、BridgeWithBoundary、BridgeBoundary、Boundary 控制器。
- 重复绑定同一上下文必须幂等，不重复创建场景子节点。
- 不访问 TileMap 数据，不计算玩家位置，不调用 MapWorldModel，不做跨房规则判断。

### scripts/map_scripts/UIGroundController.gd：地面模块

挂载于 Ground，只管理自己的直接 TileMapLayer 子节点。

- 保持地面图层顺序、可见性和场景作者设置的 TileSet 数据。
- 保留 TileSet 已配置的碰撞，不逐瓦片实例化或改写地图内容。
- 不管理障碍物、桥、房间外围墙或世界坐标。

### scripts/map_scripts/UIObstacleController.gd：障碍模块

挂载于 Obstack，只管理自己的直接障碍 TileMapLayer 子节点。

- 保持障碍显示和场景作者配置的 TileSet 碰撞。
- 若后续有动态障碍状态，只在本模块处理。
- 不改地面、桥面、边界或玩家坐标。

### scripts/map_scripts/UIBridgeContainerController.gd：方向桥模块

挂载于 BridgeContainer，只管理四个直接方向子节点。

- 将 RoomContext 的连接方向映射到 LeftBridge、RightBridge、UpBridge、DownBridge。
- 连接方向保留对应桥面；无连接方向隐藏并关闭对应的桥层碰撞/通行。
- 只报告/配置本房间桥面，不调用 Model.try_enter_room，不扣行动值，不触发战斗，不移动玩家。
- 不依据玩家输入自行决定目标坐标；边界跨房校验归 UIMapWorldController 与 MapWorldModel。

### scripts/map_scripts/UIBridgeWithBoundaryController.gd：方向桥口开闭模块

挂载于 MapContainer/BridgeWithBoundary，只管理四个方向的直接 TileMapLayer 子节点。

- 以 RoomContext 的连接方向为唯一输入，逐方向配置 Left/Right/Up/DownBridgeWithBoundary。
- 该方向有桥时，关闭阻挡该桥口的 Boundary 碰撞，使窄桥中心保持可通行；该方向无桥时，保留桥口阻挡。
- 只操作自己的 TileMapLayer，不访问 BridgeContainer、BridgeBoundary 或 Boundary 的内部节点。
- 这里的“关闭”指关闭桥口阻挡，不是关闭桥面通行；实际瓦片碰撞配置必须给桥中心留出连续无碰撞通道。

### scripts/map_scripts/UIBridgeBoundaryController.gd：桥边缘碰撞模块

挂载于 MapContainer/BridgeBoundary，只管理四个方向的直接 TileMapLayer 子节点。

- 仅在对应方向存在真实桥时启用该方向的桥边界。
- 碰撞覆盖窄桥两侧，不覆盖桥面中心，也不代替桥口开闭模块。
- 不修改桥面瓦片，不访问 BridgeContainer 或 Boundary 内部节点。

### scripts/map_scripts/UIBoundaryController.gd：固定地形边界模块

挂载于 MapContainer/Boundary，只管理 Boundary 下的直接 TileMapLayer 子节点。

- 保留场景作者布置的 Ground 常设边界与 TileSet 碰撞。
- 其可见性和碰撞不随连接掩码或桥是否存在而切换。
- 不把 Boundary 扩展成按 1280×720 矩形推算的动态外围墙；固定边界的位置以场景瓦片为准。

### TileSet 碰撞职责

- Ground 中实际构成地形边沿的边界瓦片、Obstack 中阻挡玩家的障碍瓦片、BridgeBoundary 中桥两侧边界瓦片配置碰撞。
- Bridge 的可走中心、BridgeWithBoundary 在有效桥向的桥口、普通可行走地面不得配置阻挡玩家的碰撞。
- `Boundary` 是固定层；`BridgeWithBoundary` 是随方向连接状态切换的桥口阻挡；`BridgeBoundary` 是随方向桥状态出现的桥侧边界。三者不可互相替代。
- 玩家碰撞层与瓦片物理层必须在资源盘点后统一核对；不得对整张 Ground TileSet 盲目添加碰撞。

| Map Model 方向连接 | BridgeContainer | BridgeWithBoundary | BridgeBoundary | Boundary 常设地形边界 |
|---|---|---|---|---|
| 无连接 | 隐藏该方向桥 | 保留桥口阻挡 | 关闭该方向桥侧边界 | 保持场景配置，不切换 |
| 有连接 | 显示该方向桥 | 关闭阻挡桥口的边界 | 启用桥两侧边界，桥中心不阻挡 | 保持场景配置，不切换 |

本架构中的“关闭桥口边界”指禁用会挡住桥面中心的那段阻挡；它不表示关闭桥本身。这样有效桥向才能连续跨房，同时桥两侧仍由 BridgeBoundary 约束。

## 6. 运行时数据流

    MapPositionCreate 生成 map / scene_to_scene
        ↓
    MapWorldModel 取得配置与资源，建立 RoomContext
        ↓
    UIMapWorldView 实例化完整 PackedScene 并按 1280×720 摆放
        ↓
    房间根节点 configure_room_context(context)
        ↓
    UIMapContainerController 将上下文分发给 Ground / Obstacle / Bridge / BridgeWithBoundary / BridgeBoundary / Boundary
        ↓
    玩家 WASD 连续移动；Ground / Obstacle 碰撞处理地形，BridgeWithBoundary 封住无桥桥口，BridgeBoundary 阻止玩家走离窄桥，固定 Boundary 不随桥状态改变
        ↓
    玩家实际通过开放 Bridge 跨到相邻世界坐标
        ↓
    UIMapWorldController 请求 MapWorldModel.try_enter_room(target)
        ↓
    Model 校验连接并更新 current_position，发出 current_room_changed
        ↓
    UIMapWorldView 先补齐新 3×3 窗口，再释放窗口外 Node2D
        ↓
    on_entered_room 通知小地图、地形棋盘和背景解析器

跨房前后玩家 global_position 必须连续。RoomBoardPresenter 仍可依据 on_entered_room 更新地形棋盘；这个显示更新不等于传送。

## 7. 依赖与引用审计

| 入口/资源 | 当前消费者或引用 | 架构约束 |
|---|---|---|
| normal_biome.tres / BiomeDefinition / MapAttribute | MapTypes；MapPositionCreate 使用 MapTypes 取得群系与生成规则 | 继续提供 normal 场景和生成规则，不把瓦片节点写入 Model |
| MapPositionCreate.map、scene_to_scene、start_position | MapWorldModel | 生成器保持原职责；连接掩码以其上/右/下/左顺序解释 |
| MapTypes.from_name_get_road(scene_name) | 当前 UIMapWorldView.create_map_road() 调用 | 目标架构将坐标到资源路径解析责任移入 MapWorldModel；View 不再写 Model 缓存 |
| MapWorldModel.current_room_changed | UIMapWorldView | Model 只广播坐标事实；不查找或创建显示节点 |
| MapWorldModel.get_scene_resource(position) | UIMapWorldView.ensure_scene_at() | 返回资源配置，不返回/缓存 Node2D |
| MapInstantiator 节点路径和 UIMapWorldView 的兼容字段/信号 | UIMapControl、UICurrentMapBackgroundResolver、旧 MapButton/DoorController 代码 | 暂时保留节点名与兼容接口；新自由跨房流程不接入旧门 |
| UIMapWorldController 玩家绑定 | MapControl.player_char；Main.tscn 提供 PlayerChar | 只读玩家世界坐标；不写玩家位置 |
| UIMapControl.on_entered_room(position, scene) | UIRoomBoardPresenter 与其他观察者 | 保持参数和信号语义兼容 |
| room_scene.terrain_profile / initialize_scene() | UIRoomBoardPresenter、map_env_base.gd/map_base.gd | 保留房间地形配置与既有初始化行为，不并入 MapContainerController |
| UIMapLittle | UIMapControl | 只更新小地图，不实例化真实房间 |
| DoorController、Door、Transpoint、MapButton | 旧场景/脚本/测试仍含静态路径引用 | 保留兼容，不连接新 Bridge 跨房链路，不在本次架构实施中顺手删除 |
| passage_guard_controller.gd | 旧通道战斗流程和测试 | 保留旧系统；新的世界跨房链路不得调用 |

normal 生态有 12 个唯一房间场景，且当前工作树中的 normal 场景已开始加入三类边界节点。实施前仍须逐场景确认各方向 TileMapLayer、TileSet 与 Obstack 容器，不沿用旧文档中“ordinary_wetland 缺少 Obstack”的结论。所有群系场景也引用 map_env_base.gd，因此只扩展 normal 房间时不能破坏根脚本兼容行为。

## 8. 计划文件

### 新增

- core/map/room_context.gd：纯数据上下文。
- scripts/map_scripts/UIMapContainerController.gd。
- scripts/map_scripts/UIBridgeContainerController.gd。
- scripts/map_scripts/UIBridgeWithBoundaryController.gd。
- scripts/map_scripts/UIBridgeBoundaryController.gd。
- scripts/map_scripts/UIGroundController.gd。
- scripts/map_scripts/UIObstacleController.gd。
- scripts/map_scripts/UIBoundaryController.gd。
- tests/godot/test_room_module_controller_contract.gd。

### 修改

- core/map/map_world_model.gd：由 Model 解析资源路径；增加连接校验、RoomContext 查询和配置缓存。
- resources/map/map_scene_resource.gd：保存场景资源路径和房间尺寸，不保存运行时节点或 TileMap 碰撞开口配置。
- scripts/map_scripts/UIMapWorldView.gd：将上下文经房间根节点公开接口交给场景；保持 3×3 资源/节点缓存边界。
- scripts/map_scripts/UIMapWorldController.gd：验证相邻连接后更新 Model；保留兼容 API 和文件末尾扩展接口。
- scripts/map_scripts/map_env_base.gd：仅增加稳定上下文转发入口，保留现有场景类型、地形配置和初始化。
- scenes/map_scenes/map_control.tscn：保持玩家和兼容节点入口；RoomContext 只传连接方向等纯数据。
- scenes/map_scenes/map_env/normal/**/*.tscn：为 BridgeWithBoundary、BridgeBoundary、Boundary、BridgeContainer、Ground、Obstack 挂载单一职责 Controller；按 TileSet 分类配置碰撞，不改房间生成与瓦片布局规则。

### 保持不改

- MapPositionCreate 的生成算法和 normal_biome.tres 的场景选择规则。
- 玩家 WASD 移动脚本。
- 旧门、传送点、MapButton 与 PassageGuardController 的实现；新流程只是不接入它们。
- Main.tscn 的业务流程，除非实际引用审计证明必须调整。

## 9. 验收合同

- 无效坐标、void 坐标、非相邻坐标或没有真实连接的目标均不得更新 Model.current_position。
- 有效相邻方向的 Bridge 层显示且桥中心可通行；无连接方向隐藏桥且 BridgeWithBoundary 封住桥口。
- BridgeBoundary 只阻挡窄桥两侧；玩家不能从桥侧掉入空白世界，但能沿桥中心跨房。
- Boundary 中的 Ground 常设地形边界始终使用场景作者配置，不因桥连接状态被启停或改写。
- Ground、Obstacle、Bridge、BridgeWithBoundary、BridgeBoundary、Boundary 各自只管理直接子节点；模块之间不通过 NodePath 修改彼此内部节点。
- 同一 RoomContext 可被重复配置而不生成重复节点或重复连接信号。
- 3×3 之外不保留房间 Node2D；对应 MapSceneResource 与 PackedScene 仍可复用。
- 玩家跨房时位置连续，且不出现传送、地图行动值扣除或驻守战斗。
- UIRoomBoardPresenter、UICurrentMapBackgroundResolver、UIMapLittle 继续接收正确的当前房间。
- 编辑器运行测试覆盖 clear_creek、ordinary_wetland 和 Main.tscn；Godot 4.7.1 中不得出现本次引入的解析、资源或运行时错误。

## 10. 当前实现边界

本节原有三条记录保留为本轮实施前的历史快照；本轮模块、碰撞和跨房的最新结果见文末补充及任务 runtime-validation.md。MapTypes 路径表的原有建立方式没有在本轮重构。

- 已实现并由 Godot 4.7.1 编辑器验证：MapWorldModel 的资源缓存、共享 PackedScene、1280×720 坐标换算、UIMapWorldView 的 3×3 实例窗口、玩家连续跨越房间以及现有棋盘/背景兼容链路。
- 本次提出但尚未实现：MapTypes 场景路径解析迁入 Model、MapWorldModel 连接强校验、RoomContext、六类房间子模块 Controller、TileSet 碰撞配置和 normal 房间场景接线。
- 本文件描述目标架构，不表示上述待实施项已写入源码或通过运行验证。

## 本轮落地补充

- 模块的 validate_room_context(context) -> bool 只做直接子节点预检。MapContainer 先检查所有模块，再依次 configure_room_context，防止模块缺失时留下已经开放的桥口。
- 房间根 configure_room_context(context) -> bool 薄转发模块配置结果。UIMapWorldView 仅在成功后将实例加入场景树和活跃窗口；不读取子模块的瓦片。
- 三类边界和障碍使用 TileSet 物理层 32、掩码 16，匹配玩家层 16、掩码 32。32 像素桥边瓦片只在外侧半格阻挡，让 100×140 的玩家矩形能通过中心。
- 用户已明确允许 Main.tscn 的初始出生点为 (640,360)；这只是场景加载时的初值。Controller 跨房时仍不修改玩家位置、不传送。
- 用户已开放编辑器 MCP 权限。两个新套件在新启动的 Godot 4.7.1 游戏进程完整通过：12 个用例、30,725 个断言；五个目标场景完成冒烟，Main 连续往返、节点回收和资源复用通过。依据见 .trellis/tasks/09-23-seamless-map-world/runtime-validation.md。没有截图，也没有把编辑器跳过项算作运行通过。
