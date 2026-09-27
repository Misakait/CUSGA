# 技术设计：大小地图生成与共享画布

状态：用户已批准实施。第一阶段生成能力已经提交；本设计现包含第二阶段交互与标记扩展。需求与验收编号见 `prd.md`，执行顺序见 `implement.md`。

## 1. 总体架构

```text
MapPositionCreate
  map / scene_to_scene / start_position
                    │ 初始化地图事实
                    ▼
MapWorldModel
  当前房间 / 已探索房间 / 双向连接查询
       │ room_discovered / current_room_changed
       ├──────────────────────────┐
       ▼                          ▼
MiniMap                         LargeMap
  裁切并持续居中                  open_map 动作显示并聚焦当前房间
       │                          │
       ▼                          ▼
WorldMapCanvas 实例 A          WorldMapCanvas 实例 B
  RoomsContainer                 RoomsContainer
  PinesContainer                 PinesContainer
  PlayerMarker                   PlayerMarker
```

“共用画布”指共用同一个 `WorldMapCanvas.tscn`、同一脚本和同一 Model 数据，不是让同一个 Node 同时挂在两个父节点下。小地图与大地图各自实例化一份画布节点，因此可以独立设置位置和缩放，但生成结果始终一致。

## 2. Model：探索状态与地图事实

在 `core/map/map_world_model.gd` 增加：

- `discovered_rooms: Dictionary`：键为 `Vector2i`，值为 `true`；只保存已经成功进入过的有效房间。
- `room_discovered(position: Vector2i)`：房间第一次加入探索集合时发出。
- `discover_room(position) -> bool`：校验房间有效并幂等加入；首次加入返回 `true`。
- `is_room_discovered(position) -> bool`：供 View 查询。
- `get_discovered_positions() -> Array[Vector2i]`：返回稳定排序的只读坐标副本，避免 View 直接修改字典。

初始化顺序：

1. 从生成器取得 `map`、`scene_to_scene` 和 `start_position`。
2. 从 `RunSnapshot` 恢复当前房间与已探索集合。
3. 恢复数据无效或为空时，把起始房间加入探索集合。
4. 当前房间有效但旧存档没有探索字段时，至少加入当前房间，兼容旧存档。

`try_enter_room()` 只有在原有双向连接、资源和坐标校验全部通过后，才先加入探索集合，再更新 `current_position` 并广播当前房间变化。失败请求不能泄露房间，也不能改变探索状态。

## 3. RunSnapshot：探索集合持久化

`core/gameflow/run_snapshot.gd` 的 `run_world` payload 增加 `discovered_rooms` 字段，内容为坐标字符串数组，例如 `["2,2", "2,3"]`。只序列化坐标，不序列化节点、纹理或地图画布。

增加只读恢复入口供 `MapWorldModel._ready()` 使用。旧存档缺少该字段时按“当前房间已经探索”兼容，不要求迁移存档版本，也不改变地图布局和连接恢复协议。

## 4. WorldMapCanvas：轻量地图图元

`WorldMapCanvas.tscn` 只负责绑定 Model 并把探索集合和当前房间转发给 `RoomsContainer`，不直接创建房间或桥 `Sprite2D`，也不实例化真实房间场景。

### 节点职责

- `RoomsContainer`：按探索集合管理直接 `RoomTemplate` 子节点，计算模板位置并调用桥显示策略。
- `RoomTemplate`：只协调本房间的 `RoomView` 与 `BridgeContainer`，不读取 Model。
- `RoomView`：只切换 `Room.png` 与 `Room-With-Me.png`。
- `BridgeContainer`：只管理自己的上、右、下、左桥 `Sprite2D`；桥放在 `RoomView` 后方。
- `UIWorldMapBridgeVisibilityPolicy`：无状态计算桥显示与模板所有权，不创建节点。
- `PinesContainer`：保留用户已有拼写和节点，本轮不生成图钉。
- `PlayerMarker`：保留后续房间内精确位置/指南针接口，本轮不启用。

### 坐标和素材

- 画布坐标：`Vector2(column * room_step.x, row * room_step.y)`。
- `room_step` 由 `RoomsContainer` 集中配置，默认按 `16 × 16` 临时素材留出桥接间隔。
- 普通房间：`Room.png`。
- 当前房间：`Room-With-Me.png`。
- 桥：左右使用 `Room_Bridge.png`，上下使用 `Room_Bridge_V.png`；所有方向旋转均为 0，避免像素图运行时旋转产生锯齿。

### 去重规则

- 房间字典：`Vector2i -> RoomTemplate`。
- 默认桥模式显示每个已探索房间的所有真实双向连接方向；未探索邻居没有模板，因此桥由当前已探索模板持有。
- 当连接双方都已探索时，只让 row/column 排序靠前的模板持有共享桥，保证 A→B 与 B→A 不会重叠生成。
- 模式 `1` 保留旧规则：连接双方都已探索时才显示桥；模式 `0` 恢复默认提前显示出口桥。
- 全量刷新先以 Model 的探索集合增删模板，再由模板子组件更新纹理和桥；重复调用保持节点数不变。

