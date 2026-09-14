# Battle random target card impact animation

## Goal

让随机目标卡牌对实际随机选中的敌人播放与单体卡牌一致的飞行和受击动画，并保证动画与效果结算使用同一目标。

## Requirements

- 玩家使用目标类型为 `RandomEnemy` 的卡牌时，必须对实际随机选中的仍在场敌人播放与单体卡牌相同的飞行和受击动画。
- 飞行、受击和 `SkillExecutionContext` 的伤害结算必须共用同一个随机结果；一次出牌不得为表现与效果分别随机不同敌人。
- 玩家在点击或拖拽时即使显式点中过敌人，随机目标卡牌仍保持原有“随机敌人”语义，不把点击对象改为强制目标。
- 没有可用敌人时，不播放敌人动画并保留既有以自身为安全上下文的回退规则。
- 不改变怪物技能、普通攻击、全体、扩散、自身、任意单体和常规单体卡牌的既有结算规则。
- 不关闭或重启用户正在运行的游戏进程。

## Acceptance Criteria

- [ ] `RandomEnemy` 玩家卡牌对一个实际在场敌人执行“飞行 → 受击 → 结算 → 弃牌”流程。
- [ ] 同一次随机卡牌行动的动画目标与伤害目标为同一敌人。
- [ ] 没有可选敌人时跳过敌人表现，不出现空引用、双重随机或行动队列卡死。
- [ ] 显式选择敌人不会改变随机目标卡牌的随机语义。
- [ ] 文档和状态管理规范记录“随机一次、表现与结算共用结果”的契约。
- [ ] 静态检查通过；根据项目本地规则，不运行 Godot Mono、编译或自动化测试。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
