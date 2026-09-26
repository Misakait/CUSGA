# 技术设计：开发者菜单长按速度倍率

对应 `prd.md`（R1–R6）。本文只记录技术决策与契约，需求事实不在此重复。

## 1. 架构与边界

### 1.1 倍率的落点

倍率必须同时满足三条约束：①覆盖两条长按入口（行动值类 `begin_hold`、秒数类 `begin_timed_hold`）；②不改变任何行动值扣费；③面板与运行期都能访问，且不引入新的 Autoload 或场景路径依赖。

由此得到唯一合理落点：**`WorldInteractionTiming` 持有倍率，`WorldHoldInteractionController.begin_timed_hold()` 施加倍率。**

| 候选落点 | 结论 | 原因 |
|---|---|---|
| `begin_timed_hold`（控制器） | **采用** | 它是唯一的计时执行点（`_hold_tween.tween_method(..., duration_seconds)`），在此施加一次即覆盖两条入口；`begin_hold` 只是把基础秒数转发给它，因此天然不会二次缩放 |
| `WorldInteractionTiming.get_hold_duration_seconds()` | 不采用 | 只覆盖行动值类长按，建筑拆除仍按原速；且会让「纯换算规则」这个职责掺入可被开发者篡改的全局状态，破坏 `world_hold_interaction_tests.gd` 锁定的纯函数契约 |
| `WorldInteractionCoordinator` | 不采用 | 秒数类长按（拆除）不经过它，会漏掉 |
| 各交互资源内部 | 不采用 | 要改多处；拆除不经过任何交互资源 |

### 1.2 倍率的持有者

`core/constants/world_interaction_timing.gd` 新增三个成员：

```gdscript
## 长按速度倍率：>1 更快（等待时长按比例缩短），1 为原始速度。
static var _hold_speed_multiplier: float = 1.0

static func set_hold_speed_multiplier(value: float) -> void   # 夹紧到下界后写入
static func get_hold_speed_multiplier() -> float
static func scale_hold_seconds(base_seconds: float) -> float  # base / 倍率，base<=0 时返回 0
```

**为什么用 `static var` 而不是 Autoload 或导出字段：**

- 面板解析节点依赖要付出真实代价：`_bind_time_system()`、`_enter_tree()` 重新绑定、`_is_initialized` 那套「缓存场景挂回时恢复」的逻辑，都是为节点型依赖写的。倍率放进节点会让面板再多一套同样的复杂度。
- 项目已有先例：`core/ui/item_tooltip_presenter.gd:10` 用 `static var` 作进程内共享状态。
- 倍率是「行动值 ↔ 等待时长」这条公式上的一个系数，与同文件的 `GAME_TIME_POINTS_PER_HOLD_SECOND` 同源，放在一起可读性最好。

**代价与处置：** 静态状态在同进程的测试之间会残留。设计要求所有触碰倍率的测试在结束时复位（见 §5），而不是给静态变量加自动清理 —— 后者会掩盖测试自身的顺序依赖。

### 1.3 明确不动的部分

- `get_hold_duration_seconds()` 保持 `cost / 10` 的纯换算，不含倍率。
- `TimeSystem.MapMoveTimeCost` 与 `SetMapMoveTimeCost` 保留，值恒为导出默认 10。
- `begin_hold` 的签名与语义不变。

## 2. 数据流与契约

### 2.1 写入路径

```
HoldSpeedSpinBox.value_changed
  → DevSettingsUI._on_hold_speed_spin_box_value_changed(value)
  → WorldInteractionTiming.set_hold_speed_multiplier(value)   # 内部夹紧 > 0
```

### 2.2 读取路径

```
begin_hold(owner, cost, cb, target)
  └→ begin_timed_hold(owner, get_hold_duration_seconds(cost), cb, target)   # 仍传基础秒数
       └→ effective = scale_hold_seconds(seconds)                          # 缩放只发生在这里
            ├─ effective <= 0 → 即时回调（零消耗交互的单击体验不变）
            └─ tween_method(set_hold_progress, 0.0, 1.0, effective)
```

