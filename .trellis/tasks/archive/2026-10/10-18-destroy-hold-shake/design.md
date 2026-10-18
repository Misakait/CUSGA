# 设计：长按破坏时的目标抖动反馈

## 0. 修正记录（第二轮）

第一轮实现抖的是卡内的 `Icon`（物品图标）。用户验收时指出：**要抖的是整张卡牌，不是卡里的物品**。
本轮据此修正，涉及三处设计变化：

| 项 | 第一轮（错） | 第二轮（现行） |
|---|---|---|
| 地形卡抖动目标 | `Visuals/PlayerView/Icon`（只有物品在抖） | `Visuals`（卡框 + 卡名 + 卡内图标一起抖） |
| 建筑抖动目标 | `Icon` | `Icon`（不变：建筑的可见内容就只有它，没有卡框这一层） |
| `ProgressAnchor` 位置 | `Visuals/PlayerView` 下，与图标同级 | `Item` 根节点下，**位于被抖子树之外** |
| `SyncAnchor` | `static`，同父节点手写坐标加法 | 实例方法，跨父节点全局换算 + 抵消运行中的抖动 |

下面各节已按现行方案改写；被否决备选中保留了第一轮方案及其否决理由，作为历史记录。

## 1. 边界与不变量

- 抖动是**纯表现**，只写**被抖节点自身**的本地 `position`：
  - 地形卡抖 `Visuals`（卡牌视觉根节点，其下是卡框 `PlayerView`、卡名 `Label`、卡内 `Icon`、`Amount`），
    于是整张卡牌一起抖；建筑抖 `Icon`。
  - 不写卡牌/建筑**根节点**的 `position` / `rotation` / `scale`。
  - 不写 `Collision`、`Interaction`、`Body`，因此命中区域、物理层与房间坐标完全不受影响。
  - 不新增 `AnimationPlayer` 轨道：`Item.tscn` 的动画库被既有测试约束为「轨道路径必须以 `Visuals:` 开头」，
    新增 `Icon:` 轨道会破坏该约束；且 `AnimationPlayer` 同一时刻只能播一个动画，无法与 `Idle`/`Hover` 并存。
- 抖动由 `Tween` 驱动，与 `Idle`/`Hover` 的 `Visuals:scale` / `Visuals:modulate` 轨道互不干扰。
  抖的是 `Visuals.position`，动画只写 `Visuals.scale` / `Visuals.modulate`，两者不冲突。
- 圆环锚点必须落在**被抖子树之外**，否则圆环会跟着抖（见 D2）。
- 圆环锚点的屏幕位置必须与改动前一致，不引入既有无长按交互的视觉回归。

## 2. 关键技术决策

### D1 抖动写在视图里，不写在共享长按 Controller 里

`WorldHoldInteractionController` 是长按的计时与圆环端口，它只知道 `hold_owner` 与 `progress_target`：

- 地形长按的 `hold_owner` 是卡牌，`progress_target` 是不参与抖动的锚点；
- 建筑拆除的 `hold_owner` 是 `BuildingController` 自己（不是建筑视图），`progress_target` 才是锚点。

若把抖动放进 Controller，就必须给 `begin_timed_hold` 增加「抖动目标」参数，
从而改动 `test_dev_settings_contract` 与 `test_world_interaction_coordinator_contract` 正在逐行断言的公开签名，
而且会把「地图方向 / 驻守」这条非破坏长按一并抖起来（与 R5 冲突）。

因此抖动归属视图：视图暴露幂等入口 `SetDestroying(bool)`，由**知道自己在破坏**的调用方驱动。
这与既有 `SetInteractionDisabled` / `SetHighlighted` / `SetFocused` 的视图 API 风格一致。
视图自己决定抖哪个节点（地形卡抖整卡、建筑抖图标），Controller 不需要知道这个差异。

### D2 圆环锚点改为独立锚点节点，且必须落在被抖子树之外

`world_hold_progress_indicator._resolve_hold_target_screen_position()` 对 `Sprite2D` 目标取
`sprite.get_screen_transform() * sprite.get_rect().end`。这两个量**都会随抖动变化**：

- 抖 `position` → `get_screen_transform()` 变；
- 抖 `offset` → `get_rect()` 把 `offset` 算进去，同样会变。

而且 `get_screen_transform()` 包含**整条祖先链**：抖 `Visuals` 时，其子树里的 `Icon` 的屏幕变换同样在变。
所以只要圆环还锚在被抖节点**或其子树内任何节点**上，就一定会跟着抖。第一轮把锚点放在
`Visuals/PlayerView` 下（与图标同级）在「只抖 `Icon`」时成立，一旦改为抖整张卡牌就失效了。

方案：在两张视图里各新增一个 `Marker2D` 节点 `ProgressAnchor`，位置**精确复刻图标的静止右下角**：

