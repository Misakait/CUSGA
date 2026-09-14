# Battle card impact feedback

## Goal

为战斗中的卡牌选择和敌人施放提供清晰、连贯的视觉反馈，让玩家能立即识别已选卡牌，并感受到卡牌命中敌人的打击感。

## Confirmed facts

- 点击操作模式已经存在“选卡 → 选敌人 → 确定”的显式确认流程。
- 卡牌当前由 `DeckManager.play_card` 进入既有战斗行动队列，随后会进入弃牌堆并播放已有弃牌动画。
- 需要为点击模式的已选卡牌增加上移状态。
- 对敌人使用卡牌时，需要增加卡牌飞向敌人、命中打击感（例如屏幕震动）和随后渐隐进入弃牌堆的连贯表现。

## Requirements

1. 点击操作模式中，选中卡牌后将其向上移动以明确表示选中；取消、改选、切换模式、失去玩家回合或施放完成时必须恢复正常手牌布局。
2. 对敌人确认施放卡牌时，卡牌应从手牌位置飞向该敌人，而非直接消失。
3. 卡牌抵达敌人时提供可感知的命中反馈；至少包含短暂的屏幕震动，允许结合现有动画增强表现。
4. 命中反馈结束后，卡牌按现有弃牌规则进入弃牌堆并渐隐销毁，不得重复弃牌、重复扣能量或阻塞既有行动队列。
5. 对自身施放、全体/随机/扩散等没有单一显式敌人目标的卡牌，保持安全且不误飞向无效节点的现有结算路径。
6. 动画参数应集中配置，避免将时长、位移、震动幅度散落在流程代码中。

## Acceptance Criteria

- [ ] 点击选中一张可用手牌后，该卡牌可见地上移；取消或改选后，旧卡牌恢复其手牌布局位置。
- [ ] 点击“确定”向显式选择的敌人施放时，卡牌先飞向该敌人再进入弃牌渐隐动画。
- [ ] 卡牌命中敌人时可观察到短暂的屏幕震动或等效的明确打击反馈。
- [ ] 飞行/命中表现仅发生一次，并且卡牌最终只进入一次弃牌堆。
- [ ] 对自身或没有有效显式敌人目标的施放不会尝试访问无效敌人节点，且保留原有结算行为。
- [ ] 玩家输入锁定、行动队列和回合转换仍由既有 BattleManager/DeckManager 流程控制。

## Scope

包含战斗卡牌的点击选中视觉、敌人目标飞行与命中反馈、弃牌表现衔接及相关玩法文档；不包含新增卡牌效果、伤害数值、敌人 AI、音效资产或全局相机系统重构。

## Requirements

- TBD

## Acceptance Criteria

- [ ] TBD

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
