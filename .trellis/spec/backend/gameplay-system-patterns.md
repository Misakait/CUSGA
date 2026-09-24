# Gameplay System Patterns

## Model 与服务

- Model 保存领域状态、资源缓存和坐标等事实数据，并提供带合法性校验的公开方法。
- 纯规则服务使用参数和稳定协议，不依赖具体 UI 节点；需要场景树时才继承 `Node`。
- Controller 负责把输入转成一次业务调用；不要让按钮、卡牌或 View 直接扣库存、结算伤害或移动时间。
- 状态变化通过信号广播，信号参数传递最小事实数据，避免暴露内部字典和节点路径。

## 地图与场景

- 新的地图跨房规则要求目标是当前房间的直接相邻房间，且 MapPositionCreate 的连接数据明确标记该方向；只检查坐标存在不够。
- 玩家跨房只由物理移动产生；Controller 不设置或重置玩家坐标，也不触发传送、行动值扣除或驻守战斗。
- Boundary 承载 Ground 常设地形边界，不随桥连接状态变化；BridgeWithBoundary 在无连接方向阻挡桥口，有连接方向关闭桥口阻挡；BridgeBoundary 仅限制窄桥两侧。

- 地图生成规则由现有生成器提供；Map Model 保存地图坐标、资源配置缓存和共享 `PackedScene` 缓存。
- Map View 负责当前房间及周围八个房间的实例化和回收，缓存对象不等于运行时节点。
- 房间按完整场景尺寸拼接；世界坐标换算必须使用统一的 `room_size`，当前 normal 房间为 `1280×720`。
- 玩家跨越房间边界时只更新 Model/View，不自动触发旧通道驻守战斗或地图移动行动值扣除；瓦片碰撞由 Ground、Obstacle、BridgeWithBoundary 和 BridgeBoundary 的 TileSet 配置及对应 UI Controller 分工管理。

### 房间内部模块化控制器

- 完整房间仍由一个 `PackedScene` 实例化；不得把房间瓦片拆成逐瓦片运行时实例。
- `MapContainer` 是房间级协调边界；`BridgeContainer`、`Ground` 和 `Obstacle` 必须各自挂载单一职责控制器管理子节点。
- `UIBoundaryController` 只管理 Ground 常设 Boundary；`UIBridgeWithBoundaryController` 管理方向桥口阻挡；`UIBridgeBoundaryController` 管理窄桥两侧碰撞。不要把它们合并为动态矩形房间墙或写进房间根脚本。
- `UIBridgeContainerController` 只根据 RoomContext 配置方向 Bridge 的显示和通行状态；世界 Controller 从玩家连续坐标识别跨房，桥控制器不直接发起 Model 请求。
- `UIGroundController` 和 `UIObstacleController` 分别管理各自已有 TileMapLayer 及 TileSet 配置，不逐瓦片创建节点，也不修改对方的碰撞。
- 子控制器通过 `UIMapContainerController` 接收统一的 `RoomContext`；View 不直接依赖 `BridgeContainer/Ground/Obstacle` 的内部子节点路径。
- 当前 `clear_creek.tscn` 中的 `Obstack` 是历史拼写；改名为 `Obstacle` 前必须先搜索全部场景和脚本引用。

## 无缝房间跨层合同

### 1. 范围与触发条件

- 触发：地图系统在完整 TileMap 房间之间提供连续移动，同时维护以玩家所在房间为中心的 3×3 实例窗口。
- 范围：当前 normal 生态；单房间世界步长为 Vector2(1280, 720)；瓦片内容仍由完整房间场景资源提供。

### 2. 建议的公开协议

- MapWorldModel.get_scene_resource(position: Vector2i) -> MapSceneResource
- MapWorldModel.get_room_context(position: Vector2i) -> RoomContext
- MapWorldModel.is_connected(from_position: Vector2i, to_position: Vector2i) -> bool
- MapWorldModel.try_enter_room(to_position: Vector2i) -> bool
- UIMapContainerController.configure_room_context(context: RoomContext) -> bool
- 房间根节点 configure_room_context(context: RoomContext) -> bool
- UIMapWorldView.on_entered_room(position: Vector2i, scene: Node2D)

### 3. 接口合同