- 地形卡：挂在 `Item` 根节点下（`Visuals` 的兄弟，不在被抖子树内）；
- 建筑：挂在建筑根节点下（`Icon` 的兄弟）。

`Marker2D` 既不是 `Sprite2D` 也不是 `Control`，指示器会走
`_hold_progress_target.get_screen_transform().origin` 分支，取的正是锚点自身原点；
锚点不在被抖子树内，因此圆环**逐帧完全静止**，且屏幕位置与改动前逐像素一致
（因为复刻的是同一个点，而不是改用锚点所在父节点的原点）。

锚点与图标**处于不同父节点**，所以复刻不能写成手写坐标加法，必须走全局变换：

```
point  = icon.get_global_transform() * icon.get_rect().end   # 图标静止右下角，全局空间
anchor.position = anchor.get_parent().to_local(point)        # 落到锚点自己的父空间
```

锚点位置需要在图标纹理或缩放变化时重算：

- 地形卡：`item_view.RefreshView()` 设置 `_icon.texture` 之后；
- 建筑：`building_view.Configure()` 设置 `icon.texture` 与 `icon.scale` 之后。

两处都调用同一个 `DestroyShake.SyncAnchor()`，避免两份手写换算漂移。
因为取点按**静止状态**换算（见 D3），抖动期间调用也是安全的。

**被否决的备选：**

- *保持锚点 = 图标，接受圆环随抖*：直接违反 R3。
- *只抖卡内 `Icon`（第一轮方案）*：圆环确实能靠锚点保持静止，但玩家看到的是「只有卡里的物品在抖」，
  与「整张卡牌正在被破坏」的语义不符。已按反馈改为抖 `Visuals`。
- *锚点留在被抖子树内（`Visuals/PlayerView`）*：整卡一抖锚点就被带走，圆环跟着抖，违反 R3。
- *把锚点挂到父节点并用父节点原点当锚点*：地形卡圆环会从图标右下角跳到卡框右下角；
  建筑更糟——根节点原点是建筑中心，圆环会盖在建筑正中。属于额外视觉回归。
  （注意：这与现行方案不同——现行方案虽然把锚点挂在根节点下，但坐标是**复刻图标右下角**的，不是父节点原点。）
- *shader 顶点/UV 偏移抖动*：能让 `get_screen_transform()` 与 `get_rect()` 都不变，圆环天然稳定，
  但项目当前**没有任何独立 `.gdshader` 文件**（shader 全部是场景内联 sub_resource），
  且每个实例都需要独立 `ShaderMaterial`，为一次抖动引入新的资产类型与材质生命周期管理，收益不划算。

### D3 抖动组件：`scripts/anim/DestroyShake.gd`（`RefCounted`）

- 放置依据：`scripts/` 负责动画脚本，`scripts/anim/` 已有 `CardAnimations` / `CardAnimator` / `ScreenTransitions`。
- 形态：`RefCounted` 而不是 `Node` 组件。两个视图都已经持有被抖节点引用，
  不需要往场景里加组件节点；`RefCounted` 也让逻辑可以在 `test_run` 里脱离场景树直接构造验证。
- 接口：
  - `_init(target: Node2D, amplitude: float, step_seconds: float)`——`target` 是**被抖的整个可见节点**，
    地形卡传 `Visuals`、建筑传 `Icon`。
  - `Start() -> void`：记录静止位置，创建循环 `Tween`（`tween_callback` 换一个随机偏移 + `tween_interval` 等待）。幂等：已在抖动时直接返回。
  - `Stop() -> void`：杀掉 `Tween` 并把 `target.position` 精确复位到记录的静止位置。幂等：未抖动时也保证位置复位。
  - `IsRunning() -> bool`
  - `SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void`：**实例方法**（不是静态），按 D2 的全局换算写锚点位置。
    做成实例方法的原因有两条，都是第二轮改出来的：
    1. 它需要组件持有的**静止位置**来抵消运行中的抖动——若直接从正在抖动的变换取点，
       长按中刷新视图（`RefreshView()`）会把那一帧的偏移烘进锚点，圆环跟着抖一下。
       抵消方式是 `_target.position - 静止位置`，再经 `_target.get_parent().get_global_transform().basis_xform()`
       转到全局空间后从取点结果里扣掉。
    2. 锚点与图标现在处于不同父节点，需要 `anchor.get_parent().to_local()` 落到锚点父空间。
- `Tween` 用 `target.create_tween()` 创建，绑定到节点所在场景树，节点离开树时自动失效，不会泄漏。

### D4 用独立 `Tween` 抖动，不复用 `AnimationPlayer`

`Idle` / `Hover` 已在播放，且被既有测试约束为只驱动 `Visuals:` 轨道。
用独立 `Tween` 抖 `Visuals.position`（建筑是 `Icon.position`）可以和它们叠加，且不需要改动画库。

### D5 参数放在 `ItemMotionConfig`

