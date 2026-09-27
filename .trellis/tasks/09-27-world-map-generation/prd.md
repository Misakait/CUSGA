# 大小地图生成与共享画布

## Goal

把现有地图生成结果转换为一套可复用的二维地图画布，并分别嵌入用户已经制作的 `MiniMap.tscn` 与 `LargeMap.tscn`。本轮先完成房间图片与连接桥的生成、当前房间表现和两种地图视图的基础接线；后续图钉、迷雾、拖拽缩放等功能只保留清楚的扩展边界，不提前实现。

## Background

- 用户提供的《大小地图重构.txt》是参考架构，不是可以直接覆盖项目现状的实施指令。
- 当前项目的权威地图数据源是 `MapPositionCreate.map`、`MapPositionCreate.scene_to_scene` 和 `MapWorldModel.current_position`。
- 地图坐标继续使用 `Vector2i(row, column)`；画布横坐标取 `column`，纵坐标取 `row`。
- 房间连接顺序继续使用上、右、下、左，对应索引 `0、1、2、3`。
- 用户已经创建以下场景，本任务在其现有结构上接线，不把结构差异当成错误：
  - `scenes/map_scenes/map_view/WorldMapCanvas.tscn`
  - `scenes/map_scenes/map_view/MiniMap.tscn`
  - `scenes/map_scenes/map_view/LargeMap.tscn`
- `MiniMap/MaskContainer` 与 `LargeMap/ViewportControl` 当前尚未实例化 `WorldMapCanvas`。
- `WorldMapCanvas` 当前包含 `RoomsContainer`、`PinesContainer` 和 `PlayerMarker`。保留用户已有节点命名，不因参考文档写作 `PinsContainer` 就擅自重命名。
- 临时地图素材均为 `16 × 16` 像素：
  - `res://res/room_icon/Room.png`：普通房间，绿色。
  - `res://res/room_icon/Room-With-Me.png`：当前房间，红色。
  - `res://res/room_icon/Room_Bridge.png`：互通房间之间的横向桥图片；纵向连接通过旋转同一图片表现。
- 旧 `UIMapLittle.gd` 只显示已经进入过的房间，并保留 `build_little_map`、`change_this_cell_color`、`return_this_cell_color` 和 `update_current_position` 等兼容入口；`DoorController.gd` 与旧地图按钮仍引用这些入口。
- `project.godot` 中已经存在用户新增的 `open_map` 输入动作，按键为 `M`。该未提交改动属于用户现有工作，本任务不得回退。
- 用户已经确认采用探索揭示：初始只显示起始房间，玩家成功进入新房间后，小地图和大地图都永久加入该房间；未进入的房间不显示。

## Requirements

### R1. 单一地图数据源

- 房间是否存在、房间连接和当前房间必须读取现有地图 Model/生成器，不新增一份会与 `MapWorldModel` 漂移的地图事实数据。
- 已探索房间集合由 `MapWorldModel` 统一拥有；起始房间自动加入，成功进入新房间时追加并发出信号。
- 已探索房间集合接入现有 `RunSnapshot`，继续本局后恢复所有已进入房间，而不是只恢复当前房间。
- 地图 UI 不实例化真实房间场景，不读取房间 TileMap，不通过副摄像机拍摄世界。
- 地图 UI 只生成轻量的 `TextureRect`、`Sprite2D` 或等价 `CanvasItem` 节点。

### R2. 共用场景、独立实例

- `MiniMap/MaskContainer` 下实例化 `WorldMapCanvas.tscn`。
- `LargeMap/ViewportControl` 下实例化 `WorldMapCanvas.tscn`。
- 两个 View 使用同一套画布场景和脚本，但必须是两个独立运行时实例，因为一个 Godot 节点不能同时拥有两个父节点，而且小地图与大地图需要不同的位置、缩放和裁切状态。
- 两个画布必须从同一份 Model 状态生成一致的房间与桥数据。

### R3. 房间图片生成

- 每个应显示的地图坐标在 `RoomsContainer` 下只生成一个 `RoomTemplate`，其 `RoomView` 显示房间图片。
- 普通已显示房间使用 `Room.png`。
- `MapWorldModel.current_position` 对应的房间使用 `Room-With-Me.png`；当前房间改变后，旧房间恢复为 `Room.png`，新房间切换为 `Room-With-Me.png`。
- 房间图片节点必须能由地图坐标稳定索引，重复刷新不得生成重复节点。
- 房间间距使用集中配置的画布步长，不把数值分散写在多个 View 中。

### R4. RoomBridge 连接生成

