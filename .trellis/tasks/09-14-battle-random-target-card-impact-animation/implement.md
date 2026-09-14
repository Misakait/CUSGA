# Implementation plan: Battle random target card impact animation

## Ordered checklist

1. [x] 在 `BattleManager._execute_single_action` 开头识别玩家 `RandomEnemy` 卡牌，并在展示判断前解析一次局部随机目标；为新增局部变量添加独立中文职责说明。
2. [x] 让既有 `monster_target`、`has_enemy_card_presentation`、飞行和受击分支复用该局部目标，不复制动画实现。
3. [x] 调整 `target_random_enemy` 结算分支优先使用已解包的 `real_target`，只在没有预解析目标时保留原有随机回退。
4. [x] 更新《游戏机制与玩法内容》和状态管理 code-spec，记录随机目标的一次选择与表现/结算一致性。
5. [x] 静态复核随机目标解析位置、飞行与受击顺序、效果上下文、无敌人回退、旧行动类型和差异格式；本地覆盖规则禁止运行 Godot Mono、编译与自动化测试。
6. [ ] 使用 Trellis 质量检查流程，追加学习反馈与编号提交描述，提交本任务文件，归档任务并记录会话。

## Risk controls

| Risk | Control |
| --- | --- |
| 动画与伤害命中不同敌人 | 后续效果优先复用从同一局部 `target` 解包的 `real_target`。 |
| 点击的敌人错误覆盖随机语义 | 仅对 `RandomEnemy` 重写局部目标，始终重新从当前敌人列表随机。 |
| 没有敌人时访问空节点 | 复用 `_pick_random_from` 的 `null` 返回与既有展示条件、上下文回退。 |
| 影响怪物技能或其他目标类型 | 提前随机条件严格限制为玩家 `CARD` 和生成枚举的 `RandomEnemy`。 |
| 误提交他人修改 | 只暂存 `BattleManager`、文档、规范与任务记录。 |
