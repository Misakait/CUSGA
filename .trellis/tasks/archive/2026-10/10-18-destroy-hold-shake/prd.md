# 长按破坏时的目标抖动反馈

> **修正记录（第二轮）**：R1 最初写的是「抖动只作用于**贴图节点**」——地形卡抖卡内的 `Icon`。
> 用户验收时澄清：要抖的是**整张卡牌**（卡框、卡名、卡内物品一起抖），只有卡里的物品在抖
> 会让人以为破坏的是那个物品而不是这张卡。R1 与验收标准 1、3 已据此改写为「抖整个可见节点」。
> 建筑没有这一层差异（它的可见内容就只有 `Icon`），目标节点不变。
> 连带影响：`ProgressAnchor` 从 `Visuals/PlayerView` 下移到 `Item` 根节点，因为原位置**在被抖子树内**。

## 目标

玩家长按破坏地形卡或拆除建筑时，给目标的**整个可见节点**加持续抖动，直观表示「这个东西正在被破坏」；
地形卡抖的就是整张卡牌（卡框 + 卡名 + 卡内物品），建筑抖的是它的图标；
同时右下角的长按进度圆环必须**保持稳定不抖**。

## 已确认背景

- 局外长按只有一个计时端口：`core/gameflow/world_hold_interaction_controller.gd`
  （`begin_hold` 按行动值换算、`begin_timed_hold` 按真实秒数，倍率只在 `begin_timed_hold` 施加一次）。
- 两条**破坏类**长按入口：
  - 地形卡：`world_interaction_coordinator._on_board_card_pressed()` → `begin_hold(...)`，
    结束统一走 `_clear_active_terrain_hold()`（释放、取消、完成、移动打断都汇到它）。
  - 建筑拆除：`building_controller._begin_demolition()` → `begin_timed_hold(...)`，
    结束统一走 `_cancel_demolition()`。
- 第三条长按入口 `BeginWorldHoldForMap()`（地图方向 / 通道驻守）**不是破坏**，不在本任务范围。
- 目标视图：
  - 地形卡 `res://scenes/ItemTerrian/Item.tscn`，脚本 `scripts/item_scripts/item_view.gd`。
    层级：`Item` → `Visuals`(Sprite2D，空贴图，承载闪白 shader) → `PlayerView`(Button，100×140 卡框)
    → `Icon`(Sprite2D，`position=(50,83)`、`scale=(2,2)`) / `Label` / `Amount`；
    `ProgressAnchor`(Marker2D) 挂在 `Item` 根节点下（第二轮从 `Visuals/PlayerView` 下移出来）。
  - 建筑 `res://scenes/building/building_view.tscn`，脚本 `core/building/building_view.gd`。
    层级：`Building`(Node2D) → `Icon`(Sprite2D，缩放由 `Configure()` 按占地算出) / `ProgressAnchor`(Marker2D) / `Body`(StaticBody2D)。
- 进度圆环 `core/ui/hud/world_hold_progress_indicator.gd` **每帧**重算锚点：
  目标为 `Sprite2D` 时用 `sprite.get_screen_transform() * sprite.get_rect().end`。
  改动前两条破坏长按传入的 `progress_target` 都是 `Icon`；本任务改为传入不参与抖动的 `ProgressAnchor`。
- 既有不变量（`docs/游戏机制与玩法内容.md` 第 542 行）：地形卡动画只改 `Visuals` 的缩放与颜色，
  **不改变房间坐标、根节点位置、旋转或命中区域**。

## 需求

- **R1 抖动作用于整个可见节点**：地形卡抖 `Visuals`（于是卡框、卡名、卡内 `Icon` 一起抖），建筑抖 `Icon`。
  不移动卡牌/建筑根节点，不改变房间坐标、碰撞层、`Collision` 形状、`Interaction` 命中区域、旋转。