### 稳定公开接口

- `bind_model(model: Node) -> bool`：绑定 Model、连接信号并刷新。
- `refresh_discovered_rooms() -> void`：按探索集合对齐全部图元。
- `reveal_room(position: Vector2i) -> void`：增量增加房间与已探索邻居之间的桥。
- `update_current_room(position: Vector2i) -> void`：切换普通/当前房间纹理。
- `set_bridge_visibility_mode(mode: int) -> bool`：在默认出口桥与旧的双方探索策略间切换。
- `get_room_canvas_position(position: Vector2i) -> Vector2`：供两个 View 聚焦使用。
- `get_generated_room_count()` 与 `get_generated_bridge_count()`：供测试和运行诊断读取，不暴露可变字典。

## 5. MiniMap：裁切与当前房间居中

`MiniMap.tscn` 在 `MaskContainer` 下实例化 `WorldMapCanvas.tscn`，根节点脚本只负责 View 布局：

- 由 `UIMapControl` 显式传入 `MapWorldModel`，不从 `WorldMapCanvas` 向上猜测节点路径。
- 使用 `MaskContainer` 的实际尺寸计算中心点。
- 当前房间变化后设置：`canvas.position = mask_center - room_canvas_position * zoom`。
- 小地图缩放是 `MiniMap` 自身配置，不写回共享场景资源。

旧 `MapLittle` 节点继续存在，但改为兼容适配器：旧的 `build_little_map`、`change_this_cell_color`、`return_this_cell_color`、`update_current_position` 仍可调用；它们只通过 Model 的公开方法揭示/更新，不再创建旧 `little_map_cell.tscn` 与 `little_map_bridge.tscn` 节点。这样保留 `DoorController` 和旧地图按钮动态调用，同时避免新旧小地图同时绘制。

`MapSystem/CanvasLayer` 路径继续保留，现有世界交互协调器仍可统一隐藏 HUD；新 `MiniMap` 实例放入该 CanvasLayer，替换旧 `PanelContainer/SubViewport` 的实际显示职责。

## 6. LargeMap：基础显示与后续交互边界

`LargeMap.tscn` 在 `ViewportControl` 下实例化 `WorldMapCanvas.tscn`，根脚本负责：

- 接收 Model 并绑定画布。
- 通过现有 `open_map` 输入动作切换显示。
- 每次显示时按 `ViewportControl` 的中心聚焦当前房间。
- 使用自己的缩放配置。
- 公开 `show_map()`、`hide_map()`、`toggle_map()` 和 `focus_current_room()`。

本轮不暂停场景树，也不实现拖拽、滚轮缩放、图钉和迷雾。相应输入与容器边界保留在 `LargeMap`/`WorldMapCanvas`，后续无需修改 Model 的探索协议。

## 7. MapControl 组合与兼容

`UIMapControl.gd` 继续作为组合 Controller：

- 获取 `MapWorldModel`、MiniMap、LargeMap 和兼容 `MapLittle`。
- 在 `_ready()` 中把同一个 Model 显式绑定给三者。
- 继续转发 `UIMapWorldView.on_entered_room`，不改变棋盘、建筑、背景等消费者。
- 现有 `MapInstantiator`、`MapWorldController`、3×3 房间加载和跨房流程不变。

场景接线只修改 `map_control.tscn` 内的地图 UI 组合。用户已有 `MiniMap.tscn`、`LargeMap.tscn` 和 `WorldMapCanvas.tscn` 的根类型与主要容器不重做；仅补脚本、画布实例和为正确布局所必需的属性。

## 8. 测试策略

- 扩展 `test_map_world_contract.gd`：起始探索、成功/失败进入、幂等揭示和旧存档兼容。
- 新增地图画布/View 契约测试：RoomTemplate 结构、房间/桥去重、未探索方向桥、策略切换、当前纹理切换、两个画布节点独立但结果一致、旧 `MapLittle` 方法仍存在。
- 扩展快照契约测试：探索坐标编码、解码和缺失字段兼容。
- 编辑器 MCP 刷新脚本后运行相关测试；分别冒烟 `MiniMap.tscn`、`LargeMap.tscn` 和 `Main.tscn`。
- 在 Main 运行时用 `game_eval` 核对两个画布的房间/桥数量、当前房间纹理、进入相邻房后的同步变化；用游戏截图核对裁切、居中和层级。

## 9. 文档交付

- 本 `design.md` 是本任务实施设计。
- 实施完成后，把已经验证的长期地图 UI 架构同步到 `.trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md`，使其继续作为地图系统唯一设计依据。
- 同步更新 `docs/游戏机制与玩法内容.md`，记录“只显示已探索房间、当前房间使用红色临时图标、连接只在双方均已探索时显示”的当前机制，并明确图钉、迷雾、精确玩家位置、拖拽缩放尚未实现。

