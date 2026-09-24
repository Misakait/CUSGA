# 历史方案：地图 Model / UI View 两层架构

> 本文只保留早期讨论记录，不再是当前实施依据。后续需求明确采用 Model、View、Controller 分工，并将 BridgeContainer、Ground、Obstack 和 Boundary 按单一职责拆分控制器。当前方案见 [地图 MVC 与房间模块化架构](./map-world-mvc-architecture-2026-09-24.md)。

本文下方“Controller 并入 UIMapWorldView”等决定已被新 MVC 方案取代。

日期：2026-09-24

## 架构决定

本次不再把地图代码按传统 MVC 拆成 Model、View、Controller 三个并列层，而是按用户要求划分为两类：

1. **Model 层**：负责地图资源配置、地图生成结果、地图坐标、资源缓存和运行时地图状态。Model 不引用 UI，不操作 CanvasLayer，不直接负责画面显示。
2. **UI View 层**：负责从 Model 获取资源和状态，并将完整地图场景、小地图、当前房间背景以及房间变化通知显示出来。所有属于 UI View 的代码文件和节点脚本均以 `UI` 开头。

旧 Controller 的玩家位置监听职责并入 `UIMapWorldView` 的显示协调流程。这样运行时只有 Model 和 UI View 两个边界，玩家移动不会把显示逻辑写回 Model。

## 目录与命名

### Model 层

- `core/map/map_world_model.gd`
  - 地图网格、起始坐标、当前坐标、房间尺寸。
  - 坐标到场景资源的映射。
  - 地图场景资源缓存。
  - 当前活跃坐标集合的只读状态。

- `resources/map/map_scene_resource.gd`
  - 一份地图房间资源配置。
  - 保存场景名称、场景路径、`PackedScene` 和可扩展的房间配置字段。
  - 不保存运行时 `Node2D` 实例。

- 可选的 `resources/map/map_scene_catalog.tres`
  - 只有当多个地图世界需要共享同一份场景资源配置时才增加。
  - 当前只生成 normal 群系，不提前增加这个配置资产，避免把一次性需求扩展成全局资源系统。

### UI View 层

- `scripts/map_scripts/UIMapWorldView.gd`
  - 原 `MapInstantiator` 的替代实现。
  - 从 Model 取得 `MapSceneResource`。
  - 实例化完整房间场景，不按 TileMap 瓦片拆分。
  - 维护当前房间周围 3×3 的活跃 Node2D 实例。
  - 释放 3×3 之外的实例，但不释放 Model 资源缓存。
  - 继续提供 `current_scene`、`current_position` 和 `on_entered_room` 兼容接口。

- `scripts/map_scripts/UIMapWorldCoordinator.gd`
  - 如果需要保留独立的玩家位置监听逻辑，则使用该 UI 前缀名称。
  - 读取玩家世界坐标，通知 `UIMapWorldView` 更新当前显示窗口。
  - 不修改玩家位置，不扣行动值，不调用通道驻守战斗。
  - 边界限制和驻守战斗接口继续放在文件最末尾，当前只返回默认结果。

- `scripts/map_scripts/UIMapControl.gd`
  - 地图 UI 根节点的组合和信号转发脚本。
  - 连接 `UIMapWorldView.on_entered_room`。
  - 将房间变化转发给小地图、棋盘和其他观察者。

- `scripts/map_scripts/UIMapLittle.gd`
  - 原 `map_little.gd` 的 UI 命名版。
  - 只负责小地图单元格、连线和当前格颜色。
  - 不创建真实地图房间，不访问资源缓存。

## 运行时数据结构

```text
MapWorldModel
├── map[position] -> scene_name
├── scene_resource_cache[position] -> MapSceneResource
├── packed_scene_cache[scene_path] -> PackedScene
├── current_position -> Vector2i
└── room_size -> Vector2(1280, 720)

UIMapWorldView
└── active_instances[position] -> Node2D
```

缓存的区别必须保持不变：

- `MapSceneResource` 和 `PackedScene` 是 Model 资源缓存，可以长期保留。
- `Node2D` 是 UI View 的运行时显示实例，只保留当前房间和周围八个房间。
- 3×3 之外的节点释放后，返回该坐标时从原资源重新实例化，不重新生成地图规则，也不重新加载同一路径的 `PackedScene`。

## UI View 的显示流程

