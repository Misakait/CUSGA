# 地图系统 MVC 架构设计

日期：2026-09-24

## 设计依据

本设计遵循用户提供的 MVC 分工：

- **Model** 保存核心数据、资源和业务规则，不依赖 View，不创建显示节点。
- **View** 是数据的镜子，读取 Model 状态并负责可视化显示，同时只感知 UI/输入意图，不直接决定数据规则。
- **Controller** 解释玩家移动或 UI 交互意图，调用 Model 的接口，并协调 Model 与 View 的初始化和信号链路。

本功能的 UI/View 代码统一以 `UI` 开头；Model 代码不加 `UI`；Controller 由于属于地图 UI 交互桥梁，也使用 `UI` 前缀。

## 总体结构

```text
玩家移动 / UI 交互
        ↓
UIMapWorldController
        ↓ 调用业务接口
MapWorldModel
        ↓ 发射状态变化信号
UIMapWorldView
        ↓ 更新显示实例
UIMapControl / UIMapLittle / UIRoomBoardPresenter / 背景 View
```

单向职责边界：

```text
Controller → Model → View
```

View 不直接修改地图资源和核心状态；Model 不引用 View；Controller 不负责绘制房间和 UI 控件。

## 一、Model 层

### 1. `core/map/map_world_model.gd`

职责：

- 保存 `MapPositionCreate` 生成的 `map`、`scene_to_scene` 和 `start_position`。
- 管理当前地图坐标。
- 管理地图坐标到场景资源的映射。
- 为每个有效地图坐标提供唯一的 `MapSceneResource`。
- 缓存每条场景路径对应的 `PackedScene`。
- 提供地图坐标和世界坐标之间的转换。
- 返回指定坐标周围 3×3 的有效地图坐标。
- 校验目标地图坐标是否是生成结果中的有效房间。
- 通过信号广播当前地图状态变化。

禁止：

- 实例化 `Node2D` 房间。
- 调用 `add_child`、`queue_free` 或操作场景树。
- 引用 `CanvasLayer`、`Control`、`SubViewport`、`Camera2D`。
- 读取玩家输入。
- 调用通道驻守战斗、行动值或过场系统。

### 2. `resources/map/map_scene_resource.gd`

这是地图房间的资源配置对象，不是房间节点。

字段建议：

```text
scene_name       场景名称
scene_path       .tscn 路径
packed_scene     已缓存的 PackedScene
terrain_profile  房间地形配置
room_size        默认 Vector2(1280, 720)
```

同一地图坐标只创建一份 `MapSceneResource`。同一 `scene_path` 只加载一份 `PackedScene`，不同坐标可以共享该 `PackedScene`，但坐标资源对象仍然独立，便于保存坐标相关状态。

### 3. Model 信号

建议提供：

```gdscript
signal current_room_changed(position: Vector2i)
signal map_resource_created(position: Vector2i, resource: Resource)
```

Model 只广播事实，不关心谁监听、如何显示。

### 4. 其他 Model 资源

以下现有脚本继续属于 Model 或数据层：

- `scripts/map_scripts/map_position_create.gd`
- `scripts/map_scripts/map_types.gd`
- `resources/map/biome_definition.gd`
- `resources/map/map_attribute.gd`
- `core/map/room_terrain_store.gd`

它们不负责 UI。`MapPositionCreate` 的地图生成算法和 normal 群系配置不修改。

## 二、View 层

### 1. `scripts/map_scripts/UIMapWorldView.gd`

替代原 `map_instantiator.gd`，只负责房间的视觉实例。

职责：

- 监听 `MapWorldModel.current_room_changed`。
- 从 Model 获取目标坐标的 `MapSceneResource`。
- 通过 `PackedScene.instantiate()` 创建完整房间场景。
- 按地图坐标使用固定 `1280×720` 设置世界位置。
- 维护 3×3 活跃实例窗口。
- 将窗口外的 `Node2D` 从场景树移除并释放。
- 保留 `current_scene`、`current_position` 和 `on_entered_room` 兼容接口。
- 根据 `TimeSystem` 的状态更新已显示房间的背景颜色。

View 内部缓存：

```text
active_instances[position] -> Node2D
```

这个缓存只保存当前显示节点，不保存资源配置。

### 2. `scripts/map_scripts/UIMapControl.gd`

作为地图 UI 的组合根节点：

- 注入 Model、View、Controller 和玩家节点。
- 连接 Model 和 View 的信号。
- 将 View 的 `on_entered_room` 转发给棋盘、背景和其他观察者。
- 保持主场景 `MapSystem` 的兼容入口。

