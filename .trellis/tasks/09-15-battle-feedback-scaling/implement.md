# 战斗反馈数值曲线与多段一致性实施计划

## 实施顺序

1. 重构 `CombatFeedbackProfile`：删除多段时长倍率、段间延迟、固定高额阈值、固定普通/重击幅度和固定 Hit Stop 时长；新增绝对数值饱和曲线、各表现最小/最大值、暴击/击杀语义加成和最终安全上限的导出参数。实现纯函数 `resolve_feedback_intensity(amount)`，返回钳制后的 `0..1` 强度。
2. 重构 `CombatFeedbackDirector` 的配方生成：删除 `is_combo_middle` 和按 `HitIndex` / `HitCount` 修改时长、延迟、缩放的逻辑。伤害、护盾和治疗都用统一曲线生成自身浮字；伤害的目标反应与全局冲击由总碰撞量生成，闪避保持固定轻量反馈。
3. 将目标受力从“同目标新 Tween 杀死旧 Tween”改为按目标 ID 的 FIFO。每次请求都使用独立的数值配方；目标释放或离开场景时清除其队列。
4. 将 `CombatScreenImpulse` 从覆盖式 Tween / 恢复令牌改为 FIFO 冲击请求队列。每项请求完整执行震屏与 Hit Stop 后再继续下一项；减弱模式请求保留震屏并将 Hit Stop 设为零。
5. 从 Director 移除 `hit_stop_cooldown_msec`、高额阈值和优先级门槛。保留结果优先级仅服务于暴击、击杀、护盾破裂的配方加成和结果颜色，不能再用于跳过某一段或某一范围目标的反馈。
6. 为同锚点多段浮字添加仅改变位置的确定性布局偏移；验证它不修改缩放、时长、延迟、受力、震屏或 Hit Stop。
7. 新增 `tests/godot/combat_feedback_scaling_tests.gd`：验证曲线低/中/高伤害单调增强且高值不越界；相同数值的首段/中段/末段配方一致且无开始延迟；暴击/击杀语义加成仍受最大值钳制；减弱模式使用同一曲线但没有 Hit Stop；连续冲击请求不会被覆盖或丢失。
8. 更新 `docs/游戏机制与玩法内容.md`、`.trellis/spec/frontend/state-management.md`、必要的类型安全规格和 `临时反馈文档.md`，记录公式、默认参数、队列行为、无节流约束与验证结果。

## 验证计划

- 运行 `git diff --check`，确认脚本、场景与文档无空白错误。
- 静态检索确认仓库不再引用 `multi_hit_popup_duration_multiplier`、`multi_hit_popup_stagger_seconds`、`hit_stop_cooldown_msec` 或 `high_damage_hit_stop_threshold`，且 `HitIndex` / `HitCount` 不再改变多段表现配方。
- 在当前本机约束下，不使用 Godot Mono；通过新增 GDScript 测试脚本、显式类型审查、静态调用链和场景参数核对验证 Godot 改动。
- 若运行环境具备 Godot 运行时，补跑 `tests/godot/combat_feedback_scaling_tests.gd`，观察同帧多段与范围命中每条均产生完整的局部与全局反馈；不将该运行环境前提写入权威结算代码。

## 风险文件与回滚点

| 文件 | 风险 | 回滚控制 |
| --- | --- | --- |
| `scripts/battle_scripts/combat_feedback_profile.gd` | 参数迁移错误使 Inspector 值失效 | 所有新字段给出默认值；场景内嵌 Resource 未覆写旧字段 |
| `scripts/battle_scripts/combat_feedback_director.gd` | 多段事件被队列遗漏或已释放目标仍播放 | 按实体 ID 清理队列，事件仍不阻塞结算 |
| `scripts/battle_scripts/combat_screen_impulse.gd` | 多个 Hit Stop 导致时间缩放无法恢复 | 单一 FIFO 持有 `Engine.time_scale`，退出时总是清空并恢复 |
| `tests/godot/combat_feedback_scaling_tests.gd` | 只断言视觉常数，无法捕捉节流回归 | 断言配方一致性、队列完整性、曲线单调性与上限钳制 |

## 实施前复核

- [x] Profile 曲线只使用绝对已显示数值，不读取目标最大生命。
- [x] 多段与范围没有依据段号、范围、冷却或 Tween 覆盖丢弃事件。
- [x] 所有表现上限都由 Profile 导出参数控制。
- [x] 全局队列与局部队列都不被行动队列等待。
- [x] 用户已审阅并批准本设计与实施计划。