- 仅在 `scene_to_scene` 声明真实连接时生成 `Room_Bridge.png`。
- 每一对互通房间只生成一张桥图片，避免双方各生成一次造成重叠。
- 水平连接直接使用 `Room_Bridge.png`；垂直连接旋转同一图片。
- 默认显示已探索房间通往所有真实连接方向的桥，即使连接另一端尚未探索；未探索房间本身仍不生成 `RoomTemplate`。
- 保留“仅连接双方都已探索时显示桥”的可切换接口，便于后续按玩法需求选择。
- 桥节点放在对应 `RoomTemplate/BridgeContainer` 下，随模板和整个画布共同移动或缩放。
- `WorldMapCanvas`、`RoomsContainer`、`RoomTemplate`、`RoomView` 和 `BridgeContainer` 必须按直接子节点职责拆分，不把图元细节重新集中到画布根脚本。

### R5. 小地图基础表现

- `MaskContainer` 继续使用已有裁切边界。
- 小地图画布根据当前房间反向偏移，使当前房间位于遮罩中心。
- 小地图使用自己的缩放配置，不修改共享画布场景的全局默认值来影响大地图。
- 旧 `MapLittle` 的公开兼容入口必须继续可调用；旧门、旧地图按钮和其他现有调用方不得因本次重构出现缺失方法或节点路径错误。

### R6. 大地图基础表现

- `LargeMap` 能显示同一份地图生成结果，并在显示时聚焦当前房间。
- 使用现有 `open_map` 输入动作作为后续大地图开关入口；本轮至少保留稳定的公开开关/聚焦接口。
- 鼠标拖拽、滚轮缩放、图例内容、图钉编辑和更完整的暂停菜单协调不属于本轮生成范围。

### R7. 结构性扩展接口

- `PinesContainer` 保留为后续图钉容器，本轮不生成图钉。
- `PlayerMarker` 保留为后续玩家房间内精确位置或指南针显示入口；本轮用 `Room-With-Me.png` 表示当前房间，不要求计算房间内局部坐标。
- 地图画布提供刷新全部房间、显示单个房间、更新当前房间、聚焦当前房间等职责清楚的公开方法。
- 未实现的功能必须在架构文档中明确标为“后续接口”，不能写成已经完成。

### R8. 文档与兼容性

- 输出一份适配本项目的大小地图架构文档，说明 Model、共享画布、MiniMap、LargeMap、素材与扩展接口的职责和数据流。
- 同步核对并更新 `docs/游戏机制与玩法内容.md` 中与地图显示相关的当前机制；不新增伤害、冷却、概率等玩法数值。
- 不修改 `MapPositionCreate` 的地图生成算法，不修改无缝世界 3×3 房间加载逻辑，不删除旧门、地图按钮或通道战斗系统。

## Acceptance Criteria

- [ ] `MiniMap/MaskContainer` 和 `LargeMap/ViewportControl` 下各存在一个 `WorldMapCanvas` 实例。
- [ ] 两个画布对同一份地图状态生成相同的房间集合与桥集合，且运行时节点彼此独立。
- [ ] 初始只显示起始房间；成功进入新房间后，两张地图都增加该房间；未探索的非 `void` 房间不显示。
- [ ] 每个已探索房间只出现一张房间图片；重复刷新不增加重复房间或桥节点。
- [ ] 当前房间显示 `Room-With-Me.png`，离开后恢复 `Room.png`，新当前房间变为红色图标。
- [ ] `RoomsContainer` 的直接房间子节点是 `RoomTemplate`，其 `RoomView` 与 `BridgeContainer` 分别管理纹理和桥。
- [ ] 默认显示已探索房间通往未探索相邻房间的真实连接桥；可切换回仅双方已探索才显示。
- [ ] 连接桥只出现在真实双向连接之间；每对房间只有一张桥；上下连接正确旋转。
- [ ] 小地图在当前房间改变后保持当前房间居中，且内容被 `MaskContainer` 裁切。
- [ ] 大地图能够显示并聚焦当前房间；后续交互接口存在，但拖拽缩放、图钉和迷雾不会被误报为已实现。
- [ ] 旧小地图公开方法与现有调用方保持兼容，不出现本次引入的缺失方法、缺失节点或动态调用错误。
- [ ] 新增公共类、公共方法和公共函数使用中文 `##` 文档注释，并明确参数和返回值。
- [ ] 通过 Godot 4.7.1 编辑器 MCP 扫描脚本、运行针对性测试，并冒烟测试 `MiniMap.tscn`、`LargeMap.tscn` 和 `Main.tscn`；日志不得包含本次引入的 `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 或资源加载错误。
- [ ] 项目架构文档与《游戏机制与玩法内容》准确区分本轮已实现能力和后续接口。

## Out of Scope

- 美术师最终提供的按房间轮廓切分地图贴图。
- 地图迷雾、购买地图后揭示、长椅结算揭示或脚步涂抹揭示。
- 商店、长椅、收集品和自定义图钉。
- 指南针道具规则和玩家在单个房间内部的精确位置箭头。
- 大地图鼠标拖拽、滚轮缩放、图例内容和自定义标记。
- 更改地图生成概率、群系规则、房间场景选择或无缝跨房逻辑。
- 清理或删除旧门、旧地图按钮、`PassageGuardController` 和其他历史兼容代码。
