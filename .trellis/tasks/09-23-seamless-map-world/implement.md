# 实施计划

> 本文件必须能在没有本轮对话上下文时独立指导实施。当前版本同时记录实施计划和代码完成状态；勾选代码步骤不代表运行验收已经通过。更改架构约定时必须同时更新本文件和 `.trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md`。本轮已补齐房间控制器、碰撞资源和测试；用户开放权限后，已通过 Godot 4.7.1 编辑器 MCP 完成运行验收，证据见 runtime-validation.md。

## 目标

保留 `MapPositionCreate` 的地图生成规则和已生成结果；每个房间继续以完整的 `1280×720` TileMap 场景显示，不按瓦片创建房间。Map Model 的方向连接数据配置 Bridge、BridgeWithBoundary 和 BridgeBoundary。Boundary 承载 Ground 常设边界，独立于桥连接状态。玩家可沿有效桥面连续跨房，不可从桥侧或无桥桥口进入空白世界。玩家跨房不传送、不扣地图移动行动值、不触发旧通道驻守战斗。

## 架构职责

### Model：地图状态、连接规则和资源配置

- `MapWorldModel` 保管已生成地图的房间坐标、房间间连接、当前房间坐标、固定房间尺寸和场景资源缓存。
- Model 从 `MapPositionCreate` 的生成结果判定房间是否存在、两个房间是否相邻以及相邻方向是否真实连接；不得只凭目标坐标存在就允许跨入。
- 方向索引沿用生成器约定：`0=上、1=右、2=下、3=左`。地图坐标以 row/column 表示，世界 X 对应 column、世界 Y 对应 row；不得在 Controller 中另造方向顺序。
- `MapSceneResource` 描述房间使用的场景路径、场景资源和房间尺寸。它不持有实例化后的 Node。
- `RoomContext` 是只读数据对象，至少传递房间坐标、方向连接掩码、房间尺寸和 MapSceneResource；不保存 TileMapLayer、玩家 Node 或场景实例。
- Model 不读取输入、不实例化或释放场景节点、不操作碰撞、不移动玩家、不渲染 UI，也不依赖 View。
- 不新增 `RoomTraversalProfile`。桥口和桥边界的位置来自场景内已经布置的 TileMapLayer，不按 1280×720 矩形计算或猜测开口。

### View：完整房间实例与显示窗口

- `UIMapWorldView` 通过 `PackedScene.instantiate()` 实例化完整房间，并按房间坐标和 `Vector2(1280, 720)` 的房间步长摆放。
- View 只保持玩家当前房间及其周围八个有效房间的实例。地图边缘或 void 坐标可能让实际实例数少于九个。
- 离开 3×3 活跃窗口时释放窗口外的运行时 Node2D；MapSceneResource 与共享 PackedScene 继续由 Model 缓存。
- View 通过房间根节点的 `configure_room_context(context)` 公开入口初始化模块，不直接查找房间内桥、地面、障碍或边界的 TileMapLayer。
- 保持 `current_scene`、`current_position`、`map_scene`、`on_entered_room(position, scene)` 等已有兼容接口，供地图控制节点、地形棋盘和背景解析器继续读取。

### Controller：输入解释、连接校验调用和模块协调

- `UIMapWorldController` 读取玩家实际世界坐标并计算候选房间；只在坐标改变时请求 Model 校验。它不能写玩家位置，也不能触发传送、地图行动值扣除或驻守战斗。
- `UIMapContainerController` 挂在 MapContainer，校验并保存 RoomContext，再把同一份上下文交给六个房间模块 Controller。重复配置必须幂等。
- 六个房间模块 Controller 各自只管理所在容器的直接子节点，不跨模块访问或修改其他容器的内部节点。
- 房间根脚本 `map_env_base.gd` 只保留已有场景元数据、地形配置和初始化兼容行为，并薄转发 `configure_room_context(context)`；不得变成管理所有房间功能的上帝脚本。

## 房间节点结构和模块所有权

以下是 `clear_creek.tscn` 的目标结构。`Boundary` 与 `Ground` 是 MapContainer 的同级子节点；Boundary 承载 Ground 常设地形边界，但不是 Ground 的子节点。

