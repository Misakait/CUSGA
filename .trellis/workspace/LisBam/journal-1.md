# Journal - LisBam (Part 1)

> AI development session journal
> Started: 2026-06-04

---



## Session 1: Implement battle card operation modes

**Date**: 2026-09-14
**Task**: Implement battle card operation modes
**Branch**: `main`

### Summary

Added persisted click/drag battle card controls, generic local settings storage, UI confirmation flow, gameplay documentation, and state-management contracts.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `33d08cf` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Battle card selection and impact feedback

**Date**: 2026-09-14
**Task**: Battle card selection and impact feedback
**Branch**: `main`

### Summary

Implemented click-mode card lift and restored hand layout; sequenced explicit enemy card flight, hit feedback, and guarded discard completion.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `9d6c4cb` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: Battle selection cancellation and action recovery

**Date**: 2026-09-14
**Task**: Battle selection cancellation and action recovery
**Branch**: `main`

### Summary

Added click-mode re-click cancellation and moved target hit feedback before fatal effect resolution to prevent action queue deadlock.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `9f199c2` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: Battle hit animation queue deadlock

**Date**: 2026-09-14
**Task**: Battle hit animation queue deadlock
**Branch**: `main`

### Summary

Fixed the actual single-target card deadlock by avoiding a second await on the already-emitted flash Tween finished signal.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `f332382` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: Battle random target card impact animation

**Date**: 2026-09-14
**Task**: Battle random target card impact animation
**Branch**: `main`

### Summary

Resolved each RandomEnemy player card target once before presentation so card flight, hit feedback, and SkillExecutionContext damage use the same enemy.

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `3c07b7d` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: 目标选择视觉反馈

**Date**: 2026-09-14
**Task**: 目标选择视觉反馈
**Branch**: `main`

### Summary

实现点击与拖拽选目标的呼吸、悬停、主次选中、自动选中描边和不可选变暗反馈，并补充跨语言视觉接口、测试与机制规范。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `ca806c4` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 7: 目标选择与测试卡池优化

**Date**: 2026-09-14
**Task**: 目标选择与测试卡池优化
**Branch**: `main`

### Summary

加快可选目标呼吸反馈，修复怪物卡面展示层遮挡点击，调整主次目标描边，并补齐覆盖七种目标类型的初始化测试牌池与回归测试。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `4d35eaa` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 8: 优化卡牌拖拽虚影目标选择

**Date**: 2026-09-15
**Task**: 优化卡牌拖拽虚影目标选择
**Branch**: `main`

### Summary

将拖拽输入改为无交互虚影预览，真实手牌复用既有出牌飞行链路，并同步测试、玩法文档与前端状态契约。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `e5c574e` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 9: 增强战斗打击反馈

**Date**: 2026-09-15
**Task**: 增强战斗打击反馈
**Branch**: `main`

### Summary

实现统一伤害结算反馈、浮字与表现强度设置；完成护盾、治疗、敌方下冲、目标选择、手牌生命周期修复及文档测试同步。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `5cd061b` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 10: 战斗反馈数值曲线与全量命中

**Date**: 2026-09-15
**Task**: 战斗反馈数值曲线与全量命中
**Branch**: `main`

### Summary

将战斗反馈改为绝对数值饱和曲线，移除多段与范围节流并以目标/屏幕 FIFO 保留每次命中；补充静态回归、玩法文档与跨语言类型契约。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `fa95327` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 11: 局外长按交互确认

**Date**: 2026-09-16
**Task**: 局外长按交互确认
**Branch**: `main`

### Summary

新增局外交互长按确认、目标进度圆环与地图移动完成信号，并完成右下角锚点回归测试和玩法文档同步。

### Main Changes

- Detailed change bullets were not supplied; see the summary above.

### Git Commits

| Hash | Message |
|------|---------|
| `3087a33` | (see git log) |

### Testing

- Validation was not recorded for this session.

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 12: 开发者设置窗口（LISBAM 入口）
<!-- trellis-session: v=2 fp=84d20263842448d0 -->

**Date**: 2026-09-21
**Task**: 开发者设置窗口（LISBAM 入口）
**Branch**: `main`

