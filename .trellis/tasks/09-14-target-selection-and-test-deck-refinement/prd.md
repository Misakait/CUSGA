# 目标选择与测试卡池优化

## Goal

加快可选目标呼吸缩放，修复敌人属性层遮挡点击，调整主次目标绿色描边，并扩充初始化测试卡池以覆盖全部目标类型。

## Requirements

- 可手动指定目标的卡牌，其可选敌人必须以更快节奏循环缩放，持续提示这些怪物卡可被选择。
- 点击模式中，鼠标指向 `MonsterAttribute`、名称、元素等怪物卡面展示控件时，仍必须能够选中对应敌人的卡槽；设置、确认、取消、结束回合等非怪物 UI 仍必须阻挡世界输入。
- 绿色主选中边框必须变薄；次级目标继续有绿色边框，但使用更淡的绿色。
- 战斗场景的初始化测试卡池必须覆盖 `Self`、`SingleEnemy`、`AllEnemies`、`AnySingleUnit`、`AllUnits`、`RandomEnemy`、`SpreadFromEnemy` 七种目标类型，并使每种类型至少有三张测试牌可抽取。
- 不得改变已有目标解析、随机结算、伤害、能量消耗或行动队列语义。

## Acceptance Criteria

- [x] `target_selection_pulse_half_duration` 为 `0.25` 秒，完整呼吸周期为 `0.50` 秒，且仅用于可选目标状态。
- [x] 点击怪物属性、名称、元素和状态展示区域时，会选择其所属怪物；点击非怪物 GUI 时不会误选怪物。
- [x] 主选中/自动选中描边宽度为 `2px`；次级选中描边为 `Color(0.55, 1.00, 0.65, 0.80)`，主选中仍为 `Color(0.25, 1.00, 0.35, 1.00)`。
- [x] 初始测试牌组包含 `test_card_1` 至 `test_card_7`，每张各三份，共 21 张；新增目标类型覆盖测试可验证枚举值 `0` 至 `6`。
- [x] C# 解决方案构建与差异格式检查通过；由于本地环境限制，不运行 Godot Mono。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