```text
ClearCreek (Node2D, map_env_base.gd)
└── MapContainer (Node2D, UIMapContainerController)
    ├── BridgeWithBoundary (Node2D, UIBridgeWithBoundaryController)
    │   ├── LeftBridgeWithBoundary (TileMapLayer)
    │   ├── RightBridgeWithBoundary (TileMapLayer)
    │   ├── UpBridgeWithBoundary (TileMapLayer)
    │   └── DownBridgeWithBoundary (TileMapLayer)
    ├── BridgeBoundary (Node2D, UIBridgeBoundaryController)
    │   ├── LeftBridgeBoundary (TileMapLayer)
    │   ├── RightBridgeBoundary (TileMapLayer)
    │   ├── UpBridgeBoundary (TileMapLayer)
    │   └── DownBridgeBoundary (TileMapLayer)
    ├── Boundary (Node2D, UIBoundaryController)
    │   └── 场景配置的固定地形边界 TileMapLayer
    ├── BridgeContainer (Node2D, UIBridgeContainerController)
    │   ├── LeftBridge (TileMapLayer)
    │   ├── RightBridge (TileMapLayer)
    │   ├── UpBridge (TileMapLayer)
    │   └── DownBridge (TileMapLayer)
    ├── Ground (Node2D, UIGroundController)
    │   └── 场景配置的 Ground TileMapLayer
    └── Obstack (Node2D, UIObstacleController)
        └── 场景配置的障碍 TileMapLayer
```

| Controller | 职责范围（可操作） | 禁止职责 |
|---|---|---|
| `UIMapContainerController` | Direct references to six module Controllers; initialization order and RoomContext dispatch | Read TileMap cells, calculate player coordinates, decide map adjacency or change player position |
| `UIBridgeContainerController` | Direct directional bridge TileMapLayer children | Call Model to enter a room or control boundary module internals |
| `UIBridgeWithBoundaryController` | Its four directional bridge-mouth TileMapLayer children | Modify BridgeContainer, BridgeBoundary or fixed Boundary children |
| `UIBridgeBoundaryController` | Its four directional bridge-edge TileMapLayer children | Block the walkable bridge center or modify bridge visuals |
| `UIGroundController` | Direct Ground TileMapLayer children | Modify Obstack, bridge or boundary modules |
| `UIObstacleController` | Direct Obstack TileMapLayer children | Modify Ground, bridge or boundary modules |
| `UIBoundaryController` | Direct fixed Boundary TileMapLayer children | Read the bridge connection mask to toggle the fixed Boundary |

Keep the historical scene node name `Obstack` unless a complete script, scene, resource, NodePath and dynamic-reference audit proves that a rename is safe. The controller filename remains `UIObstacleController.gd`.

## Direction state and collision contract

“关闭桥口 Boundary” means disable the blocking part across the walkable bridge mouth so the bridge center can be crossed. It does not mean disable the bridge or make the whole direction physically impassable. The Ground fixed Boundary remains unchanged; BridgeBoundary supplies the narrow bridge's side limits.

| Map Model connection for direction | BridgeContainer | BridgeWithBoundary | BridgeBoundary | Fixed Boundary |
|---|---|---|---|---|
| No connection | Hide that direction's bridge | Keep the bridge-mouth blocker active | Disable that direction's bridge-edge layer | Keep scene-authored state; do not toggle |
| Connected | Show that direction's bridge | Disable the blocker across the bridge mouth | Enable the two side limits; leave bridge center clear | Keep scene-authored state; do not toggle |

Collision requirements:

- Configure collision only on actual blocking terrain-boundary tiles, obstacle tiles and the two sides of a bridge.
- Walkable Ground and the bridge center must not have collision that blocks the player.
- BridgeWithBoundary must block a missing bridge direction and must stop blocking the bridge center for a connected direction.
- BridgeBoundary must protect the narrow bridge sides without closing its center path.
- Inspect the actual TileSet and used tile IDs for every room; do not add collision to every tile in a shared Ground TileSet.
- Verify TileSet physics layer/mask against the player's collision layer/mask. Do not assume different room TileSets use identical physics configuration.

