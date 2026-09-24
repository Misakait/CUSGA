# Component Guidelines

## UI 组件

- UI 脚本继承实际需要的 `Control`、`CanvasLayer` 或 `Node2D`，不把业务规则塞进按钮或标签。
- `_ready` 只解析导出路径、建立一次性子节点和连接信号；需要重复调用时必须幂等。
- 公开 `bind` 方法负责切换 Model。重新绑定前断开旧信号，绑定内容不变时直接返回。
- 重复槽位、列表和卡牌视图只在容量变化时增删节点；内容变化只刷新现有 View。
- `_exit_tree` 中断开信号、取消 Tween、隐藏提示和清理外部资源引用。

## 输入与拖拽

- View 只报告点击、按下、抬起、拖拽和取消意图；Controller 决定是否允许操作。
- 物品槽位调用库存/装备 Model 的校验和变更方法，不在 UI 重复堆叠、容量或装备规则。
- 空槽位、禁用按钮和不可用目标必须在 View 中明确反映，避免把无效输入交给业务层。

## 地图与战斗

- 复杂房间按容器拆分 UI Controller：BridgeContainer、BridgeWithBoundary、BridgeBoundary、Ground、Obstack 和 Boundary 分别有自己的模块控制器。
- 各模块控制器只管理挂载节点的直接子节点，不跨容器访问内部节点；跨模块数据使用同一 RoomContext 或公开信号。
- 只有在需要把同一上下文分发给多个模块或协调初始化顺序时，才在 MapContainer 挂载 UIMapContainerController；该脚本不得承载模块具体逻辑。
- UIMapWorldView 通过房间根节点 configure_room_context(context) 初始化房间，不直接查找各模块的内部 TileMapLayer。
- 房间根脚本只保留现有场景元数据、初始化兼容行为和薄转发入口，不得集中实现所有房间功能。
- normal 房间作为 1280×720 的完整 TileMap 场景拼接。Boundary 承载 Ground 常设地形边界；BridgeWithBoundary 阻挡无桥桥口并在有桥时关闭阻挡；BridgeBoundary 只限制有效窄桥两侧，桥中心保持可通行。
- 保留历史节点名 Obstack 以兼容场景序列化引用；控制器文件名使用 UIObstacleController。任何后续节点重命名都必须先搜索场景、脚本和资源路径。

- 地图按钮只上报方向和按键生命周期；地图 Controller 负责长按、跨房间和当前坐标更新。
- 地图 View 负责实例化当前房间及周围八个房间，缓存由 Model 管理。
- 房间 View 必须按节点职责拆分 `UI` 控制器：`UIBridgeContainerController` 管理方向桥，`UIBridgeWithBoundaryController` 管理方向桥口阻挡，`UIBridgeBoundaryController` 管理桥侧边界，`UIGroundController` 管理地面 TileMapLayer，`UIObstacleController` 管理障碍 TileMapLayer，`UIBoundaryController` 管理 Ground 常设边界；`UIMapContainerController` 只负责注入统一上下文和协调初始化顺序。
- 子控制器只管理自己的直接子节点，不跨模块搜索和修改其他容器的内部节点；跨模块状态通过房间上下文或信号传递。
- 新增房间功能时先判断它属于桥、地面、障碍、边界还是房间协调；只有确实属于多个子模块的流程才放在 `UIMapContainerController`。
- 战斗管理脚本拥有战斗状态机；数据资源只提供技能、怪物和地形配置，不直接创建 UI。
- 通过信号传递完成、取消和失败事实，避免一个节点直接访问另一个节点的内部子路径。

## 工具提示和共享表现

- 复用已有提示节点和 Presenter 协议；不要为同一种提示创建第二套全局系统。
- 共享表现参数放在无状态配置脚本中，消费方通过 `preload` 读取，避免复制数值。
