# 技术设计：大小地图生成与共享画布

状态：用户已批准实施。需求与验收编号见 `prd.md`，执行顺序见 `implement.md`。

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
  裁切并持续居中                  M 键显示并聚焦当前房间
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

为 `WorldMapCanvas.tscn` 挂载独立脚本。脚本只把 Model 数据转换为地图 UI 节点，不实例化真实房间场景。

### 节点职责

- `RoomsContainer`：容纳房间图片和 `Room_Bridge` 图片。桥放在房间后方，保证视觉层级稳定。
- `PinesContainer`：保留用户已有拼写和节点，本轮不生成图钉。
- `PlayerMarker`：保留后续房间内精确位置/指南针接口，本轮不启用。

### 坐标和素材

- 画布坐标：`Vector2(column * room_step.x, row * room_step.y)`。
- `room_step` 作为画布导出配置集中维护，默认按 `16 × 16` 临时素材留出桥接间隔。
- 普通房间：`Room.png`。
- 当前房间：`Room-With-Me.png`。
- 桥：`Room_Bridge.png`；水平方向保持原角度，竖直方向旋转 90 度。

### 去重规则

- 房间字典：`Vector2i -> TextureRect/Sprite2D`。
- 桥键使用排序后的两个端点，保证 A→B 与 B→A 是同一条桥。
- 新房间揭示时，仅生成它的图片，以及它与“已经探索的相邻房间”之间的桥。通往未探索房间的连接不显示，避免桥提前泄露未知地图。
- 全量刷新先以 Model 的探索集合为准进行增删，再更新当前房间纹理；重复调用保持节点数不变。

### 稳定公开接口

- `bind_model(model: Node) -> bool`：绑定 Model、连接信号并刷新。
- `refresh_discovered_rooms() -> void`：按探索集合对齐全部图元。
- `reveal_room(position: Vector2i) -> void`：增量增加房间与已探索邻居之间的桥。
- `update_current_room(position: Vector2i) -> void`：切换普通/当前房间纹理。
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
- 新增地图画布/View 契约测试：房间/桥去重、桥不泄露未探索房、当前纹理切换、两个画布节点独立但结果一致、旧 `MapLittle` 方法仍存在。
- 扩展快照契约测试：探索坐标编码、解码和缺失字段兼容。
- 编辑器 MCP 刷新脚本后运行相关测试；分别冒烟 `MiniMap.tscn`、`LargeMap.tscn` 和 `Main.tscn`。
- 在 Main 运行时用 `game_eval` 核对两个画布的房间/桥数量、当前房间纹理、进入相邻房后的同步变化；用游戏截图核对裁切、居中和层级。

## 9. 文档交付

- 本 `design.md` 是本任务实施设计。
- 实施完成后，把已经验证的长期地图 UI 架构同步到 `.trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md`，使其继续作为地图系统唯一设计依据。
- 同步更新 `docs/游戏机制与玩法内容.md`，记录“只显示已探索房间、当前房间使用红色临时图标、连接只在双方均已探索时显示”的当前机制，并明确图钉、迷雾、精确玩家位置、拖拽缩放尚未实现。

## 10. 风险与回退点

- `MapSystem/CanvasLayer` 是现有协调器的固定路径，不能删除或改名；只替换其内部旧小地图显示节点。
- `MapLittle` 是旧门和地图按钮的动态调用目标，不能删除；改造后必须用运行验证覆盖动态调用。
- `project.godot`、三个新地图 View 场景、`res/room_icon/` 和旧 `little_map_me.tscn` 删除均包含用户已有未提交工作；实施时在其当前版本上增量修改，验证后重新核对 Git 状态，不回退用户内容。
- 探索状态新增到快照时必须兼容旧存档缺字段；任何恢复异常都回退为至少显示当前房间，不能阻止主场景加载。
