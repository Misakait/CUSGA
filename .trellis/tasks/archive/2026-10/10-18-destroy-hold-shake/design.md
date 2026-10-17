# 设计：长按破坏时的目标抖动反馈

## 1. 边界与不变量

- 抖动是**纯表现**，只写贴图节点 `Icon` 的本地 `position`：
  - 不写卡牌/建筑根节点的 `position` / `rotation` / `scale`。
  - 不写 `Collision`、`Interaction`、`Body`，因此命中区域、物理层与房间坐标完全不受影响。
  - 不新增 `AnimationPlayer` 轨道：`Item.tscn` 的动画库被既有测试约束为「轨道路径必须以 `Visuals:` 开头」，
    新增 `Icon:` 轨道会破坏该约束；且 `AnimationPlayer` 同一时刻只能播一个动画，无法与 `Idle`/`Hover` 并存。
- 抖动由 `Tween` 驱动，与 `Idle`/`Hover` 的 `Visuals:scale` / `Visuals:modulate` 轨道互不干扰。
- 圆环锚点必须落在**不参与抖动**的节点上，否则圆环会跟着抖（见 D2）。
- 圆环锚点的屏幕位置必须与改动前一致，不引入既有无长按交互的视觉回归。

## 2. 关键技术决策

### D1 抖动写在视图里，不写在共享长按 Controller 里

`WorldHoldInteractionController` 是长按的计时与圆环端口，它只知道 `hold_owner` 与 `progress_target`：

- 地形长按的 `hold_owner` 是卡牌，`progress_target` 是图标；
- 建筑拆除的 `hold_owner` 是 `BuildingController` 自己（不是建筑视图），`progress_target` 才是图标。

若把抖动放进 Controller，就必须给 `begin_timed_hold` 增加「抖动目标」参数，
从而改动 `test_dev_settings_contract` 与 `test_world_interaction_coordinator_contract` 正在逐行断言的公开签名，
而且会把「地图方向 / 驻守」这条非破坏长按一并抖起来（与 R5 冲突）。

因此抖动归属视图：视图暴露幂等入口 `SetDestroying(bool)`，由**知道自己在破坏**的调用方驱动。
这与既有 `SetInteractionDisabled` / `SetHighlighted` / `SetFocused` 的视图 API 风格一致。

### D2 圆环锚点改为独立静态锚点节点，而不是图标本身

`world_hold_progress_indicator._resolve_hold_target_screen_position()` 对 `Sprite2D` 目标取
`sprite.get_screen_transform() * sprite.get_rect().end`。这两个量**都会随抖动变化**：

- 抖 `Icon.position` → `get_screen_transform()` 变；
- 抖 `Icon.offset` → `get_rect()` 把 `offset` 算进去，同样会变。

所以「抖贴图 + 圆环稳定」无法靠只抖图标实现，必须让圆环锚点脱离被抖动的子树。

方案：在两张视图里各新增一个 `Marker2D` 节点 `ProgressAnchor`，位置**精确复刻图标的静止右下角**：

```
anchor.position = icon.position + icon.scale * icon.get_rect().end
```

`Marker2D` 既不是 `Sprite2D` 也不是 `Control`，指示器会走
`_hold_progress_target.get_screen_transform().origin` 分支，取的正是锚点自身原点；
锚点不在被抖动的节点上，也不随 `Icon.position` 变化，因此圆环**逐帧完全静止**，
且屏幕位置与改动前逐像素一致（因为复刻的是同一个点）。

锚点位置需要在图标纹理或缩放变化时重算：

- 地形卡：`item_view.RefreshView()` 设置 `_icon.texture` 之后；
- 建筑：`building_view.Configure()` 设置 `icon.texture` 与 `icon.scale` 之后。

两处都用同一个公式，公式放进抖动组件的静态方法，避免两份手写换算漂移。

**被否决的备选：**