## 启动、移动与跨房数据流

### 启动和场景配置

1. `MapPositionCreate` 按现有规则生成房间坐标、场景类型和 `scene_to_scene` 连接；本任务不改生成算法。
2. `MapWorldModel` 从这些结果建立房间资源和方向连接查询，并为视图需要的坐标提供 MapSceneResource、PackedScene 与 RoomContext。
3. `UIMapWorldView` 实例化起始房间及有效 3×3 邻域中的完整场景，并使用房间步长 `Vector2(1280, 720)` 计算房间原点。
4. View 仅调用实例根节点 `configure_room_context(context)`；根脚本薄转发至 MapContainer 的公开配置入口。
5. `UIMapContainerController` 把 RoomContext 分发给 Ground、Obstacle、Bridge、BridgeWithBoundary、BridgeBoundary、Boundary Controller。各 Controller 只操作自己的直接 TileMapLayer。

### 玩家跨房

1. 玩家继续由原有 WASD 脚本自由移动；实际阻挡只来自瓦片碰撞。
2. `UIMapWorldController` 观察玩家 global_position，将其换算为候选地图坐标；换算必须使用 Model 的统一房间尺寸和坐标原点规则。
3. 候选坐标变化时，Controller 调用 Model 的跨入校验。Model 必须确认目标房间存在、与当前房间直接相邻，且生成连接数据包含该方向。
4. 校验成功后，Model 更新 current_position 并发出 current_room_changed；它不修改玩家位置。
5. `UIMapWorldView` 补齐新中心的有效 3×3 场景，然后回收窗口外节点，更新 current_scene 等兼容字段并通知 on_entered_room 观察者。
6. 小地图、地形棋盘和背景解析器沿用现有兼容信号/字段更新显示；不得把显示刷新误作玩家传送。

校验失败时不更新 Model.current_position、不发成功信号、不移动玩家。桥画面开放、BridgeWithBoundary 开口和 Model 连接数据必须一致；场景配置缺少对应方向的桥时要作为配置错误发现，不能静默留下可穿越空隙。

## 缓存和实例生命周期

| 所属层 | 保存内容 | 释放/复用规则 |
|---|---|---|
| `MapWorldModel` | 每个地图坐标的 MapSceneResource；每条场景路径共享一份 PackedScene | 不随 3×3 窗口变化释放；回访同一路径时复用 |
| `UIMapWorldView` | 当前中心及有效八邻域的已实例化房间 Node2D | 房间离开 3×3 窗口后释放；回访时通过缓存 PackedScene 重新实例化 |

禁止把 3×3 之外的完整 Node 场景树放进长期缓存；长期缓存的是场景资源，不是运行时房间实例。

## 依赖与引用审计范围

开始改动前必须静态检索以下引用，不得只检查 GDScript：

| 被检查对象 | 必须检查的来源或消费者 | 目的 |
|---|---|---|
| 地图生成和方向 | `MapPositionCreate.map`、`scene_to_scene`、`start_position`、方向索引及其所有调用方 | 确保连接方向掩码和房间场景方向完全一致，生成算法不变 |
| 场景资源解析 | `MapTypes`、normal biome/scene 配置、`MapSceneResource`、`MapWorldModel` | 确保每个地图坐标仍取得原来对应的完整场景资源 |
| 世界 View/Controller | `UIMapWorldView`、`UIMapWorldController`、`UIMapControl`、MapControl/MapInstantiator 的 NodePath 和外部注入字段 | 确保玩家位置观察、当前房间更新、缓存和旧入口兼容 |
| 房间初始化 | `map_env_base.gd`、场景根节点脚本字段、`configure_room_context`、RoomContext 的动态调用点 | 确保根节点转发入口不破坏地形配置和 `initialize_scene()` |
| 当前房间消费者 | `current_scene`、`current_position`、`map_scene`、`on_entered_room`、UIMapLittle、RoomBoardPresenter、背景解析器 | 保持小地图、地形棋盘、背景读取当前房间的协议 |
| 场景节点/资源 | 全部 12 个唯一 normal `.tscn`、节点名、NodePath、外部脚本 UID、TileSet `.tres` 与项目资源引用 | 找出房间方向桥、子层数量、TileSet 和 Obstack 的差异 |
| 旧流程 | Door、Transpoint、MapButton、PassageGuard 及其测试和场景接线 | 保留旧文件和兼容引用，但确认新自由跨房链路没有调用它们 |

