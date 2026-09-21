# 技术设计 — 开发者设置窗口（LISBAM 入口）

## 1. 架构与边界

### 1.1 挂载位置的决定依据

`Main/UI/HUDLayer` 是唯一一个在**局外游玩**与**局内战斗**两种状态下都存活的 UI 宿主：

- 局外：`Main.tscn` 是 `current_scene`。
- 局内战斗：`core/gameflow/world_interaction_coordinator.gd:30` 把 `battle.tscn` 作为 `Main` 的**子节点**挂载，`current_scene` 仍是 `Main`（`scripts/ui_scripts/status_effect_bar.gd:151` 的注释同样记录了这一事实）。

因此入口与面板都挂在 `Main/UI/HUDLayer/HUDRoot` 下，不引入新的 Autoload，也不改动任何既有脚本。

### 1.2 新增/改动清单

| 类型 | 路径 | 说明 |
|---|---|---|
| 新增 | `core/ui/dev/dev_sequence_matcher.gd` | 纯逻辑按键序列匹配器（`RefCounted` + `class_name`），无副作用、可单测 |
| 新增 | `core/ui/dev/dev_settings_ui.gd` | 面板控制器：序列监听、面板开关、两项功能的执行 |
| 新增 | `scenes/ui_scenes/dev_settings_ui.tscn` | 面板场景（根 `Control` + 居中 `PanelContainer`） |
| 改动 | `scenes/Main.tscn` | 在 `UI/HUDLayer/HUDRoot` 下新增一个 `DevSettingsUI` 实例 |
| 新增 | `tests/godot/dev_settings_tests.gd` | 序列匹配与「下一天」点数计算的运行期测试 |

**不改动**任何既有 `.gd` 脚本、`TimeSystem`、`SettingsManager`、`TimeCosts` —— 本任务的回归面因此收敛为「Main.tscn 多一个隐藏节点」。

### 1.3 依赖方向

```
Main.tscn (UI/HUDLayer/HUDRoot/DevSettingsUI)
        │
        ▼
dev_settings_ui.gd ──uses──▶ dev_sequence_matcher.gd   (纯逻辑)
        │
        └──calls──▶ TimeSystem (Autoload, 既有)
                      ├─ PassTime(amount)
                      ├─ SetMapMoveTimeCost(amount)
                      ├─ get_TotalTimePassed() / get_CurrentDay()
                      ├─ PhaseLength
                      └─ signal TimeChanged(...)
```

面板只**调用** `TimeSystem` 的既有公开 API，不读写真值（`_total_time_passed` / `_current_day` 均为私有）。

## 2. 契约

### 2.1 序列匹配器（`dev_sequence_matcher.gd`）

```gdscript
class_name DevSequenceMatcher
extends RefCounted

const SEQUENCE: String = "LISBAM"

## 送入一个已归一化为大写单字母的输入；返回是否刚好凑齐完整序列。
func push_letter(letter: String) -> bool

## 读取当前已匹配的进度（0..SEQUENCE.length()）。
func get_progress() -> int

## 清空进度。
func reset() -> void
```

匹配规则（满足 R1「按错键后从该键重新开始」）：

- 与 `SEQUENCE[progress]` 相等 → `progress += 1`。
- 不相等 → `progress = 1`（若该键就是 `SEQUENCE[0]`，即 `L`）否则 `progress = 0`。这使 `L L I S B A M` 仍能触发。
- 凑齐后 `progress` 归零并返回 `true`。

**为什么独立成类**：面板脚本带 `@onready` 场景依赖，无法在测试里直接实例化；把状态机抽成无依赖的 `RefCounted` 后，`tests/godot/` 可以纯逻辑断言，无需启动真实游戏进程。

### 2.2 字母归一化（`dev_settings_ui.gd`）

```gdscript
func _resolve_letter(event: InputEventKey) -> String
```