```text
玩家移动
  ↓
UIMapWorldCoordinator 读取玩家 global_position
  ↓
MapWorldModel.map_position_for_world()
  ↓
UIMapWorldView.activate_window(center)
  ↓
Model 为缺少资源的有效坐标创建 MapSceneResource
  ↓
UIMapWorldView 实例化当前坐标周围 3×3 完整场景
  ↓
UIMapWorldView 按 1280×720 设置场景位置
  ↓
更新 current_scene / current_position
  ↓
发送 on_entered_room
  ↓
UIMapLittle、RoomBoardPresenter、背景解析器更新显示
  ↓
释放窗口外 Node2D 实例
```

初始加载和跨房间加载使用同一套 `activate_window()` 流程，避免初始房间和后续房间出现两套不同逻辑。

## Model 层禁止依赖

Model 不允许引用：

- `CanvasLayer`、`Control`、`SubViewport`、`Camera2D`。
- `UIMapControl`、`UIMapLittle`、`UIMapWorldView`。
- 玩家节点和输入事件。
- `TimeSystem` 的画面效果处理。
- `PassageGuardController`、行动值或过场系统。

Model 只返回数据和状态，UI View 决定如何呈现这些数据。

## UI View 层允许依赖

UI View 可以依赖：

- `MapWorldModel` 的资源与坐标接口。
- `MapTypes` 的场景路径查询协议。
- 玩家节点的位置只读值。
- `TimeSystem` 的昼夜显示状态。
- `UIMapLittle`、`RoomBoardPresenter` 和背景解析器的显示协议。

UI View 不应把任何 UI 节点引用写入 `MapWorldModel`。

## 现有引用关系调整

```text
MapPositionCreate ──生成──> MapWorldModel
MapTypes ──提供场景路径──> MapWorldModel / UIMapWorldView
MapWorldModel ──提供资源──> UIMapWorldView
玩家位置 ──只读──> UIMapWorldCoordinator
UIMapWorldView ──发送房间变化──> UIMapControl
UIMapControl ──转发──> UIMapLittle / RoomBoardPresenter / 背景解析器
```

兼容关系：

- `RoomBoardPresenter` 继续使用房间坐标和房间场景节点生成地形棋盘。
- `current_map_background_resolver.gd` 改为读取 `UIMapWorldView.current_scene`，或由 UI 根节点提供同名兼容转发。
- `MapLittle` 改名为 `UIMapLittle`，但保留原节点路径兼容别名，避免主场景断引用。
- 旧 `MapButton`、`DoorController` 和传送点资源保留，不接入自由移动跨界流程。

## 计划修改文件

### 新增

- `resources/map/map_scene_resource.gd`
- `scripts/map_scripts/UIMapWorldView.gd`
- `scripts/map_scripts/UIMapWorldCoordinator.gd`
- `scripts/map_scripts/UIMapControl.gd`
- `scripts/map_scripts/UIMapLittle.gd`

### 迁移或重命名

- `core/map/map_world_model.gd`：保留为 Model 核心。
- `scripts/map_scripts/map_instantiator.gd`：迁移为 `UIMapWorldView.gd`。
- `scripts/map_scripts/map_world_controller.gd`：迁移为 `UIMapWorldCoordinator.gd`。
- `scripts/map_scripts/map_control.gd`：迁移为 `UIMapControl.gd`。
- `scripts/map_scripts/map_little.gd`：迁移为 `UIMapLittle.gd`。
- `scenes/map_scenes/map_control.tscn`：更新节点名称、脚本引用和兼容路径。

### 不改职责

- `MapPositionCreate` 的生成规则。
- normal 群系资源内容。
- 玩家 WASD 移动逻辑。
- 地形仓库按地图坐标保存的数据逻辑。
- 旧通道战斗和行动值系统。

## 验收标准

- Model 脚本不出现 UI 节点、CanvasLayer 或显示组件引用。
- 所有 UI View 脚本文件名以 `UI` 开头。
- UI View 只能通过 Model 资源获取场景配置。
- 当前房间周围最多 9 个完整场景实例。
- 3×3 之外只保留资源，不保留场景节点。
- 返回旧坐标时复用原 `MapSceneResource` 和 `PackedScene`。
- 当前房间、小地图、棋盘和背景显示仍能收到房间变化通知。
- 玩家跨界时位置连续，不传送、不扣行动值、不触发驻守战斗。

## 当前状态

本文件只记录架构设计，尚未修改任何游戏源码。等待架构确认后再实施文件重命名、节点重接线和运行时测试。