### Summary

为游戏新增开发者设置浮层：游戏内依次按下 LISBAM 打开，首批提供「下一天」与「行动值消耗」两项功能。面板挂在 Main/UI/HUDLayer/HUDRoot（该层在局外与局内战斗中均存活），叠加显示且不暂停游戏。「下一天」复用 TimeSystem.PassTime 推进到下一个偶数阶段边界，保留昼夜、天数与天赋信号的既有顺序；「行动值消耗」用 SpinBox 夹紧非法输入并实时写入 TimeSystem.MapMoveTimeCost，按约定不持久化。新增 DevSequenceMatcher 纯逻辑状态机与 dev_settings_contract 契约套件（5 测试、35 断言），全量 40 套件 296 通过、0 失败、33 跳过；Main 与 battle 场景冒烟零脚本错误，game_eval 断言序列开面板、下一天 +1、行动值写入、未暂停。同步更新 frontend spec：新增「MCP test_run 的套件发现路径与转发壳」与「局内战斗的 UI 宿主」两节契约。

### Git Commits

| Hash | Message |
|------|---------|
| `4d881e1` | 新增开发者设置窗口（LISBAM 入口） |

### Status

[OK] **Completed**


## Session 13: 开局角色与背包初始化（子任务 1）
<!-- trellis-session: v=2 fp=a149f01e7fa35d60 -->

**Date**: 2026-09-23
**Task**: 开局角色与背包初始化（子任务 1）
**Branch**: `main`

### Summary

新增带入栏权威到 ItemsControl 与开局初始化节点 RunStartInitializer，实现带入即消耗；契约套件 9/9 通过，并在运行中的游戏里用 game_eval 验证背包内容、幂等、仓库视图镜像与写穿。

### Git Commits

| Hash | Message |
|------|---------|
| `001f89f` | feat: 新增开局角色与背包初始化 |

### Status

[OK] **Completed**


## Session 14: 开局技能卡抽取（抽 5 选 2）
<!-- trellis-session: v=2 fp=aeafa73803e803b9 -->

**Date**: 2026-09-23
**Task**: 开局技能卡抽取（抽 5 选 2）
**Branch**: `main`

### Summary

子任务②完成：每局开局初始化完成后触发技能卡抽取，抽出 5 张互不重复的候选、玩家选 2 张写入背包；抽卡界面挂在 HUD 下并复用战斗卡面与全局暂停开关。

### Main Changes

- 新增 core/gameflow/run_start_skill_card_draft.gd 与 scenes/ui_scenes/skill_card_draft_screen.tscn，抽 5 选 2 后把卡写入玩家背包（不自动进卡组）
- 用「订阅信号 + HasInitialized() 完成态补偿查询」解决抽卡界面晚于 RunStartInitializer 就绪、收不到同步广播的问题
- scripts/card_scripts/skill_card.gd 的 _ready() 加父节点存在性守卫，使战斗卡面可安全复用到非战斗界面
- Main.tscn 在 UI/HUDLayer/HUDRoot 下实例化抽卡界面；同步 docs/游戏机制与玩法内容.md 与 .trellis/spec/frontend 两条约束

### Git Commits

| Hash | Message |
|------|---------|
| `710a618` | feat: 新增开局技能卡抽取 |
| `66a30d2` | chore(task): archive 09-23-run-start-skill-card-draft |

### Testing

