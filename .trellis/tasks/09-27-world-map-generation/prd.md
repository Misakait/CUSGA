# 大小地图生成、交互与标记系统

## Goal

把现有地图生成结果转换为一套可复用的二维地图画布，并分别嵌入用户已经制作的 `MiniMap.tscn` 与 `LargeMap.tscn`。第一阶段已经完成房间图片、连接桥、探索揭示与共享画布；本阶段继续完成小地图过渡、大地图暂停与拖拽缩放、大小地图共用标记、物品或场景标记配置，以及暂停菜单中的地图选项页。

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
  - `res://res/room_icon/Room_Bridge.png`：互通房间之间的横向桥图片。
  - `res://res/room_icon/Room_Bridge_V.png`：互通房间之间的竖向桥图片；保持原始方向，不旋转横桥。
- 旧 `UIMapLittle.gd` 只显示已经进入过的房间，并保留 `build_little_map`、`change_this_cell_color`、`return_this_cell_color` 和 `update_current_position` 等兼容入口；`DoorController.gd` 与旧地图按钮仍引用这些入口。
- `open_map` 当前必须绑定物理 `T` 键；按下后打开大地图并暂停时间，再按一次关闭并恢复打开前的暂停状态。`UILargeMap` 只读取 Inspector 可配置的 InputMap 动作名，不得硬编码具体按键。
- `res://res/room_icon/Room_Bridge_V.png` 是竖直桥专用素材，上下桥不得再旋转横桥图片。
- `res://res/room_icon/room_marker/` 下的两张图片是首批可选择标记图标。
- 用户已经在 `Item.tscn` 下创建 `MarkerController/MarkerPoint`，实施时在现有节点上挂接职责，不删除或整体重建。
- 用户已经创建 `option_panel.tscn`，实施时补齐“地图”分类与小地图缩放设置，不替换成另一套设置场景。
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

- 仅在 `scene_to_scene` 声明真实连接时生成对应方向的桥图片。
- 每一对互通房间只生成一张桥图片，避免双方各生成一次造成重叠。
- 水平连接使用 `Room_Bridge.png`；垂直连接使用 `Room_Bridge_V.png`，所有桥旋转均为 0。
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

### R9. 小地图过渡与缩放偏好

- 玩家进入新房间时，小地图画布从旧中心平滑移动到新中心；首次绑定和窗口尺寸变化仍允许立即定位。
- 过渡时长与缓动参数由 `MiniMap` 导出属性配置，重复换房时安全替换旧 Tween。
- `option_panel.tscn` 提供清楚的“地图”分类、小地图缩放滑条、当前数值与恢复默认入口。
- 小地图缩放写入 `SettingsManager` 管理的本地偏好，并在游戏内即时更新；上下限和步长由选项页导出参数配置。

### R10. 大地图暂停、拖拽与缩放

- 物理 `T` 键通过 `open_map` 动作打开大地图时设置 `SceneTree.paused = true`；关闭时只恢复打开大地图之前的暂停状态。
- `UILargeMap.open_map_action` 必须导出到 Inspector；脚本只判断该动作，不读取 `KEY_T` 或物理键码。
- 大地图及其交互节点在暂停期间继续处理输入。
- `ViewportControl` 支持鼠标拖拽画布与滚轮围绕鼠标位置缩放。
- 最小缩放、最大缩放、缩放步长和拖拽判定阈值必须暴露到 Inspector。
- 每次打开大地图默认聚焦当前房间；拖拽和缩放只修改大地图实例，不影响小地图。

### R11. 共用标记 Model 与画布

- 标记事实由 `MapWorldModel` 统一管理，两份 `WorldMapCanvas` 只渲染同一份标记快照。
- `PinesContainer` 保留现有拼写并挂载单一职责标记容器脚本，生成轻量 `Sprite2D` 标记。
- 标记使用与房间步长一致的逻辑地图坐标，因此大小地图缩放和移动后仍落在同一位置。
- 标记新增、移除或激活状态变化后，两张地图通过信号同步刷新。
- 自定义标记与场景或物品标记使用稳定 ID 去重；重复注册不得生成重复图标。

### R12. 大地图标记选择与放置

- `LargeMap/LegendUI` 改为可滚动的标记选择面板；标记类型增多时不挤出屏幕。
- 每个选项显示图标与名称；当前选项使用明确的按下态和状态文字，与未选项可一眼区分。
- 玩家选中类型后，可在大地图可视区域自由点击放置多个标记；右键可删除附近的玩家标记。
- 标记选择 UI 只产生意图；新增和删除必须调用 `MapWorldModel` 的公开方法。

### R13. 可配置物品与场景标记