- *保持锚点=图标，接受圆环随抖*：直接违反 R3。
- *锚点改挂父节点（`PlayerView` / 建筑根节点）*：地形卡圆环会从图标右下角跳到卡框右下角；
  建筑更糟——根节点原点是建筑中心，圆环会盖在建筑正中。属于额外视觉回归。
- *shader 顶点/UV 偏移抖动*：能让 `get_screen_transform()` 与 `get_rect()` 都不变，圆环天然稳定，
  但项目当前**没有任何独立 `.gdshader` 文件**（shader 全部是场景内联 sub_resource），
  且每个实例都需要独立 `ShaderMaterial`，为一次抖动引入新的资产类型与材质生命周期管理，收益不划算。

### D3 抖动组件：`scripts/anim/DestroyShake.gd`（`RefCounted`）

- 放置依据：`scripts/` 负责动画脚本，`scripts/anim/` 已有 `CardAnimations` / `CardAnimator` / `ScreenTransitions`。
- 形态：`RefCounted` 而不是 `Node` 组件。两个视图都已经持有 `Icon` 引用，
  不需要往场景里加组件节点；`RefCounted` 也让逻辑可以在 `test_run` 里脱离场景树直接构造验证。
- 接口：
  - `_init(sprite: Sprite2D, amplitude: float, step_seconds: float)`
  - `Start() -> void`：记录静止位置，创建循环 `Tween`（`tween_callback` 换一个随机偏移 + `tween_interval` 等待）。幂等：已在抖动时直接返回。
  - `Stop() -> void`：杀掉 `Tween` 并把 `sprite.position` 精确复位到记录的静止位置。幂等：未抖动时也保证位置复位。
  - `IsRunning() -> bool`
  - `static SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void`：按 D2 的公式写锚点位置。
- `Tween` 用 `sprite.create_tween()` 创建，绑定到节点所在场景树，节点离开树时自动失效，不会泄漏。

### D4 抖动只抖贴图，不复用 `AnimationPlayer`

`Idle` / `Hover` 已在播放，且被既有测试约束为只驱动 `Visuals:` 轨道。
用独立 `Tween` 抖 `Icon.position` 可以和它们叠加，且不需要改动画库。

### D5 参数放在 `ItemMotionConfig`

新增两个字段（既有资产 `resources/interaction/item_motion_config.tres` 会被 `item_view.gd` 与
`loot_view.gd` 预加载；建筑视图新增 `MotionConfig` 导出并指向同一资产，让两条破坏长按手感统一）：

- `DestroyShakeAmplitude: float = 3.0` —— 本地像素，随机偏移的半径。
- `DestroyShakeStepSeconds: float = 0.045` —— 每步间隔，越小抖得越快。

`item_view.gd` 复用既有 `MotionConfig`；`building_view.gd` 新增同名导出。
两者都带空值兜底，`MotionConfig` 缺失时使用组件内的默认常量，避免资源缺失导致抖动直接失效。

## 3. 数据流

```
玩家按下地形卡
  └─ world_interaction_coordinator._on_board_card_pressed()
       ├─ 距离校验 / 可采集校验（不通过直接 return，不抖动）
       ├─ _active_terrain_hold_card = card
       ├─ card.call("SetDestroying", true)        ← 抖动开始（在 begin_hold 之前，覆盖零时长即时完成）
       └─ hold.begin_hold(...)  ── 进度 Tween ──► 圆环
            └─ 完成 → _complete_terrain_hold()
                 └─ _clear_active_terrain_hold()
                      └─ card.call("SetDestroying", false)   ← 抖动停止 + 复位

释放 / 取消 / 移动打断 / 场景退出
  └─ _clear_active_terrain_hold() / _cancel_active_hold()
       └─ card.call("SetDestroying", false)

长按建筑
  └─ building_controller._begin_demolition()
       ├─ _cancel_demolition()（清掉上一个）
       ├─ _demolition_id = id
       ├─ view.call("SetDestroying", true)
       └─ hold.begin_timed_hold(...)
            └─ 完成 → _complete_demolition() → _cancel_demolition()
                 └─ view.call("SetDestroying", false)   ← 先取 view 再清 _demolition_id
```

