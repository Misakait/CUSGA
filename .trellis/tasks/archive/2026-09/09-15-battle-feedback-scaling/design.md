# 战斗反馈数值曲线与多段一致性技术设计

## 1. 设计目标

本次只改变表现层如何解释已结算的数值，不改变 `DamageEffect`、`DamageReceiverComponent`、技能目标范围或行动时序。每一个 `DamageResolutionResult` 都进入同一套完整的反馈链；段号与范围不再降低、延后或跳过任何表现。

核心原则：

- 显示的绝对数值越高，反馈越强；相同数值面对任何目标拥有相同表现强度。
- 数值强度曲线连续、单调且饱和，任何超高数值均不会突破 Inspector 配置的最大表现。
- 同帧多段和范围事件不能相互吞掉。局部目标反应、浮字和全局震屏各自使用可顺序消费的表现通道，而不是取消旧 Tween。
- 暴击、击杀和护盾破裂仍负责颜色、粗体、下划线与额外加成，但不再替代数值曲线。

## 2. 数值强度曲线

`CombatFeedbackProfile` 提供一个以绝对数值为输入的统一函数：

```text
normalized = 1 - exp(-amount / response_reference_amount)
intensity  = lerp(minimum_feedback_intensity, 1, clamp(normalized, 0, 1))
```

默认 `response_reference_amount = 20`、`minimum_feedback_intensity = 0.18`。

- `1` 点数值保持最小可读冲击；`10` 点已呈现明确的中强反馈；`20` 点约进入曲线的 70% 区间；`60` 点以上逐步接近最大值。
- `amount` 允许任意正整数，但 `normalized` 始终被限制在 `0..1`，所以不会因后期数值膨胀而越过配置上限。
- 治疗输入为生命实际增加值；完全护盾输入为吸收值；部分护盾的伤害浮字和灰色护盾浮字各按自己的显示数值计算，目标受力/屏幕冲击使用两者之和，反映一次命中的总碰撞量。
- 闪避没有数值输入，保持固定的白色轻量表现；治疗只缩放浮字，不产生受击、震屏或 Hit Stop。

所有效果从同一 `intensity` 映射，而非以固定“普通/重击”阈值分支：

| 表现 | 默认最小值 | 默认最大值 | 数值无关语义加成 |
| --- | ---: | ---: | --- |
| 伤害浮字缩放 | 1.00 | 1.34 | 暴击 ×1.18，击杀 ×1.12，最终仍钳制到 1.80 |
| 浮字上浮距离 | 34px | 56px | 无 |
| 目标受力位移 | 6px | 22px | 暴击 ×1.10，击杀 ×1.16，最终钳制到 28px |
| 冲击总时长 | 0.10s | 0.20s | 无 |
| 全屏震屏幅度 | 2px | 14px | 暴击 +2px，击杀 +3px，最终钳制到 18px |
| 全屏震屏时长 | 0.06s | 0.14s | 无 |
| 完整模式 Hit Stop | 0.012s | 0.055s | 暴击 +0.008s，击杀 +0.012s，最终钳制到 0.075s |

上述最小值、最大值、曲线参考值、最小强度、结果语义加成与最终上限均为 `@export` 参数；不得在 `CombatFeedbackDirector` 中硬编码。

## 3. 反馈数据流与通道

```text
DamageResolutionResult / Health.ValueChanged
               │
               ▼
CombatFeedbackDirector
  ├─ resolve_feedback_intensity(amount)
  ├─ build_popup_recipe(...)          → 浮字立即生成；无多段加速或段号延迟
  ├─ enqueue_target_impact(...)       → 每目标 FIFO，逐条完整播放
  └─ CombatScreenImpulse.enqueue(...) → 全局 FIFO，逐条震屏与 Hit Stop
```

### 3.1 每次结算的完整性

- 删除 `is_combo_middle`，删除基于 `HitIndex` / `HitCount` 的浮字缩放、时长与开始延迟。段号仅可用于为同一锚点的同时浮字分配确定性位置偏移，不能改变任何数值强度或播放配方。
- 范围目标与多段目标调用完全相同的 `build_popup_recipe`、`enqueue_target_impact` 与 `enqueue_impulse`；不再根据范围或段号排除震屏、受力和 Hit Stop。
- 对同一怪物/玩家的连续受击，`CombatFeedbackDirector` 维护按实体 ID 分组的局部受力队列。一个受力 Tween 结束后自动播放下一条，而不是 `kill()` 尚未播完的旧 Tween。
- 浮字仍可并发显示，且不设置数量上限。多段同锚点仅用环绕位置偏移避免数字完全重叠，所有条目使用相同的时长与数值曲线。

### 3.2 全局震屏与 Hit Stop

`CombatScreenImpulse` 改为请求队列：

1. 每次命中都将已计算的震屏和 Hit Stop 配方加入 FIFO；不再使用 `hit_stop_cooldown_msec`，也不因为新请求取消旧震屏。
2. 队首完成震屏与忽略时间缩放的 Hit Stop 恢复后，才消费下一条。这样同帧 5 段伤害会得到 5 次完整全局冲击，而不是只留下最后一次。
3. `Engine.time_scale` 仍由唯一节点持有与恢复；退出场景时清空队列、杀死当前 Tween，并精确还原根节点位置与原始时间缩放。
4. 减弱模式仍将同一配方的震屏幅度乘以 `reduced_screen_shake_ratio`，但将每条 Hit Stop 时长设为零；不会丢弃震屏请求或改变队列顺序。

该串行化仅解决一个根节点与全局时间缩放无法并行写入的问题；它不节流、不合并、不丢弃事件，且不会阻塞伤害结算或行动队列。

## 4. 职责边界

| 模块 | 修改职责 | 不得承担 |
| --- | --- | --- |
| `CombatFeedbackProfile` | 曲线计算与全部最小/最大/语义加成参数 | 读取实体、创建 Tween、改变结算 |
| `CombatFeedbackDirector` | 将结算事实变为浮字、局部受力与全局冲击请求；维护局部 FIFO | 伤害计算、目标合法性、回合等待 |
| `CombatScreenImpulse` | 按接收顺序完整播放全局冲击队列并可靠恢复世界状态 | 判断伤害高低、读取技能或实体 |
| `CombatFeedbackPopup` | 按传入配方显示浮字 | 推断段号、暴击或伤害值 |
| `DamageReceiverComponent` / `DamageEffect` | 继续只产生权威结果 | 引用表现配置或动画节点 |

## 5. 兼容性与风险控制

- `CombatFeedbackProfile` 的旧多段倍率、错开秒数、固定高额阈值、普通/重击受力、固定震屏和固定 Hit Stop 参数会被迁移为曲线参数。场景使用内嵌默认 Resource，字段没有覆写值时可安全使用新默认值。
- 局部队列比旧的 Tween 覆盖式实现更长，但只承载非阻塞表现；战斗逻辑不等待队列。若玩家偏好减弱模式，仍保留所有事件但关闭 Hit Stop。
- 队列必须在节点/目标失效时跳过条目，并在 `_exit_tree()` 清空，避免已死亡怪物或切场景后播放残留表现。
- 回滚只需恢复 Profile 的旧参数和 Director/Impulse 的覆盖式路径；C# 伤害结算契约与卡牌数值不参与本次变更。
