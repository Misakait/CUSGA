# Implementation plan: Battle selection cancellation and action recovery

## Ordered checklist

1. [x] 在 `CardManager` 中复用现有清理和高亮方法，实现重复点击已选卡牌取消整次选择、重复点击已选敌人取消该目标。
2. [x] 为 `DeckManager` 的敌人展示入口补充删除队列保护，避免将 Tween 绑定到已标记删除的目标。
3. [x] 将 `BattleManager` 的显式敌人受击反馈移动到 `ApplyEffect` 之前，保留飞行、效果结算和唯一弃牌收尾。
4. [x] 更新《游戏机制与玩法内容》和前端状态管理 code-spec，记录取消选择规则及“表现先于致死释放”的队列契约。
5. [x] 静态检查选择状态出口、受击调用位置、`QueueFree` 根因、主动出牌收尾和旧行动构造点；本地覆盖规则禁止运行 Godot Mono、编译与自动化测试。
6. [ ] 使用 Trellis 质量检查流程，追加学习反馈与编号提交描述，提交本任务范围内文件，归档任务并记录会话。

## Risk controls

| Risk | Control |
| --- | --- |
| 重复点击取消时误弃牌或扣能量 | 只调用确认前已存在的 `clear_click_selection()`，不触碰 `consume_energy` 或 `DeckManager.play_card`。 |
| 取消敌人后误丢失卡牌选择 | 只把 `_selected_click_target` 置空，继续刷新同一张已选卡牌的目标预览与操作栏。 |
| 怪物死亡后 await 永久等待 | 在 `ApplyEffect` 前完成受击 Tween，并拒绝对已进入删除队列的节点创建 Tween。 |
| 改变非单体卡牌行为 | 仅在既有 `has_enemy_card_presentation` 分支重排受击调用。 |
| 误提交用户的资源与场景改动 | 只暂存本任务涉及的 GDScript、文档、spec 和 Trellis 任务文件。 |