检索范围至少包含 `.gd`、`.tscn`、`.tres` 和 `project.godot`。动态 `call`、字符串形式的方法/信号名以及运行时组查找不能只靠 `rg` 证明安全，必须做对应编辑器运行验证。脚本、节点、信号或资源字段重命名之前，必须先完成引用审计；本计划默认不重命名历史节点 `Obstack`。

## 执行步骤

- [x] **1. 盘点范围与依赖。** 检查 12 个唯一 normal 房间的 `MapContainer` 节点、六类模块容器、方向 TileMapLayer、TileSet 和 `Obstack` 容器；逐项记录差异，不根据单个 `clear_creek.tscn` 推断其他场景相同。
- [x] **2. 完成静态引用审计。** 对计划修改的 `class_name`、脚本路径、公开方法/信号、NodePath、资源 UID 和节点名，在 `.gd`、`.tscn`、`.tres`、`project.godot` 中检索；重命名须覆盖序列化引用。动态 `call`、字符串方法名和信号连接留到编辑器运行时验证。
- [x] **3. 核对碰撞资源。** 从实际 TileSet 与瓦片数据确认 Ground 固定边界、BridgeWithBoundary 桥口阻挡、BridgeBoundary 窄桥两侧、Obstacle 障碍各自对应哪些瓦片；记录玩家 collision layer/mask。不得给整张 Ground 或可走桥面统一添加阻挡碰撞。
- [x] **4. 实现纯数据上下文。** 新增 `RoomContext`，传递房间坐标、方向连接掩码、房间尺寸和场景资源，不包含 Node 或玩家引用；不新增 RoomTraversalProfile 或按矩形推算的房间墙数据。
- [x] **5. 实现 Model 连接协议。** 让 `MapWorldModel` 从既有地图生成结果读取房间资源和邻接连接，校验跨入目标必须有效且有双向连接；生成算法及 normal 场景选择规则保持不变。
- [x] **6. 实现单一职责 View Controller。** 新增 `UIMapContainerController` 协调同一 RoomContext，并新增 `UIBridgeContainerController`、`UIBridgeWithBoundaryController`、`UIBridgeBoundaryController`、`UIGroundController`、`UIObstacleController`、`UIBoundaryController`。每个模块只操作自己容器的直接子节点；公共类、方法和函数添加中文 GDScript 文档注释。
- [x] **7. 固化方向状态表。** 有连接：显示方向 Bridge，关闭该方向阻挡桥口的 BridgeWithBoundary，启用该方向 BridgeBoundary 两侧碰撞；无连接：隐藏 Bridge，保留 BridgeWithBoundary 的桥口阻挡，关闭不存在的 BridgeBoundary。Boundary 承载的 Ground 常设边界始终保持场景配置，不读取或改变连接状态。桥中心始终无阻挡碰撞。
- [x] **8. 接入房间初始化。** 由 `map_env_base.gd` 提供稳定的 `configure_room_context(context)` 转发入口；UIMapWorldView 只调用房间根入口，不查找模块内部 TileMapLayer。MapContainer 按固定顺序把上下文分发给六个子模块，重复初始化必须幂等。
- [x] **9. 接入所有 normal 场景。** 对 12 个唯一场景逐个挂载其实际存在的模块控制器、核对四方向节点名和 TileSet；需要空容器时先确认该房间的场景设计，再补一致入口。保留历史节点名 `Obstack`，除非完整引用审计另行证明可安全改名。
- [x] **10. 逐类配置瓦片碰撞。** 在场景实际使用的 TileSet 中，仅给地形边界、障碍、桥两侧配置与玩家匹配的碰撞；保持可行走地面和桥中心无碰撞。验证 BridgeWithBoundary 的连接态确实移除桥口阻挡，而非封死桥道。
- [x] **11. 增加契约测试。** 覆盖方向掩码映射、连接/无连接状态表、Ground Boundary 不受连接状态影响、桥中心无碰撞、桥侧有阻挡、重复上下文幂等和无效跨房拒绝。
- [x] **12. 编辑器验证。** 开始验证前用 `editor_state` 或 `session_manage(op="list")` 确认 Godot 4.7.1 编辑器已打开并加载项目；未连接时先请用户打开，不运行命令行 Godot。通过编辑器 MCP 刷新资源并验证 `clear_creek.tscn`、一个实际布局有差异的 normal 场景（当前 12 个房间均有完整四向桥，未臆造缺桥资源）、`ordinary_wetland.tscn` 和 `Main.tscn`。测试无桥方向、有效窄桥中心和桥两侧，并检查游戏日志。
- [x] **13. 收尾检查。** 只用 `project_manage(op="stop")` 停止运行中的游戏，不关闭 Godot 编辑器。重新检查 `git status`，确认编辑器没有带入无关改写，保留用户原有工作区改动。