新增两个字段（既有资产 `resources/interaction/item_motion_config.tres` 会被 `item_view.gd` 与
`loot_view.gd` 预加载；建筑视图新增 `MotionConfig` 导出并指向同一资产，让两条破坏长按手感统一）：

- `DestroyShakeAmplitude: float = 3.0` —— 被抖节点父节点空间的像素，随机偏移的半径。
- `DestroyShakeStepSeconds: float = 0.045` —— 每步间隔，越小抖得越快。

`item_view.gd` 复用既有 `MotionConfig`；`building_view.gd` 新增同名导出。
两者都带空值兜底，`MotionConfig` 缺失时使用组件内的默认常量，避免资源缺失导致抖动直接失效。

## 3. 数据流

```
玩家按下地形卡
  └─ world_interaction_coordinator._on_board_card_pressed()
       ├─ 距离校验 / 可采集校验（不通过直接 return，不抖动）
       ├─ _active_terrain_hold_card = card
       ├─ card.call("SetDestroying", true)        ← 整卡抖动开始（在 begin_hold 之前，覆盖零时长即时完成）
       └─ hold.begin_hold(...)  ── 进度 Tween ──► 圆环（锚定 ProgressAnchor，静止）
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
       ├─ 取 view.get_node_or_null("ProgressAnchor")，缺失时回退 Icon（旧自定义场景兼容）
       ├─ view.call("SetDestroying", true)
       └─ hold.begin_timed_hold(...)  ──► 圆环（锚定 ProgressAnchor，静止）
            └─ 完成 → _complete_demolition() → _cancel_demolition()
                 └─ view.call("SetDestroying", false)   ← 先取 view 再清 _demolition_id
```

## 4. 新增配置项

| 位置 | 名称 | 默认值 | 说明 |
|---|---|---|---|
| `resources/interaction/item_motion_config.gd` | `DestroyShakeAmplitude: float` | `3.0` | 抖动随机偏移半径（被抖节点父节点空间像素） |
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
| **整卡抖动后锚点仍留在被抖子树内，圆环跟着抖** | 锚点挂到被抖子树之外的根节点；测试断言 200 步抖动中锚点世界坐标**逐位**不变 |
| **抖动期间重算锚点（长按中刷新视图）把当前偏移烘进锚点** | `SyncAnchor` 按静止状态取点，先扣掉 `_target.position - 静止位置`；新增专门用例锁定 |
| 抖动被误当成「动画只能改 `Visuals`」不变量的破坏 | 只改 `Visuals.position`，不碰根节点/旋转/命中区域；`docs/游戏机制与玩法内容.md` 已同步说明 |
| 写运行时校验脚本时把 `Visuals/PlayerView` 当成 `Node2D` | 它是 `Button`（`Control`），`as Node2D` 会静默得到 `null`；按 `CanvasItem` 取 |

## 6. 回滚形状

- 新增文件（`scripts/anim/DestroyShake.gd`、新测试套件与其壳文件）可直接删除。
- 改动集中在 7 个文件：`item_view.gd`、`building_view.gd`、`Item.tscn`、`building_view.tscn`、
  `world_interaction_coordinator.gd`、`building_controller.gd`、`item_motion_config.gd`，均为**追加式**改动；
  `GetProgressAnchor()` 的返回值、建筑 `progress_target`、以及 `Item.tscn` 里锚点的挂载位置
  是仅有的三处结构性变更。回滚时把返回值改回 `_icon`、把建筑锚点改回 `view.get_node("Icon")`、
  把锚点移回 `Visuals/PlayerView` 即可恢复原状。
- `ItemMotionConfig` 新增字段带默认值，旧 `.tres` 缺少字段时行为等价于默认值。

## 7. 验证策略

- **契约测试**（新增 `tests/godot/test_destroy_hold_shake.gd` + 2 行壳 `tests/test_destroy_hold_shake.gd`）：
  源码形状断言 + 运行时行为断言（见 `implement.md` 验证证据）。
- **不能实例化生产场景做断言**：`item_view.gd` / `building_view.gd` 不是 `@tool`，在编辑器测试运行器里
  实例化后是 placeholder instance，实例方法不可调用；`building_view.tscn` 还被 `building_controller.gd`
  的 `preload` 缓存。因此套件用**等价层级的最小夹具**（根 → 被抖卡牌节点 → 卡框 → 图标，锚点挂根下）
  直接驱动生产组件。
- **端到端**：`project_run(mode="custom", scene="res://scenes/Main.tscn")`，用 `game_eval` 走真实
  `_on_board_card_pressed` / `_release`，采样被抖节点与锚点的**世界**坐标
  （世界坐标不含相机变换，可避开玩家移动导致相机跟随、屏幕坐标整体漂移的混淆）。
- **注意**：结算期间 `SettlementManager` 会 `tree.paused = true`，`Tween` 不推进；
  采样前先确认 `tree.paused == false`，否则会误判为「抖动没生效」。