- 只接受 `pressed == true` 且 `echo == false` 的事件（过滤长按重复）。
- 优先用 `OS.get_keycode_string(event.physical_keycode)`：物理键位不受 Shift / CapsLock / 输入法影响。
- 若上一步得不到单字母，回退到 `event.unicode`（`String.chr(unicode).to_upper()`）。
- 非字母键返回空串，调用方直接忽略（**不重置进度**，这样 `L I S B A M` 之间夹一个方向键不会打断序列）。

**零副作用约束**：处理函数**不调用** `get_viewport().set_input_as_handled()`，也不注册 InputMap 动作。因此该监听对既有 `toggle_inventory` / `toggle_crafting`（`core/ui/hud/hud_controller.gd`）与一切 UI 输入完全透明。

### 2.3 「下一天」（`dev_settings_ui.gd`）

```gdscript
func _get_points_to_next_day() -> int
```

依据 `core/autoloads/time_system.gd` 的既有规则推导（**不新增规则**）：

- `PhaseLength = 100`，一天 = 白天 + 夜晚 = 2 个阶段。
- `_check_time_transitions` 只在 `phase % 2 == 0` 时执行 `_current_day += 1` 并 `DayPassed.emit()`。
- 因此「下一天」= 推进到**下一个偶数阶段边界**。

```gdscript
var total: int = TimeSystem.get_TotalTimePassed()
var current_phase: int = total / TimeSystem.PhaseLength        # 整数除法，与 time_system.gd:80 一致
var next_even_phase: int = current_phase + 1
if next_even_phase % 2 != 0:
	next_even_phase += 1
return next_even_phase * TimeSystem.PhaseLength - total
```

| `total` | `current_phase` | `next_even_phase` | 返回 | 结果 |
|---|---|---|---|---|
| 0 | 0 | 2 | 200 | 天数 1 → 2，落在白天起点 |
| 50 | 0 | 2 | 150 | 天数 1 → 2 |
| 150 | 1 | 2 | 50 | 天数 1 → 2（当前是夜晚） |
| 200 | 2 | 4 | 200 | 天数 2 → 3 |

推进一律走 `TimeSystem.PassTime(amount)`，由它按既有顺序发出 `DayNightToggled` / `DayPassed` / `TalentSelectionTriggered` / `TimeChanged`。

**为什么不能直接改 `_current_day`**：那会跳过昼夜切换、天赋选择、天气等依赖信号的系统，产生「天数变了但世界状态没跟上」的撕裂状态。

### 2.4 行动值消耗控件（`dev_settings_ui.gd`）

- 控件用 `SpinBox`（`min_value = 1`、`max_value = 999`、`step = 1`）。选它是因为它**原生夹紧**非整数与越界输入，直接满足 R4 的「非法输入必须被拒绝或夹紧」，不需要自建校验分支。
- `value_changed` → `TimeSystem.SetMapMoveTimeCost(int(value))`。该 setter 本身已有 `if amount > 0` 守卫（`time_system.gd:59-61`），构成第二道防线。
- 「恢复默认」按钮 → 设回 `10`。
- 面板打开时用 `TimeSystem.MapMoveTimeCost` 同步控件初值。
- 面板关闭时调用 `_cost_spin_box.release_focus()`：避免隐藏的 `SpinBox` 继续持有键盘焦点、吞掉后续 `LISBAM` 输入。

### 2.5 面板显示刷新（`dev_settings_ui.gd`）

- 在 `_ready` 中连接 `TimeSystem.TimeChanged`，在 `_exit_tree` 中断开（符合 `frontend/quality-guidelines.md` 的场景安全要求）。
- 天数标签只在信号回调里刷新，因此**任何来源**的时间推进（地图移动、下一天按钮）都会让显示保持一致。

### 2.6 不暂停的落实

面板不触碰 `get_tree().paused`，也不设置任何 `process_mode`。面板自身保持默认 `PROCESS_MODE_INHERIT`，游戏逻辑照常运行。

## 3. 场景结构