### 3. `scripts/map_scripts/UIMapLittle.gd`

替代原 `map_little.gd`，只负责：

- 创建小地图格子。
- 绘制小地图连接线。
- 高亮当前地图坐标。
- 调整小地图摄像机中心。

它不实例化真实房间，也不读取场景资源缓存。

### 4. 其他 View

以下脚本属于 View/Presenter，需要在迁移时统一 `UI` 命名或提供兼容包装：

- `core/map/room_board_presenter.gd` → `UIRoomBoardPresenter.gd`
- `core/gameflow/current_map_background_resolver.gd` → `UICurrentMapBackgroundResolver.gd`

它们只读取 Model/房间 View 提供的数据并更新棋盘或背景，不修改地图生成规则。

## 三、Controller 层

### `scripts/map_scripts/UIMapWorldController.gd`

替代原 `map_world_controller.gd`，作为 Model 与 View 的桥梁。

职责：

- 读取玩家世界坐标变化。
- 将玩家位置解释为目标地图坐标。
- 调用 `MapWorldModel.try_enter_room()`。
- 处理 Model 返回的有效/无效坐标结果。
- 接收旧门、按钮或其他 UI 的进入房间意图，并统一转给 Model。
- 负责启动时的依赖注入和信号连接。

Controller 不负责：

- 实例化场景。
- 移动玩家。
- 修改玩家位置。
- 绘制小地图。
- 扣地图行动值。
- 触发通道驻守战斗。

文件最末尾保留两个未来接口：

```gdscript
can_enter_room_with_boundaries(...)
request_passage_guard_encounter(...)
```

当前跨房间流程不调用这两个接口。

## 四、两级缓存设计

```text
Model：资源缓存
├── scene_resource_cache[position] -> MapSceneResource
└── packed_scene_cache[scene_path] -> PackedScene

View：显示缓存
└── active_instances[position] -> Node2D
```

生命周期：

1. Model 首次遇到地图坐标时创建 `MapSceneResource`。
2. Model 首次遇到场景路径时加载并缓存 `PackedScene`。
3. View 只实例化当前房间和周围八个有效房间。
4. 玩家进入新房间后，View 先补齐新的 3×3 窗口。
5. View 更新当前显示指针并发送进入房间通知。
6. View 释放新窗口以外的 `Node2D`。
7. Model 的资源缓存不受 View 节点释放影响。
8. 玩家返回旧坐标时，View 复用原来的资源重新实例化。

## 五、完整数据流

```text
玩家 WASD 移动
        ↓
UIMapWorldController 观察玩家世界坐标
        ↓
MapWorldModel.try_enter_room(position)
        ↓
Model 校验地图坐标并更新 current_position
        ↓
Model 发出 current_room_changed
        ↓
UIMapWorldView 获取 MapSceneResource
        ↓
View 实例化当前房间周围 3×3 完整场景
        ↓
UIMapControl 转发 on_entered_room
        ↓
UIMapLittle / UIRoomBoardPresenter / UICurrentMapBackgroundResolver 更新显示
```

玩家跨界时：

- 不传送。
- 不改变玩家坐标。
- 不扣地图移动行动值。
- 不触发通道驻守战斗。
- 不播放场景切换过场。

## 六、节点和文件迁移方案

计划新增或迁移：

```text
resources/map/map_scene_resource.gd
scripts/map_scripts/UIMapControl.gd
scripts/map_scripts/UIMapWorldView.gd
scripts/map_scripts/UIMapWorldController.gd
scripts/map_scripts/UIMapLittle.gd
core/map/UIRoomBoardPresenter.gd
core/gameflow/UICurrentMapBackgroundResolver.gd
```

计划更新：

```text
core/map/map_world_model.gd
scenes/map_scenes/map_control.tscn
scenes/Main.tscn 的地图节点引用
tests/test_seamless_map_world.gd
scenes/map_scenes/map_env/normal/**/*.tscn
```

旧脚本不会直接删除。迁移顺序是：

1. 新建 `UI` 前缀脚本。
2. 更新场景引用和节点名称。
3. 运行引用审计和 Godot 测试。
4. 为旧调用者保留最小兼容包装。
5. 确认所有调用方迁移后，再决定是否删除旧文件。

## 七、依赖关系

