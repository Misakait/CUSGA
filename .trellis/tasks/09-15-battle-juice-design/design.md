# Battle 打击感与果汁感技术设计

## 1. 体验目标

本方案不调整伤害公式、目标规则、状态规则、卡牌消耗或回合顺序。它只把已经发生的结算结果，以强烈但可读的卡牌动作语言传达给玩家。

首版体验基调：

- 每一次有效命中都要有明确的“接触瞬间”：卡牌切入、命中帧、目标受力与数值弹出对齐。
- 暴击、击杀、护盾、闪避等结果必须先于“伤害是多少”被识别。
- 多段与范围攻击要持续有连击感；每段数字都必须出现，屏幕冲击与受力不随段数或目标数简单叠加。
- 玩家与怪物使用同一个结果语义和调度器；只根据目标的表现锚点选择怪物卡面或玩家 HUD/角色区域。
- 视觉以切牌、残影、冲击框、爆字、高对比配色为主。五行只作为可选的细小色相/纹理变化。

## 2. 现状与问题定位

当前完整链路为：

```text
玩家手牌 → DeckManager.play_card → Action → BattleManager._execute_single_action
  → 单体怪物：飞卡、预先抖动+闪白
  → SkillExecutionContext → CombatSkillData / DamageEffect
  → DamageReceiverComponent.ReceiveDamage → HealthComponent.TakeDamage
  → Health.ValueChanged / DamageTaken → 血条与死亡逻辑
```

现有可复用能力：

- `CardAnimations.gd` 已有飞行、缩放、抖动、闪白、弃牌和死亡原子动画。
- `Monster` 已能独立缩放卡面、文本、属性和状态栏，并保留血条原始大小。
- `DamageEffect` 逐段调用 `DamageReceiverComponent.ReceiveDamage()`；每一段都有独立的闪避、暴击、状态、护盾和实际扣血语义。
- `StatusComponent.StatusChanged` 已可驱动状态栏刷新。

现有缺口与其后果：

| 缺口 | 直接后果 | 设计处理 |
| --- | --- | --- |
| 受击动画发生在实际结算之前 | 命中、闪避、护盾、暴击和致死无法匹配各自表现 | 只在伤害结算产生结果后派发表现事件 |
| `ReceiveDamage` 仅打印日志且不返回结果 | 表现层无法知道实际伤害、暴击、闪避、护盾与致死 | 新增只读的伤害结算结果契约和信号 |
| 范围、扩散、敌方攻击没有统一反馈入口 | 只有玩家单体卡看起来“打到了” | 所有伤害都由结果事件进入同一导演层 |
| 多段伤害在一个同步循环中瞬间完成 | 逐段数字会完全重叠 | 导演层按段号缩短浮字时长并错开显示；不延迟权威结算 |
| 怪物生命为零后立即从列表移除并 `QueueFree()` | 击杀缺少收尾，且新怪可能立刻补位 | 逻辑死亡即时生效，视觉死亡延迟收尾并独立释放节点 |
| 场景没有镜头和浮字层 | 无法承载高冲击反馈 | 新增独立表现层节点，不侵入伤害公式与卡牌数据 |

## 3. 边界与职责

```text
DamageEffect / DamageReceiver / StatusComponent       CombatFeedbackDirector
（权威玩法结算）              ──只读结果事件──▶       （表现调度）
  伤害、暴击、闪避、护盾、生命                         配方、队列、浮字、特效、震屏
         ▲                                                       │
         │                                                       ▼
   不读取表现配置、不 await 动画                             Anchor / PopupPool / FxPool
```

### 3.1 结算层：只产生事实

新增 `[GlobalClass] DamageResolutionResult : RefCounted`，由 `DamageReceiverComponent` 在每一次 `ReceiveDamage` 结束时创建并发射 `DamageResolved(result)`。调用方可忽略返回值，因此现有 `DamageEffect` 与 GDScript 调用路径保持兼容。

结果应至少包含：

- `Source`、`Target`、`DamageType`、`Element`。
- `RequestedDamage`、`PreGuardDamage`、`ActualDamage`；所有数值均为已结算值。
- `IsEvaded`、`IsCritical`、`IsLethal`、`WasCapped`。
- `ShieldAbsorbedDamage`、`ShieldWasBroken`；不把 Boss 单次上限、减伤等误标为护盾。
- `HitIndex`、`HitCount`、`TargetRole`，用于表现节流和范围主/次目标区别，不参与数值计算。

为保证护盾识别准确，`DamagePayload` 可承载一次性、仅供结算记录使用的 `DamageResolutionTrace`。`ShieldStatusInstance` 向 trace 写入吸收量与破裂状态，`BossDamageCapStatusInstance` 写入封顶量；两者都不引用 UI 或表现代码。`DamageReceiverComponent` 从 trace 组装不可变结果。

`HealthComponent.DamageTaken` 与 `ValueChanged` 保留，继续服务现有血条与兼容消费者；新增结果信号不替换它们。闪避同样必须发射结果，即使实际生命变化为零。

