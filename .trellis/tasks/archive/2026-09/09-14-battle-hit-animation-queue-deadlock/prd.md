# Battle hit animation queue deadlock

## Goal

修复单体敌人受击动画同时启动后顺序 await 导致遗漏 finished 信号、永久锁住行动队列的问题。

## Requirements

- 修复玩家使用明确单体敌人目标的卡牌后，卡牌抵达敌人即永久停留、战斗输入保持锁定的问题。
- 根因必须按实际时序处理：`CardAnimations.hit` 同时启动抖动与闪白 Tween，却顺序等待它们的 `finished` 信号；较短的闪白会在开始等待前结束，信号不会补发。
- 保留既有“卡牌飞行 → 敌人抖动和闪白 → 技能效果 → 弃牌”的视觉与结算顺序。
- 修复不能依赖怪物死亡；目标血量充足时也必须让行动队列恢复。
- 不改变点击模式取消选择、卡牌消耗、弃牌数据写入或非单体目标的既有规则。
- 不关闭或重启用户当前正在运行的游戏进程。

## Acceptance Criteria

- [ ] 对仍存活的单体敌人使用卡牌时，卡牌完成飞行与受击反馈后进入既有效果结算、弃牌渐隐，玩家输入恢复。
- [ ] `CardAnimations.hit` 不会等待已经结束的 Tween 的 `finished` 信号；无论闪白先结束还是仍在运行，函数均能完成。
- [ ] 卡牌击败敌人、卡牌不击败敌人、以及无明确单体敌人目标的原有收尾规则继续成立。
- [ ] 文档与状态管理规范准确说明并行动画不能顺序等待可能已发射的瞬时信号。
- [ ] 静态检查通过；根据本项目本地规则，不运行 Godot Mono、编译或自动化测试。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