- RoomContext 至少包含 room_position、connection_mask、room_size 和 MapSceneResource；禁止包含运行时 Node。TileMap 开口由场景瓦片表达，不使用 RoomTraversalProfile 推算。
- try_enter_room 只接受有效且与当前房间直接连接的目标；失败时不改 current_position，也不发 current_room_changed。
- 跨房成功只更新 Model 状态并广播；玩家位置由连续物理移动产生。
- 3×3 之外必须释放房间 Node2D，但保留 Model 的 MapSceneResource 和共享 PackedScene。
- 每个模块 Controller 只管理挂载节点的直接子节点；跨模块事实通过 RoomContext 或公开信号/方法交接。

### 4. 校验与失败处理

| 条件 | 处理 |
|---|---|
| 目标为直接相邻房间且生成数据标记连接 | 更新当前坐标并广播一次 |
| 目标为 void、超出地图或非相邻坐标 | 拒绝，不修改状态 |
| 目标相邻但连接数据不含该方向 | 拒绝；隐藏该方向 Bridge 并保留 BridgeWithBoundary 桥口阻挡 |
| 房间资源或 RoomContext 缺失 | 不开放 BridgeWithBoundary 桥口；输出可定位的配置错误 |
| Bridge 未连接但对应桥口没有阻挡 | 视为场景配置错误，契约测试失败 |
| 同一上下文重复绑定 | 幂等，不重复创建节点或信号连接 |

### 5. 成功、边界与失败案例

- 成功：玩家通过已连接的 RightBridge 连续进入有效右邻房，Model 坐标变化并刷新新中心的有效 3×3。
- 边界：无连接桥向由 BridgeWithBoundary 阻挡，Ground 常设 Boundary 不变；有效桥向仅开放桥中心并由 BridgeBoundary 限制两侧。
- 失败：非相邻或未连接坐标的进入请求被 Model 拒绝，玩家坐标不被脚本改写。

### 6. 必需测试

- Model：四方向连接、void、非相邻目标、拒绝时状态不变及信号次数。
- Bridge：四方向连接掩码与四个 TileMapLayer 的显示/碰撞状态一致。
- Ground 与 Obstacle：各自只管理直接 TileMapLayer，不创建逐瓦片节点或修改对方。
- Boundary：Ground 常设边界始终不随连接状态变化；BridgeWithBoundary 管桥口；BridgeBoundary 管桥侧。
- MapContainer：同一 RoomContext 分发至各子模块且重复配置幂等。
- 场景：至少覆盖 clear_creek.tscn、ordinary_wetland.tscn 和 Main.tscn；实施前逐场景核对节点结构，不能依赖旧的 Obstack 缺失记录。

### 7. 错误与正确模式

错误：UIMapWorldView 通过房间内部 NodePath 直接修改 Bridge TileMapLayer 碰撞。

正确：UIMapWorldView 只调用根节点公开配置入口；MapContainerController 把上下文交给 BridgeController，由后者管理直接子节点。

错误：BridgeController 直接调用 MapWorldModel.try_enter_room() 或写入玩家 global_position。

正确：BridgeController 只配置桥；世界 Controller 观察连续玩家位置并调用 Model 校验。

## 交互与时间

- 需要长按确认的操作由共享长按 Controller 管理开始、取消、完成和进度显示。
- 完成回调只能在进度达到终点后触发；取消、场景退出和 owner 失效都必须清理 Tween 与缓存引用。
- 时间扣除、掉落和库存写入由 Model 的一次业务操作完成，View 不先行修改任何数值。

## 库存、制作与掉落

- ItemStack 是槽位级状态；库存 Model 负责容量、堆叠、移动和通知，UI 只绑定堆叠信号。
- 制作先计算需求并检查材料和空间，再执行一次扣除与产出；失败返回稳定原因，不产生部分副作用。
- 掉落表 Resource 只保存条目和概率，随机抽样后由领域服务创建堆叠并提交给库存或拾取入口。

## 战斗与状态

- 怪物、技能、状态效果和伤害配置使用 Resource；战斗 Controller 负责目标选择、顺序和状态机。
- 伤害、状态、闪避和暴击等结果由结算 Model 产生，表现层只能监听结果信号，不能从血条差值反推结果。
- 状态钩子按固定阶段顺序执行；同一阶段移除的状态不能在当前遍历中再次执行。

## 测试

- 纯规则用脚本夹具测试，节点生命周期、信号时序和资源反序列化用 Godot 编辑器运行测试。
- 地图测试必须覆盖坐标换算、3×3 活跃窗口、资源/PackedScene 复用和运行时节点回收。
- 每个新增公开协议至少有一条成功、一条空值或无效输入的回归断言。