```text
MapPositionCreate ──生成地图──> MapWorldModel
MapTypes ──提供场景路径──> MapWorldModel
MapWorldModel ──发出状态信号──> UIMapWorldView
玩家位置 ──被观察──> UIMapWorldController
UIMapWorldController ──调用──> MapWorldModel
UIMapWorldView ──发出显示事件──> UIMapControl
UIMapControl ──转发──> UIMapLittle / UIRoomBoardPresenter / UICurrentMapBackgroundResolver
```

Model 不依赖 View；View 依赖 Model；Controller 同时依赖 Model 和 View 的稳定接口，但不持有显示节点内部细节。

## 八、验证标准

- Model 文件没有 UI 节点和渲染逻辑。
- UI/View/Controller 新文件以 `UI` 开头。
- Controller 通过 Model 接口更新地图状态。
- View 通过 Model 资源刷新显示。
- 当前房间周围最多九个完整场景实例。
- 3×3 外没有运行时房间节点，但资源缓存仍存在。
- 返回旧房间时复用原 `MapSceneResource` 和 `PackedScene`。
- `current_scene`、小地图、棋盘和背景显示保持兼容。
- 玩家位置连续，不传送、不扣行动值、不触发驻守战斗。

## 当前状态

## 实施状态

编辑器初始检查通过：Godot 4.7.1、CUSGA 项目、MCP ready、游戏 stopped。随后已开始按本架构实施，已完成以下源码迁移：

- 新增 `resources/map/map_scene_resource.gd`。
- 扩展 `core/map/map_world_model.gd`，加入资源缓存、PackedScene 缓存、3×3 坐标查询和状态信号。
- 新增 `scripts/map_scripts/UIMapWorldView.gd`、`UIMapWorldController.gd`、`UIMapControl.gd`、`UIMapLittle.gd`。
- 将旧地图脚本改为兼容包装，保留旧路径和旧节点名。
- 将房间棋盘和背景解析器迁移为 `UIRoomBoardPresenter.gd`、`UICurrentMapBackgroundResolver.gd`，旧路径保留兼容包装。
- 更新 `map_control.tscn` 和 `Main.tscn` 的新 UI 脚本引用。
- 增加无缝地图资源缓存和 MVC 边界契约测试。

Godot 4.7.1 编辑器重新连接后，已改用真实场景运行验证，不再调用会导致编辑器断开的 `test_run(suite="seamless_map_world")`：

- `map_control.tscn` 成功启动，生成 22 个 normal 房间配置，无新增脚本解析、资源加载或运行时错误。
- 初始坐标的有效 3×3 窗口包含 9 个完整房间实例，房间世界步长为 `1280×720`。
- 运行时断言确认初始窗口包含 9 个实例，房间根节点和所有活跃 TileMap 的位置误差均为 0。
- 移动到 `(7, 8)` 后，3×3 窗口外节点被释放，活跃实例降为 7 个；被释放坐标的 `MapSceneResource` 和共享 `PackedScene` 仍在缓存中。
- 返回 `(7, 6)` 后，活跃实例恢复为 9 个；原 `MapSceneResource`、`PackedScene` 被复用，运行时房间节点重新实例化。
- `Main.tscn` 成功启动，`MapSystem` 正确注入并由 Controller 观察 `Main/PlayerChar`。
- 玩家从 `x=1200` 连续向右移动到约 `x=1346.7`，实际跨过 `1280` 边界；Model 与 View 自动从 `(7, 6)` 更新到 `(7, 7)`，玩家坐标未被传送或重置，活跃实例仍不超过 9 个。
- 画面验证发现 normal 房间的 `MapContainer` 原为普通 `Node`，导致 TileMap 不继承房间根节点位移；现已统一改为 `Node2D`，并移除标题的 `top_level`。复测中所有活跃 TileMap 的全局坐标均与各自房间根节点一致，边界两侧场景同时可见。
- 最终游戏日志没有新增脚本解析、资源加载或运行时错误，编辑器日志没有新增错误。编辑器中已有的 `shop_trade_tests.gd` 与 `test_gold.gd` 的 `ItemData` 错误属于本任务前已存在的问题，本次未修改。
- `seamless_map_world` 是 `tests/test_seamless_map_world.gd` 返回的契约测试套件名，不是场景名或新功能名；本次按项目约束不再调用该测试套件，改用 Godot 4.7.1 编辑器中的真实场景运行、`game_eval`、输入注入、日志和截图完成验收。
- 最终已停止游戏，Godot 编辑器保持打开并回到 `ready/stopped` 状态。
- 仓库中不存在 `.sln`、`.csproj` 或 `.cs` 文件，因此没有可执行的 C# 编译目标。
