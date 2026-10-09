# 统一背包格子为 item_slot1

## Goal

OpenBackpack 所有运行时格子使用 item_slot1 原有点击和松开样式，各栏独立单选并保持现有功能。

## Requirements

- 物品、角色装备、出战卡组三栏生成的格子均实例化 scenes/ui/item_slot1.tscn。
- 使用 item_slot1 已有的松开和点击贴图，不重新绘制或染暗底图。
- 同一栏独立单选，点击另一个格子取消旧选中，再次点击当前格子取消；不同栏允许各自选中一个。
- 未选中格子的悬停和瞬时按下不能造成同栏同时有两个点击外观。
- 保留名称、数量、装备占位、节点复用、拖拽、Shift/Alt 快捷操作、建筑菜单、固定和悬停提示以及关闭清除选择功能。
- 背包使用最小兼容适配，不改变原 item_slot1 场景和仓库、商店、合成行为。
- 同步游戏机制文档和相关组件契约；不自动提交或推送。

## Acceptance Criteria

- [x] 三栏所有格子的 scene_file_path 均为 res://scenes/ui/item_slot1.tscn，刷新复用节点。
- [x] 真实按下/松开验证单栏切换、取消、跨栏独立，悬停和按住也无重复点击外观。
- [x] 数量、名称、拖拽、快捷转移和提示照常，关闭全部清除。
- [x] Godot 4.7.1 编辑器 MCP 扫描、相关测试、OpenBackpack 和主场景冒烟无本次引入错误。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
