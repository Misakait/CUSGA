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

## 全屏覆盖层（滤镜、遮罩）

- **先确认宿主场景的相机**：放在默认 canvas 的全屏覆盖层会随 `Camera2D` 一起变换。相机跟随玩家移动时，覆盖层会跟着移出画面——表现为「滤镜完全没生效」，且**不报任何错**；相机固定在屏幕左上角（`top_level = true`、缩放 `1`）时才不受影响。相机不固定的场景必须把覆盖层放进 `CanvasLayer`（`CanvasLayer` 不受相机变换影响）。
- 用 `CanvasLayer` 承载覆盖层时，它默认画在**所有**默认 canvas 内容之上，因此要按 `layer` 值把它排在世界之上、其余 UI `CanvasLayer` 之下（本项目探索场景的实际取值：滤镜 `0`、小地图 `1`、HUD `2`）。同层 `CanvasLayer` 之间的顺序不确定，必须错开。
- 验证口径：移动相机后，覆盖层的 `get_screen_transform().origin` 必须仍为 `(0, 0)`；只看「覆盖层大小是否为视口尺寸」会漏掉这个缺陷。
- 全屏 `Control`（`ColorRect` 滤镜、全屏遮罩）的父级必须是普通 `Node`、`Control` 或 `CanvasLayer`，**不得直接挂在 `Node2D` 下**。
- 覆盖层的强度由**离散事件**驱动时（时间按行动值跳变、血量按回合变化），参数跨度要按**最小触发步长**校验，而不是按一整轮的总跨度设计。本项目一次移动只推进昼夜阶段的十分之一（`10 / 100`），端点色差过小会让玩家以为覆盖层根本没生效、只有跨阶段那一瞬才看得出来。为「单步可见性」写契约测试（断言相邻两步的差值不低于阈值），不要只靠肉眼看一次。
- 原因：`Control` 的 anchors 以父级 `CanvasItem` 的 `anchorable_rect` 为参考，而 `Node2D` 的该矩形是空的，全屏 anchors 会算出 `0×0`。此时节点照常进树、`visible` 仍是 `true`、`color` 也能正常读写，但**什么都不画，且不产生任何报错**——只能靠像素级验证发现。
- 兜底写法：在 `_ready` 里检测退化尺寸并自愈，例如 `set_anchors_preset(Control.PRESET_TOP_LEFT)` 后显式 `size = get_viewport_rect().size`。参考 `core/ui/filters/day_night_filter.gd` 的 `_fit_to_viewport()`。
- 层级判断：默认 canvas 内按 `z_index` 排序，而 `CanvasLayer` 的内容**永远**画在默认 canvas 之上（与 `layer` 数值是否为 `0` 无关，已实测 `map_control.tscn` 的 `layer = 0` 仍在滤镜之上）。因此「压住世界但保留 UI」的覆盖层应放在默认 canvas，并取一个高于世界内容 `z_index` 的值；若某场景的 HUD 不在 `CanvasLayer` 上（战斗场景即是），必须把 HUD 根节点的 `z_index` 提到覆盖层之上。
- 覆盖层必须设 `mouse_filter = MOUSE_FILTER_IGNORE`（枚举值 `2`），否则会吞掉其下方所有输入。
- 乘法混合的 `CanvasItemMaterial` 用 `blend_mode = BLEND_MODE_MUL`，枚举值是 **`3`** 而不是 `1`（`1` 是 `BLEND_MODE_ADD`）；写错不会报错，只会得到发白的画面。
- 全屏覆盖层的入场应直接吸附到当前应有的状态（而非播放入场动画），否则场景切换时会看到一次多余的渐变或闪烁。