## 验收场景

- 四个方向的连接掩码都映射到正确的 Left/Right/Up/Down TileMapLayer；相邻房间的连接关系必须互相对应。
- 无连接方向：方向桥隐藏、BridgeWithBoundary 保留桥口阻挡、BridgeBoundary 不启用；玩家无法从桥口离开房间。
- 有连接方向：方向桥显示、桥口阻挡关闭、桥侧边界启用；玩家能沿窄桥中心进入相邻房间，不能从桥侧离开。
- 同一房间在上下文更新前后，固定 Boundary 的显示与碰撞不变。
- 可走 Ground 和桥面中心没有阻挡玩家的碰撞；实际边界、障碍和桥侧能阻挡玩家。
- Model 拒绝 void 坐标、超出地图坐标、非相邻目标、无连接目标及缺失场景资源；拒绝时不改 current_position、不发成功变更信号、不移动玩家。
- 玩家过桥前后 global_position 连续；新中心的有效 3×3 房间已实例化；窗口外 Node2D 被释放但 MapSceneResource/PackedScene 保留并可复用。
- `current_scene`、`current_position`、`map_scene`、`on_entered_room` 继续服务 UIMapControl、UIMapLittle、地形棋盘和背景解析器；旧传送门和驻守战斗没有进入新跨房调用链。
- 12 个唯一 normal 场景均完成静态节点和 TileSet 盘点；运行验证至少覆盖 `clear_creek.tscn`、`ordinary_wetland.tscn`、一个节点/桥向布局有差异的 normal 场景及 `Main.tscn`。
- Godot 4.7.1 编辑器日志中没有本次变更引起的 `SCRIPT ERROR`、Parse Error、Failed to load script 或资源加载错误。

## 保留接口与兼容边界

- `UIMapWorldController` 文件末尾预留 `can_enter_room_with_boundaries(...)` 和 `request_passage_guard_encounter(...)` 两个后续接口。当前移动流程不调用它们；它们不替代本次配置的 TileSet 碰撞。
- 保留旧 `MapButton`、`DoorController`、`Door`、`Transpoint` 和 PassageGuard 实现及其现存引用；只确认新跨房链路不依赖它们，不在本任务中删除或重写。
- 保持根场景 `map_env_base.gd` 的 `scene_type`、`terrain_profile`、`initialize_scene()` 等既有职责。新房间上下文只通过薄转发入口加入。
- 保持 MapControl 对玩家的既有注入和外部接口；若静态引用审计证明 `UIMapControl.gd` 或 `UIMapLittle.gd` 必须改动，限定为兼容信号/坐标更新，不把房间模块逻辑塞进去。

## 计划文件

### 新增脚本与测试

- `core/map/room_context.gd`
- `scripts/map_scripts/UIMapContainerController.gd`
- `scripts/map_scripts/UIBridgeContainerController.gd`
- `scripts/map_scripts/UIBridgeWithBoundaryController.gd`
- `scripts/map_scripts/UIBridgeBoundaryController.gd`
- `scripts/map_scripts/UIGroundController.gd`
- `scripts/map_scripts/UIObstacleController.gd`
- `scripts/map_scripts/UIBoundaryController.gd`
- `tests/godot/test_room_module_controller_contract.gd`