`begin_hold` 传基础秒数是**硬约束**：若它先缩放、`begin_timed_hold` 再缩放一次，实际会变成 k²。

### 2.3 契约

- `scale_hold_seconds(base)`：`base <= 0` 返回 `0.0`；倍率为 1 时恒等于 `base`。
- `set_hold_speed_multiplier(v)`：`v <= 0`、非数值或 NaN 一律夹紧到下界常量；上界不在这一层收口 —— 它是公共 API，将来可能被非 UI 调用方以别的范围使用。
- 倍率的可调范围 `0.1 ~ 10` 是 **UI 层** 的收口（SpinBox min/max/step），与既有 `_configure_gold_spin_box()` 同一套「场景写一遍供编辑器预览、脚本再收口一次」的做法。

## 3. UI 改造

### 3.1 场景结构

`CostRow` 那一行整体替换为倍率行（保持「一个功能独占一行」的既有排版，`test_dev_settings_contract.gd:45-53` 与 `:494` 锁定了这条规则）：

```
HoldSpeedRow (HBoxContainer, unique_name_in_owner=true)
├── HoldSpeedLabel   (Label)      text = "长按速度倍率"
└── HoldSpeedSpinBox (SpinBox)    unique_name_in_owner=true
                                  min_value = 0.1 / max_value = 10 / step = 0.1 / value = 1
```

`ResetCostButton` 重命名为 `ResetHoldSpeedButton`（文本仍是「恢复默认」）。重命名而非沿用旧名，是因为节点名里的 `Cost` 在新语义下会误导 —— 它现在复位的是速度倍率，与行动值消耗无关。

### 3.2 脚本改造

| 成员 | 处置 |
|---|---|
| `DEFAULT_ACTION_COST`、`MAX_ACTION_COST` | 删除，替换为 `DEFAULT_HOLD_SPEED_MULTIPLIER = 1.0`、`MIN_HOLD_SPEED_MULTIPLIER = 0.1`、`MAX_HOLD_SPEED_MULTIPLIER = 10.0` |
| `_cost_row`、`_cost_spin_box`、`_reset_cost_button` | 替换为 `_hold_speed_row`、`_hold_speed_spin_box`、`_reset_hold_speed_button` |
| `_configure_cost_spin_box()` | 替换为 `_configure_hold_speed_spin_box()` |
| `_on_cost_spin_box_value_changed()` | 替换为 `_on_hold_speed_spin_box_value_changed()`，写 `set_hold_speed_multiplier` |
| `_on_reset_cost_button_pressed()` | 替换为 `_on_reset_hold_speed_button_pressed()`，写回 `1.0` |
| `_sync_from_time_system()` 中的 `MapMoveTimeCost` 回填 | 删除 |
| 新增 `_sync_hold_speed_from_multiplier()` | 用 `set_value_no_signal` 从静态倍率回填，保证面板显示与真实生效值一致 |
| `_apply_feature_visibility()` 的 `run_only_rows` | 两项替换为新行与新按钮 |
| `_connect_buttons()` | 换接新信号 |
| `_on_close_button_pressed()` | 释放焦点改为新输入框 |

`_sync_hold_speed_from_multiplier()` 的必要性：金币框是「要加多少」的一次性输入、不镜像外部状态，而倍率**有**外部权威（静态变量可能被别处改），因此打开面板时要回填，不能像金币框那样只在脚本里写死初始值。

## 4. 兼容性与迁移

- **无数据迁移**：倍率不落盘，`.tres`、存档、`project.godot` 都不受影响。
- **场景文件**：`dev_settings_ui.tscn` 只增删节点；新增节点的 `unique_id` 由编辑器在保存时补齐。改完必须 `git diff` 核对 diff 形态只有预期的增删，避免编辑器把整份场景重写。
- **既有测试**：`tests/godot/test_dev_settings_contract.gd` 的 6 处断言必须同批更新（`REQUIRED_VBOX_ROWS`、写入与夹紧测试、`run_only_names`、场景标签断言、缓存重挂回断言、最小节点树构造）。该套件已在 `tests/` 顶层有壳文件，无需新增壳。

