# Design: Battle hit animation queue deadlock

## Confirmed cause

`CardAnimations.hit(node, sprite)` 同时创建 `t1 = shake_x(node)`（默认总时长 0.28 秒）和 `t2 = flash_white(sprite)`（默认总时长 0.14 秒）。旧实现先 `await t1.finished`，再 `await t2.finished`。因此 `t2` 通常已在等待 `t1` 时完成；Godot 的 `finished` 信号不会缓存给稍后注册的 `await`，第二次等待永久挂起。`BattleManager._handle_execute_actions` 正在等待该协程，控制锁便无法释放。

这与怪物是否死亡无关；目标血量充足时同样稳定复现。

## Chosen repair

保留两条独立 Tween，避免更改既有抖动和闪白的时长、缓动或视觉效果：

1. 创建抖动 Tween 与闪白 Tween。
2. 立即等待抖动 Tween 的完成信号，因此不会错过其信号。
3. 在等待结束后，仅当闪白 Tween 仍有效且正在运行时才等待其完成；若它已完成或被中止，直接返回，不再等待不会重发的信号。

抖动是当前较长的表现，但实现不依赖这个时长关系：若未来闪白变长，仍在运行时会被等待；若保持较短，已完成时安全跳过。

## Scope and safeguards

- 仅调整 `scripts/anim/CardAnimations.gd` 的 `hit` 等待逻辑与说明。
- 在 `docs/游戏机制与玩法内容.md` 和前端状态管理规范中补充并行动画等待契约。
- 不修改 `BattleManager` 的既有“飞行 → 受击 → 效果 → 弃牌”顺序，也不触碰用户未提交的资源或场景文件。
- 当前游戏保持运行；源代码修复在下一次脚本重载或游戏重启后生效。
