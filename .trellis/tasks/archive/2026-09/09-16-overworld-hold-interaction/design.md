# 局外长按交互系统设计

## 架构与边界

- `core/constants/WorldInteractionTiming.cs` 作为唯一的换算规则：`10` 游戏时间点等于 `1` 真实秒，并提供从行动值计算长按时长的纯函数。
- `core/ui/hud/WorldHoldProgressIndicator.cs` 是只负责表现的 HUD `Control`：接收 `0..1` 的进度与可见目标节点；精灵和控件分别以自身矩形右下角换算屏幕坐标，默认偏移为 `0px, 0px`，使约四分之一圆环位于目标内；再用目标原点与鼠标位置作为安全回退，不持有任何游戏结果或行动值。
- `core/gameflow/WorldHoldInteractionController.cs` 是局外输入组件：维护唯一进行中的长按、Tween、取消与完成回调，并把进度和目标节点投递给圆环 UI。它为 `ProgressIndicatorPath` 提供与主场景一致的非空默认值，并在 `_Ready` 验证路径与目标类型；新操作会取消旧操作，释放鼠标、目标失效或节点离开场景时也会清理 UI。
- `WorldInteractionCoordinator` 将棋盘地形交互映射进该组件，并为地图提供携带可见方向按钮的 `BeginWorldHoldForMap` / `CancelWorldHoldFor` 门面和 `WorldHoldCompleted(owner)` 信号。它在按下时快照实际行动值；可重复采集使用工具减免后的实际值，其他地形使用资源的 `TimeCost`；完成后才调用原有 `TerrainInteractionExecutor`。
- `map_button.gd` 仅依赖 `WorldInteractionCoordinator` 门面，将方向按钮的按下/松开映射进该组件。它经 `Object.get("MapMoveTimeCost")` 读取 C# 自动加载属性，在按下时快照目标坐标和可见按钮精灵，并在 `WorldHoldCompleted(owner)` 信号中启动原有驻守战斗、淡出和 `PassMapMoveTime()` 流程；不将 GDScript `Callable` 作为 `Object.call` 参数传入 C#。

## 数据流

```text
按下正行动值目标
  -> 计算/快照实际行动值
  -> WorldHoldInteractionController 开始 Tween
  -> WorldHoldProgressIndicator 在可见目标右下角绘制圆环
  -> 进度满：清理圆环 -> 执行原有交互

提前松开 / 新目标按下 / 目标离开场景
  -> 取消 Tween -> 清理圆环 -> 不执行、不消耗行动值
```

## 关键契约

- 行动值为 `0` 时不启动长按，保留既有即时交互；行动值为正时，真实秒数严格为 `行动值 / 10`。
- 可重复采集在开始时快照工具减免后的耗时，并将同一数值传回执行器，避免长按期间装备变化造成“等待时间”和实际扣除不一致。
- 圆环是非权威输入反馈；它不能独立扣除行动值，也不能执行采集、移动或任何 `TerrainOp`。
- 只有长按完成回调可进入原有业务逻辑。取消路径不会调用执行器、不会触发掉落或遭遇、不会切换场景。
- 仅一项局外交互可同时长按，防止同时结算多个行动值交互。

## 兼容性与回滚

- 不改动资源中的 `TimeCost`、`TimeSystem.MapMoveTimeCost` 或各交互 `BuildOps` 的业务结果。
- 保留 `ReusableGatheringInteraction.GameTimePointsPerHoldSecond` 作为兼容常量，并改为引用新的共享换算常量。
- 回滚仅需移除控制器与 HUD 圆环接线，并恢复棋盘/方向按钮的直接执行入口；资源数据无需迁移。