### 修改脚本、场景与资源

- `core/map/map_world_model.gd`：连接校验、房间资源和 RoomContext 查询。
- `resources/map/map_scene_resource.gd`：房间场景路径和固定尺寸，不存节点或边界开口配置。
- `scripts/map_scripts/UIMapWorldView.gd`：保持当前 3×3 活跃实例窗口，并经根节点入口初始化房间模块。
- `scripts/map_scripts/UIMapWorldController.gd`：把玩家实际跨越与 Model 连接校验衔接起来；不传送、不扣行动值、不触发驻守战斗，预留接口仍放文件末尾。
- `scripts/map_scripts/map_env_base.gd`：只转发 RoomContext，保留现有地形与初始化兼容行为。
- `scenes/map_scenes/map_control.tscn`：保持现有玩家、Model、View 兼容接线。
- `scenes/map_scenes/map_env/normal/**/*.tscn`：接入模块 Controller 并保留已生成瓦片布局。
- 上述场景引用的 TileSet 资源：按已核对的瓦片类别添加边界、障碍和桥侧碰撞。

## 不在本计划内

- 不改 `MapPositionCreate` 生成规则或 normal 群系场景选择。
- 不把房间改为按瓦片实例化；不改变 1280×720 房间步长和 3×3 活跃场景窗口/资源缓存策略。
- 不改玩家 WASD 移动脚本，不增加旧传送点流程。
- 不删除旧 `MapButton`、`DoorController`、`Door`、传送点或驻守战斗代码；新跨房路径不接入它们。
- 当前边界限于 normal 群系，不扩展其他生态。

## 本轮实现与验证记录

- 已逐个静态盘点全部 12 个 normal 房间；当前文件均具备完整四向桥及六类模块。旧文档中的缺桥/缺障碍容器假设不适用于当前场景，因此没有补画或重排瓦片。
- 为场景内实际使用的桥口、桥边、固定边界和障碍瓦片配置物理层 32、掩码 16；Ground 和桥面仍无碰撞。桥边使用外侧半格，容纳玩家 100×140 的真实碰撞框。
- MapContainer 在切换状态前先调用各模块的 validate_room_context；所有模块通过后再按顺序传递同一上下文。房间根入口返回 bool，View 拒绝失败实例并在配置成功后才加入场景树。
- Model 拒绝未双向连接或缺失场景资源的目标。Controller 对未变化的候选坐标不重复请求，跨房不修改玩家位置。
- 用户在本轮明确回复「允许调整初始出生点」；仅在 Main.tscn 的 PlayerChar 序列化节点设置 position=Vector2(640,360)。该位置已按起始 ordinary_market 场景的碰撞几何核对，不代表其他房间也应使用这个出生点。
- 新增 tests/godot/test_room_module_controller_contract.gd 和 tests/godot/test_map_world_contract.gd，共 12 个用例，覆盖全部方向组合、模块幂等、真实瓦片碰撞、玩家尺寸、上下桥拼接、非法进入、信号兼容和缓存回收。
- 已通过：12 个场景的外部资源/子资源引用、瓦片物理层、桥中心和双侧阻挡的静态几何检查；git diff --check。
- 初轮因权限策略阻塞；用户开放权限后已完成 filesystem_manage(scan)、test_run、game_eval、project_run 和日志检查。新增顶层测试入口，并在新游戏进程逐个 await 执行真实场景/物理用例：12 个全部通过、30,725 个断言、0 脚本异常。没有截图、生图或命令行 Godot。
- clear_creek、ordinary_wetland、forest_path、map_control、Main 冒烟完成；Main 原移动输入往返过桥，坐标连续、9 个活跃房间、窗口外节点释放、回访复用资源、时间不扣。最终游戏日志无新增错误和警告。Task 标为 completed，PRD 验收勾选；仅停止游戏，保留编辑器。详见 runtime-validation.md。