`DamageEffect` 在创建 `DamagePayload` 时填入段号、总段数和主/次目标元数据。元数据仅描述这次已经发生的伤害，不允许表现层反向修改伤害。

### 3.2 表现层：唯一的战斗反馈导演

在 `scenes/battle_scenes/battle.tscn` 根节点下新增以下组合：

```text
CombatFeedbackDirector (Node)
├── CombatFeedbackLayer (CanvasLayer)
│   ├── PopupPool
│   ├── ImpactFxPool
│   └── ScreenFlashOverlay
├── CombatScreenImpulse (Node)
└── CombatFeedbackSettings (Node 或 Autoload 适配器)
```

`CombatFeedbackDirector.gd` 是唯一订阅 `DamageResolved` 与生命 `ValueChanged` 的表现调度者：

1. 战斗初始化时连接玩家和当前怪物的 `DamageReceiverComponent`；监听 `MonsterManager.monsters_spawned` 连接后续新怪。
2. 收到结果后先解析目标屏幕锚点；所有浮字立即保留，多段结果按段号使用更快的上浮与错开延迟。
3. 根据 `CombatFeedbackProfile` 和当前表现强度取得反馈配方，驱动浮字、目标反应、冲击框/粒子、屏幕脉冲与 Hit Stop。
4. 不回写 `HealthComponent`、`StatusComponent`、行动队列或卡牌节点；表现错误必须安全降级为跳过单项，不中断回合。

场景中的 `CombatFeedbackAnchor` 用导出路径把战斗实体映射到可显示的位置：怪物使用卡面中心，玩家使用 `UI` 内新增的 `PlayerFeedbackAnchor`。该映射让玩家实体仍可保持纯 `Node`，而不会把 HUD 路径硬编码进伤害结算。

### 3.3 行动表现与真正命中分离

- 保留玩家卡牌“脱离手牌 → 切入/残影 → 飞向目标”的施放表现，但将 `BattleManager` 当前的 `play_enemy_hit_feedback` 从卡牌飞行后移除。
- 实际命中仅由 `DamageResolved` 触发，所以范围、扩散、随机、多段、敌方技能及未来伤害来源都天然覆盖。
- 现有 `ATTACK` 临时分支绕开 `DamageReceiverComponent`，后续实现必须改为生成标准 `DamagePayload` 或淘汰该占位路径；否则玩家受击无法拥有一致反馈。
- 卡牌行动仍只在效果完成后弃牌。表现导演不增加权威结算等待，也不改变 `Action` 队列顺序。

### 3.4 死亡的逻辑/视觉双阶段

当前 `Monster.HandleDeath()` 和 `MonsterManager.on_monster_died()` 会使目标过早销毁或补位。首版应拆为：

1. **逻辑死亡**：生命归零后立即从 `active_monsters` 移除，禁止后续目标选择，并维持胜负、掉落、补位和回合规则的权威语义。
2. **视觉死亡**：原怪物节点保留约 0.20–0.35 秒，由导演播放击杀冲击、卡面裂解/缩退和淡出；完成后只由一个收尾入口 `QueueFree()`。

死亡节点要被标记为“不可交互、不可再次受击”，并不会重新加入候选池。补位怪物可照常出现，死亡节点保持其旧位置渐隐，避免阻塞流程。若导演不存在或已禁用，必须立即走现有安全销毁路径。

玩家逻辑死亡保持现有战斗结束判定；只追加 HUD/角色区域的致命冲击和全屏暗闪，不销毁玩家节点。

## 4. 反馈配方与优先级

### 4.1 结果优先级

同一目标、同一帧或同一连击窗口只播放最高价值的独占反馈；低优先级信息以浮字或轻量提示保留。

| 优先级 | 结果 | 必须反馈 | 可独占项 |
| ---: | --- | --- | --- |
| 100 | 击杀 | 带下划线的终结数字、死亡收尾 | 最大冲击、最长 Hit Stop |
| 90 | 暴击且有效伤害 | 加粗、加大的深红伤害数、重击框 | 中等 Hit Stop、短震屏 |
| 80 | 护盾破裂/完全格挡 | 灰色吸收数字与一次短震屏 | 一次短震屏 |
| 70 | 闪避 | 白色 `MISS`、残影闪移 | 不显示 0 伤害数字 |
| 60 | 普通有效命中 | 伤害数、目标受力、命中火花 | 轻量受力 |
| 50 | 减伤、封顶、吸收一部分 | 小型灰色吸收数字 | 不抢占正常伤害数 |
| 40 | 护盾获得、治疗 | 治疗绿色数字 | 不震屏、不停顿 |

### 4.2 默认视觉配方

