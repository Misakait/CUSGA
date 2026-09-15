# 卡牌拖拽虚影目标选择：实施计划

## Implementation Checklist

1. 在 `scripts/card_scripts/card_manager.gd` 的既有视觉配置区添加默认值为 `0.5` 的虚影透明度导出参数，以及真实卡引用之外的虚影节点状态；为新增变量和方法补充中文说明。
2. 增加虚影创建、位置更新、输入隔离与统一销毁的私有辅助方法。创建副本时保持完整卡面内容，禁用其物理和 GUI 命中，并让真实卡恢复普通手牌表现。
3. 调整 `_process`：拖拽期间仅移动虚影；所有释放区域、卡槽射线查询和目标视觉预览改用虚影位置。
4. 调整 `start_drag`、`finish_drag` 与 `_cancel_active_drag`：真实卡始终保留在手牌布局；有效释放前清除虚影并将真实卡传入既有出牌链路；无效释放与取消仅清理虚影和预览状态。
5. 扩展 `tests/godot/target_selection_visual_tests.gd`，覆盖虚影副本的 50% 透明度、既有拖拽缩放与输入隔离契约。
6. 更新 `docs/游戏机制与玩法内容.md` 的拖拽操作模式与目标选择视觉反馈，明确真实卡与虚影的生命周期和 50% 不透明度数值。
7. 依据项目要求，将学习反馈摘要和分点提交描述追加到根目录 `临时反馈文档.md`。

## Review Gates

- 确认虚影从不作为 `Action.presentation_card`，真实 `SkillCard` 是唯一进入 `DeckManager.play_card` 的节点。
- 确认任意退出路径都会使虚影隐藏并回收，且不会遗漏 `_apply_target_highlights([])`。
- 确认虚影的碰撞层/掩码、`input_pickable` 与 `Control.mouse_filter` 都不会阻断真实输入。
- 确认未修改点击模式及 `DeckManager`、`BattleManager`、`CardAnimations` 的既有接口。
- 确认机制文档记录了 50% 不透明度，并且没有引入新的战斗数值。

## Validation

- 静态检查改动后的 GDScript 类型、节点路径、方法调用和中文注释是否符合现有模式。
- 审阅 `tests/godot/target_selection_visual_tests.gd` 的新增断言是否直接覆盖虚影契约。
- 运行 `git diff --check`，检查空白、编码和补丁格式问题。
- 本机 `agent.local.md` 明确禁止运行 Godot Mono，因此不执行 Godot 运行时/场景检查；该限制将在最终交接中说明。

## Risk And Rollback

- 主要风险是复制后的 `Area2D` 或 `Control` 仍拦截输入；通过三层输入隔离和专门断言降低风险。
- 次要风险是取消路径残留虚影；通过单一清理方法和模式/回合出口复用降低风险。
- 回滚仅涉及 `CardManager` 的虚影状态与调用路径、对应测试和机制文档，无数据迁移或资源回滚。