- **R2 抖动与长按同生命周期**：长按真正开始（已通过距离与可采集/可拆除校验）时启动；
  释放、取消、完成、移动打断、目标失效、场景退出时立即停止并把被抖节点复位到静止位置。
  启动与停止都必须**幂等**，且零时长长按（即时完成）不能留下永久抖动。
- **R3 圆环锚点稳定且位置不变**：抖动期间圆环的屏幕位置与抖动前完全一致，不随抖动位移。
  因此锚点必须落在**被抖子树之外**——`Visuals` 一抖，其子树内所有节点的屏幕变换都会变。
- **R4 参数可配置**：抖动幅度与步进频率放进既有动作参数资产，便于手感调整。
- **R5 覆盖范围**：地形卡破坏 + 建筑拆除；地图方向 / 通道驻守长按保持原样（不抖）。

## 验收标准

1. 地形卡长按期间 `Visuals.position` 相对静止位置持续变化，且 `Visuals`、卡框 `PlayerView`、卡内 `Icon`
   三者的屏幕位置**都在变**（证明抖的是整张卡牌而不是只有卡里的物品）；释放后回到静止位置，且差值精确为 `Vector2.ZERO`。
2. 建筑拆除长按期间 `Icon.position` 同样抖动，取消/完成后复位。
3. 抖动期间圆环锚点的 `get_screen_transform().origin` 逐帧不变（用精确相等判定，非容差）；
   同时 `Icon.get_screen_transform().origin` 确实在变（证明抖动真的发生了）。
4. 圆环锚点的屏幕位置与改动前一致（误差在 1 屏幕像素内）。
5. 长按被释放 / 移动打断 / 目标被移除 / 场景退出时，抖动停止且被抖节点无残留偏移。
6. 地图方向与通道驻守长按期间不产生任何抖动。
7. 抖动不影响命中：长按期间 `Interaction` 的命中区域与根节点位置不变。
8. `test_run` 全量回归中本任务新增套件通过，且未引入新的失败。

## 范围

### 本轮包含

- 新增可复用的抖动表现组件（`RefCounted`，`Start()` / `Stop()` / `IsRunning()`）。
- `item_view.gd`、`building_view.gd` 新增幂等公开入口 `SetDestroying(destroying: bool)`。
- `Item.tscn`、`building_view.tscn` 各新增一个不参与抖动的进度锚点节点；
  地形卡的锚点必须挂在**被抖子树之外**（`Item` 根节点下），因为被抖的正是 `Visuals` 整棵子树。
- 两个破坏入口的开始/结束调用点接线。
- `ItemMotionConfig` 新增抖动参数。
- 新增契约测试套件 + 运行时验证。

### 本轮不包含

- 不改 `WorldHoldInteractionController` 的公开签名（`begin_hold` / `begin_timed_hold` 的 4 个参数保持不变）。
- 不改地图方向 / 通道驻守长按的任何表现。
- 不加抖动音效、粒子、屏幕震动、伤害数字。
- 不改圆环的半径、颜色、线宽与绘制逻辑。
- 不修既有失败套件（见下）。

## 既有阻塞（改动前即存在，不在本任务范围）

- `tests/godot/building_system_tests.tscn` 在 `building_system_tests.gd:178` 越界崩溃
  （`resources/recipe/res/campfire_recipe.tres` 的 `Inputs` 只有 1 项，测试期望 2 项）。
- `tests/godot/test_item_room_content.gd` 无法实例化（`Parse error, base=none`）。
- `board_controller_contract::test_shared_log_and_error_texts` 期望的文案在 HEAD 与工作区都不存在。
- `reusable_gathering` 2 项、`world_interaction_coordinator_contract` 3 项、`gameflow_chain_contract` 1 项既有失败。

## 待确认 / 实现默认

- 抖动幅度与频率的具体手感值：先给保守默认（幅度 3 本地像素、步进 0.045 秒），
  运行时验证后按观感微调，并写进 `ItemMotionConfig` 供后续调整。
- 抖动位移按「目标本地像素」定义：建筑占地越大，同样的幅度在世界空间里抖得越明显，符合直觉。