## 5. 测试策略

- **纯换算层**：`scale_hold_seconds` 与 `set_hold_speed_multiplier` 的夹紧行为，直接断言，不需要场景。
- **控制器层**：断言 `begin_timed_hold` 在倍率 2 下建立的 Tween 时长减半。控制器是 Node，在测试里以最小节点树构造（既有套件已有该做法），并在结束时 `cancel_active_hold()`。
- **面板层**：断言 SpinBox 默认值、写入倍率、越界夹紧、恢复默认、以及删除后的场景不再含 `CostRow`。
- **复位纪律**：每个触碰倍率的测试在结束前把倍率写回 `1.0`。这是静态状态的代价，必须显式承担。

## 6. 权衡与已知取舍

| 取舍 | 选择 | 理由 |
|---|---|---|
| 倍率是否缩放行动值扣费 | **不缩放** | 需求明确：只加速手感，不影响天数推进与资源平衡 |
| `get_required_hold_seconds()` 是否含倍率 | **不含** | 它在生产代码中无调用方；若含倍率，就与「控制器是唯一计时权威」形成两个真相来源。将来若要用它显示「还需按 X 秒」，让它改走 `scale_hold_seconds()` |
| 拆除（不消耗行动值）是否也变速 | **变速** | 需求是「所有长按」；且它复用同一个计时执行点 |
| 倍率放静态变量而非 Autoload | 静态变量 | 避免给面板增加节点依赖与缓存挂回恢复逻辑；项目有先例 |
| `ResetCostButton` 重命名 | **重命名** | 旧名里的 `Cost` 在新语义下误导；代价是场景 + 4 处测试引用要同步 |

## 7. 回滚

改动集中在 4 个产品文件 + 1 个测试文件，每个都可单文件 `git checkout --` 还原：

- `core/constants/world_interaction_timing.gd`（新增静态成员）
- `core/gameflow/world_hold_interaction_controller.gd`（`begin_timed_hold` 内施加缩放）
- `core/ui/dev/dev_settings_ui.gd`（控件改造）
- `scenes/ui_scenes/dev_settings_ui.tscn`（节点增删）
- `tests/godot/test_dev_settings_contract.gd`（契约同步）

## 8. 验证要点

⚠️ `tests/godot/world_hold_interaction_tests.gd` 与 `passage_guard_tests.gd` 都是 `extends SceneTree` 的独立运行脚本（`tests/` 下共 13 个），**不注册为 `McpTestSuite`**，因此不能用 `test_run` 运行；项目也不允许用命令行 `--script` 跑它们（无法正确加载 autoload）。本次改动涉及的长按断言必须落在**可运行**的套件里 —— 即把 `world_hold_interaction_tests.gd:35-47` 那组纯换算断言复刻进 `dev_settings_contract`，让它们在 `test_run` 下真正被执行。

| 目标 | 手段 |
|---|---|
| 契约与 UI（含新增倍率断言） | `test_run(suite="dev_settings_contract")` |
| 纯换算与缩放规则 | 在可运行套件内直接断言 `get_hold_duration_seconds`（0→0.0、10→1.0、20→2.0、−5→0.0）与 `scale_hold_seconds` 的倍率行为 |
| 协调器长按入口未回归 | `test_run(suite="world_interaction_coordinator_contract")` |
| 采集链路未回归 | `test_run(suite="reusable_gathering")` |
| 时间常量未动 | `test_run(suite="core_constants_contract")` |
| 运行期真实生效 | 冒烟 `project_run` + `game_eval`：设置倍率后直接驱动控制器，读回实际 Tween 时长；并确认行动值扣费不随倍率变化 |
| 面板可操作 | `project_run(mode="main")` → 输入 LISBAM 序列 → `editor_screenshot(source="game")` |