| 结果 | 浮字/UI | 目标与画面 |
| --- | --- | --- |
| 普通命中 | 暖色伤害数，上浮 38–52px、0.32–0.42s | 目标 6–10px 受力位移 + 1.04→0.97→1.00 squash；小型斜向冲击框 |
| 暴击 | 1.35–1.55 倍、加粗的深红数字 | 10–16px 受力、放大冲击框、0.04–0.06s Hit Stop |
| 闪避 | 白色 `MISS`，不显示伤害 | 12–18px 横向残影闪移，立刻回位 |
| 护盾吸收 | 灰色吸收数字，不显示额外文字 | 六边形/硬边冲击框；完整吸收不播放受伤闪红 |
| 治疗 | 绿色 `+N`；玩家从生命 UI 右侧显示 | 不影响生命条读数以外的布局 |
| 范围命中 | 主目标完整浮字，次目标 0.025–0.045s 错开 | 一次共享冲击波，次目标只做轻受力 |
| 多段命中 | 每段独立数字；中间段紧凑数字 | 每段时长缩短并按段号错开；首段入场、末段收束 |
| 护盾获得 | icon 1.15→1.00 弹入 | 不影响生命条读数 |
| 击杀 | 带下划线的最大伤害数、掉落式碎片 | 0.20–0.35s 裂解/缩退/淡出，12–18px 脉冲 |

颜色依结果语义固定：普通伤害暖色、暴击深红、护盾灰色、闪避白色、状态紫色、治疗绿色。元素只允许在冲击框的辅助笔触上加入轻微差异。

### 4.3 多段与范围的视觉预算

- 每段均立即进入独立浮字流程；多段浮字使用普通时长的 **55%**，并按段号以 **45ms** 错开。
- 不设置每个目标或全战场的浮字并发上限；每个已结算结果都会创建或取得独立浮字，播放结束后回收到对象池。
- 每张范围技能最多触发 1 次屏幕脉冲和 1 次 Hit Stop。次目标只允许轻量受力和错峰浮字。
- 每 100ms 最多 3 个普通冲击特效；高优先级事件可借位，但先回收最低优先级池对象。
- 同一目标正处于死亡收尾时，不再排入普通受击反馈；追加命中只汇总至终结数字，避免复活般的抖动。

### 4.4 Hit Stop 与屏幕脉冲

`CombatScreenImpulse` 管理根 `Battle` 节点的短震屏、暗角/闪白叠加和 `Engine.TimeScale`。不得让每个 Tween 或技能各自写时间缩放。

- 只允许暴击、击杀、高伤害阈值与护盾破裂申请 Hit Stop。
- 完整强度下：暴击 35–50ms、护盾破裂 35–45ms、击杀 55–70ms；时间缩放建议为 0.02–0.08。
- 减弱强度下：默认关闭 Hit Stop，震屏位移和闪白不透明度降至完整模式的 35–50%。
- 控制器采用最高优先级覆盖、最短冷却 120ms、忽略时间缩放的恢复计时器，保证不会叠加后永久慢放。
- 震屏只移动战斗根节点或专门的表现容器；恢复时精确回写初始位置，避免与怪物排布/卡牌 Tween 争夺属性。

## 5. 参数化与设置

新增 `CombatFeedbackProfile.tres`（或等价 Resource），把所有时长、幅度、多段错开参数、颜色与阈值放入 Inspector。禁止将上述表中的数值散落进 `BattleManager`、`DamageEffect` 或状态类。

`BattleSettingsPanel` 扩展为第二项下拉选项：

- `full`（默认）：完整的冲击、粒子、闪白、震屏与 Hit Stop。
- `reduced`：保留伤害数字、结果标签和轻量目标受力；减少特效、禁用 Hit Stop。

设置与现有 `battle/operation_mode` 同样持久化到 `user://settings.cfg`，建议键为 `battle/feedback_intensity`。设置改变立即影响新事件，不重置正在播出的表现。

## 6. 兼容性、风险与回滚

| 风险 | 约束/处理 | 回滚方式 |
| --- | --- | --- |
| 表现改变结算时序 | 导演只消费只读结果；权威伤害同步完成 | 关闭导演或 profile 的 `enabled`，恢复原有同步结算 |
| 多段同步结算导致数字重叠 | 缩短浮字时长并按段号错开 | 调整 profile 的多段时长倍率与错开间隔 |
| 死亡延迟与补位冲突 | 逻辑死亡先移出候选池，视觉节点不可交互 | 导演缺失时立即 `QueueFree()` |
| Hit Stop 让游戏卡死或慢放残留 | 由唯一控制器持有恢复 token，使用忽略缩放的计时器 | profile 禁用 Hit Stop；控制器在 `_ExitTree` 还原时间缩放 |
| 低性能设备卡顿 | 对象池、较短的多段浮字时长、`reduced` 预设 | 默认/运行时切换为 reduced |

## 7. 验收映射

- AC1：第 2 节的当前链路与文件锚点。
- AC2：第 4 节的结果矩阵覆盖命中、暴击、多段、范围、护盾、状态、闪避与击杀。
- AC3：第 4.3、4.4、5 节给出预算、默认参数、完整/减弱策略。
- AC4：本设计与 `implement.md` 构成后续实施蓝图。
- AC5：当前文档只用于评审；用户确认前不创建运行时代码或资源改动。