- 新增可由 Inspector 创建和配置的 GDScript `Resource`，至少包含：是否允许地图显示、图标、当前是否激活、显示比例；为标记选择面板补充稳定类型名与显示名。
- `Item.tscn/MarkerController` 负责读取资源、使用 `MarkerPoint` 作为位置锚点，并把有效标记注册给 `MapWorldModel`。
- `Item` 根脚本只在房间身份确定后把房间坐标转交给 `MarkerController`，不直接操作地图标记字典。
- 同一 `MarkerController` 脚本可挂到本身带标记点的其他场景；未探索房间不得因相邻房预加载而提前显示标记。
- 标记资源缺少图标、未激活或禁止显示时安全跳过，不阻断房间生成。

### R14. 暂停菜单设置入口

- `pause_menu.tscn` 在“继续游戏”和“退出游戏”之间增加“参数设置”按钮。
- 点击后在暂停浮层内显示 `option_panel.tscn`，返回时恢复暂停菜单主面板；切换设置页不得解除暂停。
- 关闭暂停菜单或退出游戏前重置设置页显示状态，避免下次打开停留在残缺页面。

## Acceptance Criteria

- [x] `MiniMap/MaskContainer` 和 `LargeMap/ViewportControl` 下各存在一个 `WorldMapCanvas` 实例。
- [x] 两个画布对同一份地图状态生成相同的房间集合与桥集合，且运行时节点彼此独立。
- [x] 初始只显示起始房间；成功进入新房间后，两张地图都增加该房间；未探索的非 `void` 房间不显示。
- [x] 每个已探索房间只出现一张房间图片；重复刷新不增加重复房间或桥节点。
- [x] 当前房间显示 `Room-With-Me.png`，离开后恢复 `Room.png`，新当前房间变为红色图标。
- [x] `RoomsContainer` 的直接房间子节点是 `RoomTemplate`，其 `RoomView` 与 `BridgeContainer` 分别管理纹理和桥。
- [x] 默认显示已探索房间通往未探索相邻房间的真实连接桥；可切换回仅双方已探索才显示。
- [x] 连接桥只出现在真实双向连接之间；每对房间只有一张桥；上下连接使用竖桥素材且不旋转。
- [x] 小地图在当前房间改变后保持当前房间居中，且内容被 `MaskContainer` 裁切。
- [x] 大地图能够显示并聚焦当前房间，并已实现独立拖拽缩放与通用标记；迷雾继续明确保留为后续范围。
- [x] 旧小地图公开方法与现有调用方保持兼容，不出现本次引入的缺失方法、缺失节点或动态调用错误。
- [x] 新增公共类、公共方法和公共函数使用中文 `##` 文档注释，并明确参数和返回值。
- [x] 通过 Godot 4.7.1 编辑器 MCP 扫描脚本、运行针对性测试，并冒烟测试 `MiniMap.tscn`、`LargeMap.tscn`、`option_panel.tscn`、`pause_menu.tscn` 和 `Main.tscn`；当前运行日志没有本次引入的脚本、解析或资源加载错误。
- [x] 项目架构文档与《游戏机制与玩法内容》准确区分本轮已实现能力和后续接口。
- [x] 小地图换房时平滑过渡；过渡过程中再次换房会停止旧 Tween 并从当前视觉位置开始新过渡。
- [x] `open_map` 当前绑定物理 `T` 键；大地图脚本通过 Inspector 可配置的动作名响应输入，没有硬编码 T 键。打开后游戏时间暂停，关闭后恢复打开前状态。
- [x] 上下桥使用 `Room_Bridge_V.png` 且旋转为 0；左右桥继续使用横桥。
- [x] 两张地图显示完全一致的玩家标记与场景或物品标记，并在变更后同步刷新。
- [x] 大地图标记面板可滚动、选中态清楚；选中后能放置多个标记，右键能删除附近玩家标记。
- [x] 标记 Resource 可在 Inspector 配置显示许可、图标、激活状态、比例、类型名和显示名。
- [x] `Item.tscn/MarkerController/MarkerPoint` 已接入，未探索的预加载房间不会提前泄露标记。
- [x] 大地图可拖拽、以鼠标为中心缩放，并遵守导出的缩放上下限。
- [x] 暂停菜单“参数设置”能进入 `option_panel.tscn` 的“地图”页面；滑条即时改变小地图缩放并持久化偏好。

## Out of Scope

- 美术师最终提供的按房间轮廓切分地图贴图。
- 地图迷雾、购买地图后揭示、长椅结算揭示或脚步涂抹揭示。
- 商店、长椅和收集品的专用图例规则；本轮只提供通用场景或物品标记配置。
- 指南针道具规则和玩家在单个房间内部的精确位置箭头。
- 地图标记跨局外永久存档、标记文字备注、标记筛选和标记数量上限。
- 更改地图生成概率、群系规则、房间场景选择或无缝跨房逻辑。
- 清理或删除旧门、旧地图按钮、`PassageGuardController` 和其他历史兼容代码。
