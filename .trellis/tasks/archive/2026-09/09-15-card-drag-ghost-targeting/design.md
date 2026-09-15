# 卡牌拖拽虚影目标选择：技术设计

## Architecture

本功能只修改 `CardManager` 的拖拽展示状态，不改变 `PlayerHand`、`DeckManager`、`BattleManager` 或 `CardAnimations` 的职责。

- `card_being_dragged` 继续持有真实 `SkillCard`，作为目标类型解析、能量校验与最终 `DeckManager.play_card` 调用的唯一数据源。
- 新增 `card_drag_ghost` 仅为 `SkillCard` 的临时展示副本。它由 `CardManager` 创建、更新位置和销毁，绝不进入手牌数组或行动队列。
- 既有 `Action.presentation_card` 继续接收真实手牌。因此 `BattleManager` 已有的“真实卡从手牌位置飞向敌人”的展示链路无需重写。

## Lifecycle And Data Flow

1. 鼠标按下可用手牌后，`CardManager` 保留真实卡引用并从它复制虚影。
2. 创建阶段将虚影定位到真实卡当前位置、设为 50% 不透明度、应用现有 `card_drag_scale`，并禁用其 `Area2D` 碰撞/输入与子 `Control` 鼠标接收。
3. 每帧只移动虚影；目标卡槽查询、手牌区释放判断和目标高亮均使用虚影当前位置，卡牌数据仍读取真实卡。
4. 鼠标松开时先隐藏并回收虚影，再按现有规则判断目标：
   - 有效敌人：扣能量并以真实手牌调用 `DeckManager.play_card`。
   - 自身目标卡在手牌区外空白处：保留已有扣能量与自身施放。
   - 其他位置：不出牌；真实卡从未离开手牌数组和布局。
5. 切换操作模式、输入锁定或失去玩家回合时，复用统一清理出口回收虚影并重置目标视觉；不调用出牌、弃牌或能量消耗。

## Input Isolation

完整复制 `SkillCard` 会连带复制 `Area2D` 和 `Label` 等可命中节点。创建虚影后必须：

- 将虚影 `Area2D` 的碰撞层和掩码设为零，并关闭 `input_pickable`；
- 将虚影及其后代 `Control` 设为 `MOUSE_FILTER_IGNORE`；
- 不将虚影加入 `PlayerHand.player_hand_card`，也不连接它作为可交互手牌使用。

这能保证物理点查询仍命中真实手牌与怪物卡槽，GUI 也不会因虚影遮挡而阻断后续交互。

## Presentation Configuration

将虚影透明度作为 `CardManager` 顶部的 Inspector 配置项，默认 `0.5`，并在中文注释中说明它对应已确认的 50% 不透明度需求。缩放继续复用现有 `card_drag_scale`，不引入新的时长、缓动或 `CardAnimations` 方法。

真实手牌在开始拖拽时恢复为普通手牌表现；这样虚影是拖拽过程唯一的缩放对象，且真实手牌不会留下悬停缩放状态。

## Compatibility And Rollback

- 点击模式完全不读取虚影状态。
- 自动、随机、范围和扩散目标仍由已有目标类型分支和行动队列处理；虚影只改变鼠标位置的展示与目标查询。
- 所有取消出口均调用同一个虚影清理方法，避免改变模式或回合时残留节点。
- 若需回退，可仅移除 `CardManager` 的虚影创建、移动和清理路径，恢复真实卡移动；不涉及资源、场景、存档或跨语言迁移。

## Test Strategy

- 扩展 `tests/godot/target_selection_visual_tests.gd`：实例化真实卡与 `CardManager`，断言创建出的虚影是独立节点、内容副本保持、透明度为 `0.5`、缩放为 `card_drag_scale`，并断言虚影 `Area2D` 与控件不会接收输入。
- 保留既有目标类型和卡面目标反馈断言，防止虚影改动回归自动/手动目标语义。
- 本机覆盖规则禁止运行 Godot Mono；实施后进行静态审查、差异检查与测试脚本的源码核对，并将未执行的运行时验证明确交接。
