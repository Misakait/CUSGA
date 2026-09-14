# Implementation plan: Battle hit animation queue deadlock

## Ordered checklist

1. [x] 在 `CardAnimations.hit` 中保留并行启动的抖动和闪白 Tween，补充每个临时变量的中文职责说明。
2. [x] 立即等待抖动完成，并在之后仅对仍有效且运行中的闪白 Tween 等待 `finished`，避免错过已发射的信号。
3. [x] 为 `hit` 补全参数和返回值文档，说明其对行动队列的完成契约。
4. [x] 更新《游戏机制与玩法内容》和状态管理 code-spec，明确并行动画不得顺序等待可能已结束的瞬时信号。
5. [x] 静态复核 `hit` 的两个 Tween 时序、`DeckManager` 调用、`BattleManager` 队列收尾和差异格式；本地覆盖规则禁止运行 Godot Mono、编译与自动化测试。
6. [ ] 使用 Trellis 质量检查流程，追加学习反馈与编号提交描述，提交本任务文件，归档任务并记录会话。

## Risk controls

| Risk | Control |
| --- | --- |
| 修改等待逻辑后闪白可能被提前跳过 | 只有 `is_valid()` 且 `is_running()` 时才等待；已经结束说明视觉已完成。 |
| 改动破坏受击视觉 | 保留 `shake_x` 和 `flash_white` 的原有调用、参数和并行启动方式。 |
| 再次锁住行动队列 | 不再对已结束 Tween 的 `finished` 执行 `await`。 |
| 误提交用户资源/场景改动 | 只暂存动画脚本、文档、状态规范和本任务记录。 |
