# Design: Battle selection cancellation and action recovery

## Selection cancellation

`CardManager` 继续是点击模式临时输入状态的唯一拥有者。

- `_select_click_mode_card` 接收到与 `_selected_click_card` 相同的节点时，调用现有 `clear_click_selection()` 后立即返回。该出口已经负责归位、高亮清理与操作栏隐藏，因此不复制任何清理逻辑。
- `_select_click_mode_target_at_mouse` 先解析本次命中的怪物父节点；如果它与 `_selected_click_target` 相同，则把目标设为 `null`，否则保存新目标。两种情况都调用现有 `_update_click_mode_target_highlights()`，使空目标自动复用“默认自己”的预览规则。

## Fatal-hit recovery

当前顺序在 `ApplyEffect` 之后播放 `CardAnimations.hit`。致死效果会同步调用 `Monster.QueueFree()`，该调用会终止绑定到敌人节点的 Tween，使外层 `await` 失去完成信号，`BattleManager` 因而一直持有输入锁。

将显式敌人卡牌行动调整为：

```text
验证有效敌人
  → CardAnimations.play_card 飞行
  → CardAnimations.hit 抖动与闪白
  → SkillCardData.ApplyEffect（可能删除怪物）
  → DeckManager.complete_played_card 渐隐弃置
```

受击反馈代表“卡牌已命中”的瞬间，在伤害数值应用前播放不会改变技能目标、伤害数值、卡牌弃置或行动队列所有权。`DeckManager` 在飞行和受击入口均检查 `is_instance_valid` 与 `is_queued_for_deletion`，当目标在表现前失效时安全返回；BattleManager 仍会执行现有技能结算和唯一的弃牌收尾。

## Compatibility

- `Action.presentation_card` 仍然只对 `CARD` 行动可选；`SKILL` 和 `ATTACK` 不进入新增展示分支。
- 自身、全体、随机、扩散卡牌的 `has_enemy_card_presentation` 为 false，因此保持原有结算和弃牌时序。
- 不改动 `Monster.HandleDeath`，因为其同步释放是现有怪物生命周期契约；修复位于等待它的展示层顺序。

## Rollback

若新受击顺序造成不可接受的视觉效果，只需恢复 BattleManager 中受击调用的位置；选择撤销与目标删除防护可以独立保留。
