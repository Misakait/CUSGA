# 设计：属性加点界面与分配入口

## 组件边界

| 组件 | 职责 | 不负责 |
|---|---|---|
| `AttributeSummaryUI`（既有） | 「分配」按钮的显隐、打开弹窗 | 不参与加点累计与写入 |
| `AttributeAllocationPopup`（新增，独立子场景） | 累计、撤回、确认、取消，以及弹窗内的值显示 | 不改属性规则、不直接改字段 |
| `AttributeComponent`（既有） | 点数的权威状态与写入 | 不认识 UI |

## 为什么弹窗内先累计

属性点每级只发 3 点且不可再生，点错无法弥补。因此弹窗只维护一份「待分配」字典，点「确认」才真正写入；「取消」与关闭窗口都直接丢弃。

## 接口

```gdscript
# AttributeAllocationPopup（extends PopupPanel）
func Bind(attributes: Node) -> void          # 绑定属性组件；null 表示不绑定
func OpenFor(attributes: Node) -> void       # 绑定并重置累计后弹出
```

`AttributeSummaryUI` 只调用这两个方法，弹窗自身的按钮信号在弹窗内部连接。

## 数据流

- 点「+1」→ `_pending[类型] += 1` → `_refresh()`：更新该行值文本、预计值、按钮禁用态与顶部可用点数。
- 点「-1」→ `_pending[类型] -= 1` → `_refresh()`。
- 点「确认」→ 校验 `累计总量 <= AvailablePoints` → 逐项 `TryAllocatePoint(类型, 累计数)`；全部成功后关闭并清零，任一项失败则保持打开并刷新。
- 点「取消」/关闭窗口 → `_pending.clear()` → 隐藏。

## 关键决策

1. **预计值显示（对「只看属性名 + 当前值」的最小扩展）**：纯累计模式下，若点「+1」后界面毫无变化，玩家会认为功能失效。因此当某行有待分配点数时，值文本显示为 `当前值 → 预计值`，否则只显示当前值。预计值 = `GetEffectiveValue(类型) + 累计数 × GrowthPerPoint`，`GrowthPerPoint` 从 `GetAttribute(类型)` 读取；它仅用于显示，不参与写入。
2. **行由代码生成**：5 行结构完全一致，且每行都要持有值标签与两个按钮的引用；在场景里声明会产生 20+ 个节点与 20 次唯一名绑定，因此弹窗外壳在场景中声明、5 行在 `_ready` 里一次性生成，之后不再重建。
3. **属性名硬编码在 UI**：与摘要区的「物攻/物防/法强/法抗/速度」保持同一套措辞；不依赖组件 `DisplayName`（它依赖初始化时机，措辞也与摘要区不一致）。
4. **一次性写入**：`TryAllocatePoint` 自带 `amount` 参数，确认时按项传入累计总数即可，不需要逐点循环。
5. **显隐契约**：`AttributeSummaryUI._refresh()` 末尾调用 `_refresh_allocate_button()`，条件为 `_attributes != null and AvailablePoints > 0`。`AvailablePointsChanged` 已经连到 `_refresh()`，因此升级发点后按钮会自动出现，无需额外订阅。

## 风险与降级

| 风险 | 处理 |
|---|---|
| 属性组件缺失 | 按钮隐藏；弹窗不打开；不报错 |
| 组件缺 `TryAllocatePoint` / `GetEffectiveValue` | 能力探测（`has_method`）不通过时拒绝写入并保持弹窗打开 |
| 弹窗打开期间点数被外部改变 | 每次 `_refresh()` 按最新 `AvailablePoints` 重算累计上限；确认前重新校验 |
| 属性值被钳制（如比率型属性） | 预计值仅作展示；是否越界由组件决定，UI 不做二次钳制 |

## 测试

- 新增 `tests/godot/test_attribute_allocation_popup_contract.gd`（suite `attribute_allocation_popup_contract`）+ 顶层转发壳（`test_run` 只扫 `res://tests` 顶层）。
- 扩展 `tests/godot/test_attribute_summary_ui_contract.gd`：夹具补「分配」按钮与弹窗节点，新增按钮显隐与打开弹窗的用例。