## 4. 新增配置项

| 位置 | 名称 | 默认值 | 说明 |
|---|---|---|---|
| `resources/interaction/item_motion_config.gd` | `DestroyShakeAmplitude: float` | `3.0` | 抖动随机偏移半径（目标本地像素） |
| `resources/interaction/item_motion_config.gd` | `DestroyShakeStepSeconds: float` | `0.045` | 抖动步进间隔（真实秒） |
| `building_view.gd` | `MotionConfig: Resource` | `item_motion_config.tres` | 建筑复用同一动作参数资产 |

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| 零时长长按即时完成，抖动启动后无人停止 | 抖动在 `begin_hold` **之前**启动，且完成回调必定经过 `_clear_active_terrain_hold()` / `_cancel_demolition()` |
| `_clear_active_terrain_hold()` 在 `_active_terrain_hold_card == null` 时提前返回，漏停抖动 | 只有设置了 `_active_terrain_hold_card` 的分支才启动抖动，两者严格同生命周期 |
| `_cancel_demolition()` 先把 `_demolition_id` 置 `-1`，之后取不到视图 | 在重置 `_demolition_id` **之前**先取 `_views[id]` 并停抖 |
| 视图在抖动中被释放（房间重建、卡牌移除）留下偏移 | `Tween` 绑定节点场景树；两个视图的 `_exit_tree()` 调用 `Stop()` |
| 锚点复刻公式与图标实际渲染位置漂移 | 公式抽成 `DestroyShake.SyncAnchor()` 单一实现；测试断言锚点屏幕位置与图标静止右下角一致 |
| 改锚点造成圆环位置回归 | 锚点复刻的是**同一个点**（图标静止右下角），测试断言改动前后误差 < 1 像素 |
| 抖动被误当成「动画只能改 `Visuals`」不变量的破坏 | 只改 `Icon.position`，不碰根节点/旋转/命中区域；`docs/游戏机制与玩法内容.md` 的表述在 3.3 阶段补充说明 |

## 6. 回滚形状

- 新增文件（`scripts/anim/DestroyShake.gd`、新测试套件与其壳文件）可直接删除。
- 改动集中在 6 个文件：`item_view.gd`、`building_view.gd`、`Item.tscn`、`building_view.tscn`、
  `world_interaction_coordinator.gd`、`building_controller.gd`，均为**追加式**改动；
  `GetProgressAnchor()` 的返回值和建筑 `progress_target` 是仅有的两处语义变更，
  回滚时把返回值改回 `_icon`、把建筑锚点改回 `view.get_node("Icon")` 即可恢复原状。
- `ItemMotionConfig` 新增字段带默认值，旧 `.tres` 缺少字段时行为等价于默认值。

## 7. 验证策略

- **契约测试**（新增 `tests/godot/test_destroy_hold_shake.gd` + 2 行壳 `tests/test_destroy_hold_shake.gd`）：
  源码形状断言 + 运行时行为断言（见 `implement.md` 验证证据）。
- **运行时行为断言**：直接实例化 `Item.tscn`，调 `SetDestroying(true)`，
  跨帧采样 `Icon.position` 与锚点 `get_screen_transform().origin`，再 `SetDestroying(false)` 断言精确复位。
- **端到端**：`project_run(mode="main")` + `game_manage(op="input_mouse")` 真实按下并保持，
  用 `game_eval` 采样同一张卡的图标位移与锚点位移。
- **注意**：结算期间 `SettlementManager` 会 `tree.paused = true`，`Tween` 不推进；
  采样前先确认 `tree.paused == false`，否则会误判为「抖动没生效」。