## 10. 风险与回退点

第一阶段的风险与回退点继续有效。第二阶段不得整体重建用户正在编辑的 `Item.tscn`、`LargeMap.tscn`、`pause_menu.tscn` 和 `option_panel.tscn`；只在现有结构上补脚本、子节点和必要属性。

## 11. 第二阶段：地图交互组件拆分

继续沿用“父节点协调、直接子节点各管一件事”的结构：

- `UIMiniMap`：只绑定 Model、读取缩放偏好并驱动居中 Tween。
- `UILargeMap`：只协调 Inspector 可配置的 InputMap 动作、暂停所有权、标记选择和两个子控制器。
- `UIMapPanZoomController`（挂在 `ViewportControl`）：只处理拖拽、滚轮缩放、点击坐标换算和聚焦。
- `UIMapLegend`（挂在 `LegendUI`）：只构建可滚动选项、维护选中态并发出选择信号。
- `UIWorldMapMarkersContainer`（挂在 `PinesContainer`）：只把 Model 标记快照转换成 `Sprite2D`。
- `UIMapMarkerController`（挂在场景或 `Item/MarkerController`）：只读取标记 Resource、使用 `MarkerPoint` 计算位置并注册稳定来源标记。
- `UIOptionPanel`：只读写地图偏好并发出返回请求。
- `PauseMenu`：只负责主菜单与设置页切换，不直接读写小地图节点。

## 12. 标记数据合同

`MapMarkerConfig` 是可编辑 Resource，保存标记类型与表现配置，不保存某次运行的位置。字段至少包括稳定类型键、显示名、图标、是否允许显示、当前是否激活、显示比例和是否允许玩家手动放置。

`MapWorldModel` 保存运行时标记记录，并提供添加玩家标记、注册来源标记、移除玩家标记、查询只读快照等入口。标记位置采用逻辑地图坐标：`Vector2.x` 是 column（可含房间内小数），`Vector2.y` 是 row。`WorldMapCanvas` 通过 `room_step` 把它换算为画布像素；Model 不依赖 UI 像素尺寸。

来源标记使用“来源场景 + 房间坐标 + 锚点逻辑位置”组成稳定 ID。相邻房预加载时，MarkerController 只等待探索信号；对应房间进入探索集合后才注册，防止提前泄露。

## 13. 输入与暂停

`project.godot` 当前把 `open_map` 绑定到物理键 T。`UILargeMap.open_map_action` 导出到 Inspector，脚本只调用 `event.is_action_pressed(open_map_action)`，不读取具体键码。LargeMap 记录打开前的 `SceneTree.paused`，打开时暂停并保持 `PROCESS_MODE_ALWAYS`；关闭时仅在打开前未暂停的情况下解除。拖拽、滚轮、图例与设置页均必须在暂停时可交互。

`UIMapPanZoomController` 区分点击与拖拽：移动超过导出阈值才视为拖拽；没有超过阈值的左键释放向 LargeMap 报告画布局部坐标，右键报告删除意图。滚轮缩放保持鼠标下的画布点不漂移。

## 14. 小地图过渡与设置页

小地图首次绑定立即定位；`current_room_changed` 使用 Tween 平滑移动。新的换房事件先停止旧 Tween，再从当前视觉位置移动到新中心。

缩放偏好使用 `SettingsManager` 的 `map/minimap_zoom`。OptionPanel 的地图分类通过滑条更新该键；MiniMap 监听设置变化并同步缩放与中心位置。暂停菜单只实例化和切换 OptionPanel，不直接寻找 MiniMap。

## 15. 第二阶段验证重点

- 契约测试覆盖竖桥纹理、不旋转、标记 Resource 默认值、Model 去重或删除、两个画布同步、MiniMap Tween 与缩放设置。
- 独立冒烟 `MiniMap.tscn`、`LargeMap.tscn`、`option_panel.tscn`、`pause_menu.tscn`。
- Main 运行时验证物理 T 键通过 `open_map` 动作暂停或恢复、拖拽缩放范围、标记放置或删除、两个画布标记数量一致、场景 Item 标记只在探索后出现。
- 用游戏截图检查大地图图例滚动布局、选中态、地图标记层级和选项页视觉。

- `MapSystem/CanvasLayer` 是现有协调器的固定路径，不能删除或改名；只替换其内部旧小地图显示节点。
- `MapLittle` 是旧门和地图按钮的动态调用目标，不能删除；改造后必须用运行验证覆盖动态调用。
- `project.godot`、三个新地图 View 场景、`res/room_icon/` 和旧 `little_map_me.tscn` 删除均包含用户已有未提交工作；实施时在其当前版本上增量修改，验证后重新核对 Git 状态，不回退用户内容。
- 探索状态新增到快照时必须兼容旧存档缺字段；任何恢复异常都回退为至少显示当前房间，不能阻止主场景加载。
