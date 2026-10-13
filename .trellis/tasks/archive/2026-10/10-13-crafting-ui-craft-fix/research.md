# 已确认的排查依据

- 新场景 `scenes/crafting/CraftingUI.tscn` 的数量节点实际路径是 `DetailSection/OutPutCount/SpinBox`，按钮路径是 `DetailSection/OutPutCount/Craft/CraftButton`（按钮已有场景唯一名）。
- `core/ui/crafting/crafting_ui_controller.gd` 第 49、50 行仍使用不存在的 `DetailSection/Quantity` 和 `DetailSection/CraftButton`。`get_node_or_null` 返回 null，按钮连接被跳过，所以没有调用制作组件。
- 实际 SpinBox 未配置 min_value/value，默认均为 0；即便只修按钮，仍可能提交无效数量或访问 null。
- 当前场景不存在 StatusLabel，控制器已有 null 容错。本任务不用扩展美术布局。
- 制作组件和服务本身提供 TryCraftWithReason、MaxCraftableQuantity；规则层无需改动。
- 主代理负责文档、任务记录与编辑器运行验证。实现代理负责控制器、必要场景绑定配置、测试。检查代理只在这些范围自修。
- 进入任务时 Git HEAD 为 d43f6c1；已有未追踪 agent.local.md，为用户规则文件，不修改或提交。上一轮发现的类型缓存报错当前已不在编辑器错误列表中，不能拿旧日志作为这次合成问题原因。

## 验证计划

测试真实 CraftingUI 场景与真实 InventoryComponent/CraftingComponent，通过按钮 pressed 信号走整个链路；覆盖默认单次、多次、材料耗尽及空配方状态。编辑器 filesystem scan 后运行新套件，使用 project_run 运行 CraftingUI 与 Main，game_eval 检查绑定与扣料产出，截图检查，结束只停止游戏。