- [OK] 新增 tests/godot/test_run_start_skill_card_contract.gd（含顶层转发壳），11/11 通过
- [OK] 全量 test_run：371 passed / 2 failed（均为既有红灯）/ 33 skipped，相对基线 360 无新增回归
- [OK] project_run(custom res://scenes/Main.tscn) + game_eval：抽 5 张、卡面实例化并显示正确卡名、选 2 张入背包、未选不入包、界面收起、暂停正确归还
- [OK] 第二次开局验证新局状态独立（drawn=5、selected=0），且 user:// 下无存档文件、跨局不残留

### Status

[OK] **Completed**

### Next Steps

- 父任务 09-23-game-start-flow 的 5 条跨子任务集成验收（两项需求均已交付）
- 可选：在背包 UI 补充「抽到的卡需手动放进出战卡组」的引导


## Session 15: 每七天弹出天赋选择并交付十张测试天赋卡
<!-- trellis-session: v=2 fp=4fb0729dfca99ad1 -->

**Date**: 2026-09-24
**Task**: 每七天弹出天赋选择并交付十张测试天赋卡
**Branch**: `main`

### Summary

实装每七天弹出的天赋选择：可选池改为扫描 resources/talents 目录实时装配，新增 10 张属性天赋卡；界面补齐遮罩/标题/提示并对齐开局技能卡抽取。顺带修复属性天赋静默失效（组件路径写成玩家根下的 AttributeComponent，实际在 Components/ 下）、卡面描述被固定像素矩形截断、悬停详情浮窗被遮罩盖住三处缺陷。编辑器 MCP 实测：第 7/14 天自动弹出并暂停、点击后属性 100→105、暂停归还、池 10→9、已学卡不再出现；全量 424 项 389 通过 2 失败（均为既有问题）。

### Git Commits

| Hash | Message |
|------|---------|
| `aae82e6` | 每七天弹出天赋选择并交付十张测试天赋卡 |

### Status

[OK] **Completed**


## Session 16: 跨运行存档系统：局外仓库与玩家进度持久化
<!-- trellis-session: v=2 fp=cd504659e1c62b6a -->

**Date**: 2026-09-24
**Task**: 跨运行存档系统：局外仓库与玩家进度持久化
**Branch**: `main`

### Summary

新增 SaveManager 存档层（参与者协议 + 版本化 JSON + global/run 作用域分流 + 0.5s 防抖）与 4 个局外参与者（仓库物品/带入栏/金币/容量升级等级），29 个契约用例全绿；记录并修正两处实现期决策：损坏档保留 .corrupt 后从 .bak 恢复（而非把损坏内容写回 .bak），洗炼属性白名单仅在物品确实声明 AttributeBonuses 时求交集；把「进度走 SaveManager、偏好走 SettingsManager」的分层写入 spec。

### Git Commits

| Hash | Message |
|------|---------|
| `0e46bf4` | 新增存档系统 |
| `5cd8886` | 补充存档系统的 spec 契约与进度/偏好分层 |

### Status

[OK] **Completed**


## Session 17: 长按速度倍率与技能卡类别标签收尾
<!-- trellis-session: v=2 fp=9b774eec9653a5a9 -->

**Date**: 2026-09-26
**Task**: 长按速度倍率与技能卡类别标签收尾
**Branch**: `main`

### Summary

新增开发者菜单长按速度倍率：倍率 k 由 WorldInteractionTiming 持有，在 begin_timed_hold 统一施加，只压缩等待时长而不改任何行动值扣费；移除面板的行动值消耗调节入口并保留 TimeSystem.MapMoveTimeCost；契约测试同步至 18/18，并用 game_eval + Tween.custom_step 在真实进程内实证时长精确缩放；测试规范补记 game_eval 陷阱、SceneTree 脚本不可 test_run、全局静态状态复位纪律。归档本任务与上一个技能卡类别标签任务。

### Git Commits

| Hash | Message |
|------|---------|
| `70fdab2` | 1.新增技能卡类别标签； 2，更新技能卡贴图 |
| `7a3a34c` | feat：新增长按速度倍率，移除开发者菜单的行动值消耗调节入口 |

### Status

[OK] **Completed**


## Session 18: 昼夜动态屏幕滤镜
<!-- trellis-session: v=2 fp=72e3a42c8ad64ef1 -->

**Date**: 2026-09-27
**Task**: 昼夜动态屏幕滤镜
**Branch**: `main`

### Summary

新增全屏乘法混合滤镜，随 TimeSystem 昼夜状态与阶段进度连续改变天色并带平滑过渡；移除 UIMapWorldView 的旧背景自变暗逻辑；探索与战斗分别划分世界与 UI 层级；契约测试锁定颜色曲线、过渡收敛与 Node2D 父级尺寸自愈；沉淀全屏覆盖层父级约束到前端规范。

### Git Commits

| Hash | Message |
|------|---------|
| `b593b0d` | feat：新增昼夜动态屏幕滤镜 |

### Status

[OK] **Completed**


## Session 19: 交互距离不足提示圈与飘字世界坐标重构
<!-- trellis-session: v=2 fp=534a3f0fdb4388b1 -->

**Date**: 2026-10-17
**Task**: 交互距离不足提示圈与飘字世界坐标重构
**Branch**: `main`

### Summary

为「距离不够！」飘字新增一个附加组件：以交互目标为中心画出所需交互范围的空心半透明圈，与文字同批产出、同曲线淡出、一起自释放，覆盖棋盘卡与建筑两条入口。随后按用户意见整体重构定位方式：飘字承载层改为跟随相机变换，坐标成为世界坐标且只在生成时写一次，从而删除全部每帧重算逻辑。

### Main Changes

- 新增「所需交互范围」提示圈组件 InteractionRangeRing（空心 draw_arc、灰色半透明、自释放）
- 棋盘卡与建筑的距离不足提示同时显示范围圈，半径分别取 InteractionRange 与建筑数据的 InteractionRadius
- 飘字承载层启用 follow_viewport_enabled，圈与字的位置改为世界坐标且只在生成时写入一次
- 移除 FloatingTextAnchor 值对象、两个组件的 _process/_refresh、PROCESS_PRIORITY_LATE 与「世界到屏幕」缩放换算
- 契约测试新增「不得每帧重算」反向护栏，同步更新建筑系统与游戏机制文档及前端组件规范

### Git Commits

| Hash | Message |
|------|---------|
| `ecf5950` | feat：交互距离不足时显示所需交互范围提示圈 |

### Testing

- [OK] test_run(suite=floating_text_contract)：11/11 通过
- [OK] test_run(suite=world_interaction_coordinator_contract)：6 通过 / 3 失败 / 1 跳过，3 条失败为改动前既有，与本次无关
- [OK] Main 场景冒烟 status=live、游戏日志无报错；game_eval 实测相机平移 (120,80) 后圈的世界坐标一字未改、屏幕漂移 0.0px
- [OK] 运行期断言 ring.is_processing() 与 label.is_processing() 均为 false，证明组件已无每帧逻辑

### Status

[OK] **Completed**

### Next Steps

- 任务已归档；若要收敛工程内并存的 FloatingTextLabel 与 CombatFeedbackPopup 两个浮字节点，需另开任务


## Session 20: 掉落物多张卡牌化与随机落点
<!-- trellis-session: v=2 fp=d557f504099687b2 -->

**Date**: 2026-10-18
**Task**: 掉落物多张卡牌化与随机落点
**Branch**: `main`

### Summary

在 BoardController.SpawnLootCards 增加逐单位展开与最小间距随机落点：掉落 N 件生成 N 张各承载 1 件的卡，不再用右下角数字表示数量；不改 LootTableData.RollLoot 的产出形状，掉落表数值契约与装备逐件洗炼不变。新增 tests/godot/test_loot_multi_card_scatter.gd（9 用例 / 39 断言），并把「世界掉落卡恒为单件」不变量与 tree_paused 冻结 Tween、多编辑器会话需先锁定 CUSGA 等验证经验写入 .trellis/spec。运行期实证 3 件到 3 卡（记录最小间距 68.98/99.18）、1 件到 1 卡、恢复入口按记录位置重建不重新随机。发现既有损坏两处未修：campfire_recipe.tres 的 Inputs 只有 1 项导致 building_system_tests.gd:178 越界崩溃（篝火掉落断言零执行），test_item_room_content.gd 无法实例化。

### Git Commits

| Hash | Message |
|------|---------|
| `028dddc` | feat: 掉落物按实际数量生成多张卡牌并各自随机落点 |

### Status

[OK] **Completed**


## Session 21: 长按破坏抖动反馈
<!-- trellis-session: v=2 fp=6ed00249fa2063b5 -->

**Date**: 2026-10-18
**Task**: 长按破坏抖动反馈
**Branch**: `main`

### Summary

长按破坏（地形采集/破坏、建筑拆除）期间给目标贴图加循环 Tween 抖动，并向视图暴露幂等 SetDestroying(bool)。关键设计：进度圆环对 Sprite2D 取点用 get_screen_transform() * get_rect().end，position 与 offset 都会改变该乘积，因此「只抖贴图」无法让圆环静止——新增与图标同级、不参与抖动的 Marker2D ProgressAnchor，由 DestroyShake.SyncAnchor 复刻图标静止右下角，Marker2D 走指示器的 origin 分支，圆环屏幕位置与旧实现逐像素一致。抖动放在视图而非共享长按端口（其签名被契约测试逐字锁定），且必须在 begin_hold/begin_timed_hold 之前启动、在清空 _demolition_id/_active_terrain_hold_card 之前取出视图引用。新增 tests/godot/test_destroy_hold_shake.gd（6 用例 62 断言）全绿；全量 580 通过 / 12 失败，逐条核对均为既有失败。运行期 game_eval 证实：200 次抖动步进中锚点屏幕坐标精确不变而图标 200 次全动，1.2 秒内 28 个不同位置、最大偏移 2.99 ≤ 幅度 3，根节点/旋转/命中区域不动，建筑拆除走真实 _begin_demolition 启停正常，地图方向长按共用圆环但不触发抖动。顺带记录两条编辑器测试陷阱（非 @tool 视图是 placeholder instance；被 preload 的场景在同一进程内不可见）并已写入 spec。

### Git Commits

| Hash | Message |
|------|---------|
| `86f59e5` | feat: 长按破坏物品时目标抖动，进度圆环保持稳定 |

### Status

[OK] **Completed**


## Session 22: 破坏抖动改为整卡
<!-- trellis-session: v=2 fp=b1d2fd0c4222e8bb -->

**Date**: 2026-10-18
**Task**: 破坏抖动改为整卡
**Branch**: `main`

### Summary

修正上一轮的抖动目标：原先只抖卡内 Icon，实际要抖整张卡牌。地形卡改为抖 Visuals（卡框、卡名、卡内图标一起动），建筑仍抖 Icon（建筑的可见内容就只有它）。连带影响：ProgressAnchor 原本挂在 Visuals/PlayerView 下，位于被抖子树内，必须移到 Item 根节点才不会被带走，坐标由实测的卡框原点 (-50,-70) 反推为 (2,15)（无纹理 Sprite2D 的 get_rect() 是 Rect2(0,0,1,1) 而非居中矩形）。DestroyShake.SyncAnchor 因此从静态方法改为实例方法：它需要组件持有的静止位置，用 icon.get_global_transform() * get_rect().end 取点后经 anchor.get_parent().to_local() 落到锚点自己的父空间，并在抖动期间调用时先扣掉 _target.position - 静止位置（经父节点 basis_xform 转全局），避免长按中刷新视图把当前偏移烘进锚点。测试夹具同步改成跨父节点层级并新增 test_anchor_sync_during_shake_does_not_drift；7 用例 77 断言全绿。运行期实测：真实卡牌 200 步抖动中卡牌节点/卡框/卡内图标三者全动而锚点世界坐标逐位不变，屏幕位置与旧的锚定图标公式一致，max_shift 2.99≤3，停止精确复位；真实长按经 _on_board_card_pressed 启动、圆环锚定锚点且 40 帧内世界坐标逐位不变，释放后停止并隐藏圆环；建筑经真实 building_data 实例 + Configure 验证 max_shift 2.9976；地图方向长按共用圆环端口但完全不触发抖动。全量 580 通过 / 12 失败，与修正前同一失败集合（跳过数 39→40 系编辑器未打开场景导致 test_vital_component_contract 走 skip 分支）。另修正 spec 与文档中「只抖图标/与图标同级」的错误表述，并记录 Control 不能 as Node2D 的坑。

### Git Commits

| Hash | Message |
|------|---------|
| `8571b54` | fix: 破坏抖动改为抖整张卡牌，圆环锚点移出被抖子树 |

### Status

[OK] **Completed**


## Session 23: 归档件同步整卡抖动
<!-- trellis-session: v=2 fp=299acca129211921 -->

**Date**: 2026-10-18
**Task**: 归档件同步整卡抖动
**Branch**: `main`

### Summary

上一轮把 10-18-destroy-hold-shake 归档时，抖动方案还是错的「只抖卡内 Icon」，所以归档件里的 prd.md（R1、验收标准 1/3、层级说明）、design.md（D2 锚点挂载位置、D3 接口签名、D4、风险表、回滚形状、验证策略）、implement.md（阶段 1/2 的节点路径与构造参数、验证证据表、运行期证据、全量回归数字、回滚点）与 task.json 的 description 全都在描述已作废的方案。本轮把这四处同步到现行方案，并在每份文件顶部加「修正记录（第二轮）」明确记下改了什么、为什么改——保留第一轮方案及其否决理由作为历史，不假装一直是对的。要点：抖动目标是整个可见节点（地形卡 Visuals、建筑 Icon）；ProgressAnchor 必须落在被抖子树之外（地形卡移到 Item 根节点）；SyncAnchor 因此从静态方法改为实例方法，跨父节点用全局变换换算，并在抖动期间按静止状态取点以免把当前偏移烘进锚点。验证证据补入第二轮实测值：真实卡牌 200 步中卡牌/卡框/卡内图标三者全动而锚点世界坐标逐位不变、max_shift 2.4179、真实长按 40 帧锚点逐位不变、建筑 max_shift 2.9976、地图方向长按完全不抖；测试表更新为 7 用例 77 断言并列出新增的 test_anchor_sync_during_shake_does_not_drift。全量回归数字更新为 580/12/40/632，并写明跳过数 39→40 是 test_vital_component_contract 因编辑器未打开场景走 skip 分支的环境差异，不是回归。

### Git Commits

| Hash | Message |
|------|---------|
| `073a84b` | docs(task): 归档件同步到整卡抖动方案 |

### Status

[OK] **Completed**


## Session 24: 长按期间在范围内移动不再打断交互（地形 + 建筑）
<!-- trellis-session: v=2 fp=b12680603facfd44 -->

**Date**: 2026-10-18
**Task**: 长按期间在范围内移动不再打断交互（地形 + 建筑）
**Branch**: `main`

### Summary

长按的取消条件从「玩家在动」改为「离开交互范围」；建筑侧用鼠标屏幕坐标区分玩家操作与相机漂移，遮挡只在完成瞬间拦。

### Main Changes

- 地形：_process_terrain_hold_input 不再读方向键，只比玩家与卡牌的世界距离；越界按拥有者 cancel_hold_for 并给出「距离不够！」+ 范围提示圈。
- 建筑：去掉逐帧重新命中鼠标指向，改用鼠标屏幕坐标是否变化判定（_mouse_screen_position 经 get_canvas_transform 往返，基准每帧前移）；逐帧门禁只判距离，遮挡留给 _can_complete_demolition。
- 两条长按的完成入口都再复查一次距离，挡住「越界那一帧恰好填满」的结算。
- 新增 tests/godot/test_hold_move_within_range.gd（4 用例 36 断言）；building_system_tests.gd 补范围内移动不取消的断言；同步两份 docs 与 backend spec 的「交互与时间」。

### Git Commits

| Hash | Message |
|------|---------|
| `d7fb56a` | feat(interaction): 长按期间在范围内移动不再打断交互 |

### Testing

- [OK] test_run(suite=hold_move_within_range)：4 passed / 0 failed / 36 assertions。
- [OK] 全量 test_run：585 passed / 12 failed / 39 skipped / 636 total / 76 suites；基线 581/12/39/632/75，失败集合逐条一致，零新增失败。
- [OK] Main 场景 game_eval 实证：建筑漂移免疫、越界取消+反馈、遮挡只在完成拦；地形范围内存活、越界取消+反馈、完成入口正负对照。

### Status

[OK] **Completed**

### Next Steps

- 既有的 building_system_tests.gd:181 越界错误（campfire_recipe 的 Inputs 只剩 1 项）会让整个建筑回归场景一项断言都不执行，需单独修。
- 本地领先 origin/main，尚未 push。
