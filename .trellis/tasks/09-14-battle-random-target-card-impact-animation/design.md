# Design: Battle random target card impact animation

## Current gap

`BattleManager._execute_single_action` 在最开始依据 `action.targets[0]` 决定是否播放敌人飞行和受击。`RandomEnemy` 卡牌通常没有可用的显式敌人目标，实际随机选择则在后续 `target_random_enemy` 分支才发生。因此卡牌直接跳过敌人表现；若仅为动画提前随机、但效果分支再次随机，动画与伤害还可能命中不同敌人。

## Chosen repair

在 `_execute_single_action` 开头、构造 `monster_target` 和 `has_enemy_card_presentation` 前，仅为玩家 `CARD` 的 `RandomEnemy` 类型解析一次目标：

1. 从 `_get_enemies_for_source(action.source)` 获取当前敌人包装节点并随机选取一个。
2. 用该节点覆盖本行动的局部 `target`，让后续飞行和受击分支自然走已有单体敌人表现。
3. 后续 `target_random_enemy` 分支优先复用已经由该局部 `target` 解包得到的 `real_target`，只在不存在时保留旧的随机回退。

这样不改变 `Action.targets` 的原始输入记录，也不改变显式选中敌人对随机卡牌无效的既有语义；局部已解析目标只服务于当前行动的一致表现与结算。

## Safety and compatibility

- 仅 `action.action_type == "CARD"` 进入提前随机；怪物 `SKILL` 继续使用现有目标解析。
- 无敌人时局部目标保持 `null`，既有条件自然跳过飞行/受击，效果分支继续走自身回退。
- 复用既有 `_pick_random_from`、`_get_enemies_for_source`、`_unwrap_combat_entity` 和 `has_enemy_card_presentation`，不引入新全局状态、随机源或表现参数。
- 维持既有“飞行 → 受击 → 效果 → 弃牌”及受击 Tween 防卡死保护。
