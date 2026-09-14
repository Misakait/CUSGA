# Design: Battle card impact feedback

## Existing extension points

- `CardManager` already owns the click-mode selected card and clears it on cancellation, mode changes, and turn/input changes.
- `PlayerHand` owns hand layout and the existing discard fade/queue-free presentation.
- `DeckManager.play_card` builds an `Action`, immediately moves card data to the discard pile, then enqueues the action today.
- `BattleManager._execute_single_action` already serializes player card actions, applies the effect, and owns the input-locking action flow.
- `CardAnimations` already supplies reusable `play_card`, `discard_card`, `shake_x`, `flash_white`, and `hit` Tweens. No new animation framework or Camera2D is needed.

## Data and presentation flow

```text
点击选卡
  → CardManager 将卡牌从 hand_position 向上 Tween，并保留 selected 状态

确认对显式怪物目标施放
  → DeckManager 从 PlayerHand 数据布局中移除卡牌（不播放弃牌、不销毁）
  → Action 保存 presentation_card 节点
  → BattleManager 行动队列锁定输入
  → CardAnimations.play_card 飞向目标
  → 执行既有卡牌效果
  → CardAnimations.hit 让目标抖动并闪白
  → DeckManager 将数据写入弃牌堆
  → PlayerHand 播放现有渐隐弃牌动画并销毁卡牌节点
```

对自身、全体、随机和扩散等没有一个“显式怪物目标”的卡牌，跳过飞向敌人与敌人受击反馈，但仍在同一个行动完成出口进入弃牌堆。这样卡牌效果仍完全由既有 `SkillTargetingType` 结算器决定。

## Ownership and contracts

| Owner | Responsibility |
| --- | --- |
| `CardManager` | 点击模式选中卡牌的上移、改选/取消/失去回合时复原，以及确认时不抢占飞行动画。 |
| `PlayerHand` | 从手牌布局中移除卡牌、恢复布局、弃牌渐隐和节点销毁。 |
| `DeckManager` | 创建带 `presentation_card` 的玩家卡牌行动；在战斗完成后仅一次写入弃牌堆并调用手牌弃牌表现。 |
| `Action` | 为玩家卡牌行动保留可选的 `presentation_card: Node2D`，不改变怪物技能或普通攻击构造方式。 |
| `BattleManager` | 在已锁定的行动队列中按“飞行 → 既有效果 → 命中反馈 → 弃牌”排序。 |
| `CardAnimations` | 复用现有 Tween 原子动画；命中效果使用目标抖动与 Sprite2D 闪白作为打击感。 |

卡牌选中上移距离与时间作为 `CardManager` 导出参数集中配置。飞行、命中和弃牌时间继续复用 `CardAnimations` 的 `NORMAL`、`FAST`、`SLOW` 常量；避免在行动调度处写入新的魔法数。

## Safety and compatibility

- `Action.presentation_card` 是可选字段；所有怪物技能、攻击和旧行动构造都保持兼容。
- `DeckManager` 只有在 BattleManager 完成该卡牌行动后才将卡牌数据追加到弃牌堆，防止飞行节点被早期 `queue_free`。
- 最终弃牌方法必须校验节点有效性，并只由一个结束出口调用，防止双重数据入堆或双重节点销毁。
- 目标在飞行前失效时，跳过敌人表现，仍安全结算并弃牌。
- 本地项目规则禁止 Godot Mono、编译和自动化测试；验收通过静态流程、节点路径和变更范围审阅完成。