```text
Main (Node)
└─ UI (Node)
   └─ HUDLayer (CanvasLayer)
      └─ HUDRoot (Control)
         ├─ ... 既有 HUD 节点 ...
         └─ DevSettingsUI (Control, 新增实例, 默认 visible = false)
            └─ Panel (PanelContainer, anchors_preset = center)
               └─ MarginContainer
                  └─ VBoxContainer
                     ├─ TitleLabel      "开发者设置"
                     ├─ DayLabel        "当前天数：N"
                     ├─ CostRow (HBoxContainer)
                     │  ├─ CostLabel    "行动值消耗"
                     │  └─ CostSpinBox  (SpinBox)
                     └─ ButtonRow (HBoxContainer)
                        ├─ NextDayButton    "下一天"
                        ├─ ResetCostButton  "恢复默认"
                        └─ CloseButton      "关闭"
```

- 根 `Control` 默认 `visible = false`，`mouse_filter = MOUSE_FILTER_IGNORE`（未打开时不拦截任何鼠标事件）。
- 子节点用固定路径 `@onready` 获取，与 `battle_settings_panel.gd` 的既有惯例一致。
- 关闭按钮的 `focus` 样式按 `frontend/component-guidelines.md` 的陷阱说明处理为 `StyleBoxEmpty`，避免双重边框。

## 4. 权衡与取舍

| 决策 | 选择 | 放弃的方案 | 理由 |
|---|---|---|---|
| 挂载点 | `Main.tscn` 的 `HUDLayer` | 新建 Autoload | 只有 Main 场景需要它；新增 Autoload 会扩大全局面且违反「无本地所有者才加 Autoload」的项目约定 |
| 输入阶段 | `_unhandled_input` | `_input` | 让既有 UI（背包、仓库）先消费输入，不抢焦点 |
| 字母来源 | `physical_keycode` 优先 | 只用 `unicode` | 不受 Shift / CapsLock / 输入法影响 |
| 数值控件 | `SpinBox` | `LineEdit` + 手写校验 | 原生夹紧非法输入，少一条易错的自建分支 |
| 序列逻辑 | 独立 `RefCounted` | 内联在面板脚本 | 可被 `tests/godot/` 纯逻辑测试覆盖 |
| 持久化 | **不持久化** | 写入 `SettingsManager` | 用户已确认；避免调试值污染玩家存档，重开即回默认 10 |

## 5. 兼容性与回滚

- **兼容性**：不修改任何既有脚本与资源；`TimeSystem` 的公开协议、`TimeCosts` 常量契约、战斗内 ATB `action_value` 均不受影响。
- **回滚**：`scenes/Main.tscn` 中删除 `DevSettingsUI` 节点，再删除三个新增文件与测试文件即可完全还原。`Main.tscn` 的改动是**纯增量**（新增一个节点段），不会触碰既有节点定义。
- **已知副作用**：运行 Godot 编辑器会重排 `.cs` 缩进并改写 `CUSGA.csproj` 的 SDK 版本（见 `frontend/quality-guidelines.md`）。本任务不涉及 C# 文件，验证后仍须 `git status --porcelain` 复查并还原非预期改动。

## 6. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| `SpinBox` 持有焦点吞掉 `LISBAM` | 关闭面板后序列失效 | 关闭时 `release_focus()`；面板打开时序列本就无需再触发（R1 幂等） |
| 「下一天」跨过第 7 天倍数触发天赋选择 | 玩家被弹出天赋界面 | 这是 `TimeSystem` 的既有契约，属于正确行为，**不特殊处理**；在验收中确认信号按既有规则发出 |
| 面板遮挡 HUD 导致无法操作 | 调试时体验差 | 面板居中且尺寸受限；关闭按钮常驻；默认隐藏 |
| `Main.tscn` 改动破坏主场景 | 游戏无法启动 | 改动为纯增量；`project_run(mode="custom", scene="res://scenes/Main.tscn")` + `logs_read(source="game")` 冒烟作为门禁 |
| `class_name` 未刷新导致解析失败 | `Parse Error: Could not find type` | 新增 `DevSequenceMatcher` 后先 `filesystem_manage(op="scan")` 再冒烟 |
