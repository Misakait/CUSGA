# 按键绑定设置 — 技术设计

## 1. 分层与边界

沿用项目既有的 `输入 → Controller → Model → 信号 → View` 单向数据流（`.trellis/spec/frontend/state-management.md:3-9`），本功能拆成四层：

| 层 | 文件 | 职责 | 不做什么 |
|---|---|---|---|
| 数据 / 纯函数 | `core/input/key_binding_registry.gd`（新增，`extends RefCounted`，无 `class_name`） | 可重绑动作清单、中文显示名、分组、按键事件的编解码与文案格式化、`SettingsManager` 读写封装 | 不接触节点树，不碰 `InputMap` |
| 领域拥有者 | `core/input/key_binding_manager.gd`（新增，`extends Node`，autoload 名 `KeyBindingManager`） | 启动时把已保存键位应用到 `InputMap`；运行时改键、冲突检测、全部恢复默认；发事实信号 | 不引用任何 UI 节点 |
| View（行） | `scripts/ui_scripts/key_binding_row.gd` + `scenes/ui_scenes/key_binding_row.tscn`（新增） | 显示单个动作的中文名与当前键位；「等待按键」交互；只发出改键意图 | 不写 `InputMap`，不读 `SettingsManager` |
| View / 组装 | `scripts/ui_scripts/UIOptionPanel.gd`（增量修改） | 新增第三个分类；按注册表生成行与分组标题；把行的意图转发给 `KeyBindingManager`；显示反馈与冲突红色标记 | 不实现按键校验规则 |

**为什么需要新的 autoload**：`InputMap` 是全局单例，玩家偏好必须在任何场景 `_ready()` 之前生效，这个启动钩子必须挂在 autoload 上。`SettingsManager` 是通用的偏好读写服务，让它反向依赖输入领域会造成分层倒置，因此新增 `KeyBindingManager`，并在 `project.godot` 的 `[autoload]` 中排在 `SettingsManager` **之后**（`SettingsManager._ready()` 必须先完成 `settings.cfg` 载入）。已核对 `tests/godot/test_save_system_contract.gd:206-229` 的顺序断言：它只要求 `SaveManager` 位于参与者之前，新增非参与者条目不影响该契约。

**不新增 autoload 的替代方案（已否决）**：把应用逻辑写进 `SettingsManager._ready()`。否决理由：违反单一职责，且 UI 需要一个可注入/可替换的领域入口来发信号，塞进通用设置服务会扩散耦合。

## 2. 数据流

### 启动
```
engine 载入 InputMap（来自 project.godot 的 [input] 段，此时是项目默认键位）
  → SettingsManager._ready() 载入 user://settings.cfg
  → KeyBindingManager._ready()
      capture_project_defaults()   # 快照当前 InputMap 作为「项目默认」，供「恢复默认」使用
      apply_saved_bindings()       # 逐个动作读 settings.cfg，命中就替换该动作的键盘事件
```

**默认值来源的选择**：不从 `ProjectSettings.get_setting("input/...")` 读，而是在 `_ready()` 里快照 `InputMap`。理由：① 启动瞬间的 `InputMap` 就是项目默认值，是唯一真相源，不需要在脚本里复制一份键码表；② 不需要假设导出后 `ProjectSettings` 仍能取到输入映射；③ 与 `tests/godot/test_map_ui_contract.gd:386-387` 对 `project.godot` 的文本断言天然一致（默认键位仍然只由 `project.godot` 定义）。

### 改键
```
玩家点击行的按键按钮 → 行进入「等待按键」→ 捕获 InputEventKey
  → row.rebind_requested(action, event)            # View 只发意图
  → UIOptionPanel 转发 KeyBindingManager.rebind(action, event)
  → 校验 → 只替换该动作的键盘事件（保留手柄/鼠标事件）
  → registry.write_saved_event(SettingsManager, action, event)  # 立即落盘
  → binding_changed.emit(action, event)
  → UIOptionPanel 刷新全部行的键位文案与冲突红色标记
```

### 恢复默认
```
点击「全部恢复默认」→ KeyBindingManager.reset_all_to_defaults()
  → 每个动作：registry.erase_saved_event(...) + 把 _default_events 写回 InputMap
  → bindings_reset.emit()
  → UIOptionPanel 刷新全部行
```

## 3. 契约（签名）

### `core/input/key_binding_registry.gd`（全部为 `static`）

```gdscript
## 可重绑动作清单；顺序即面板显示顺序，group 相同者归入同一分组标题。
const REBINDABLE_ACTIONS: Array[Dictionary]   # 元素：{action: StringName, display: String, group: String, note: String}

static func get_rebindable_actions() -> Array[Dictionary]
static func get_action_names() -> Array[StringName]
static func is_rebindable(action: StringName) -> bool
static func get_display_name(action: StringName) -> String
static func get_group_name(action: StringName) -> String
static func get_note(action: StringName) -> String

## 把一次真实按键事件规范化为可存储字典；不可绑定（非键盘、纯修饰键、echo）时返回 {}。
static func encode_event(event: InputEvent) -> Dictionary
## 把存储字典还原为 InputMap 可用的按键模板；非法输入返回 null。
static func decode_event(data: Variant) -> InputEventKey
## 人类可读的键位文案，例如 "W"、"Ctrl+S"、"Escape"；无法识别返回 "未绑定"。
static func format_event_text(event: InputEvent) -> String

## 以下三个通过 settings_source.call(...) 访问，缺失或返回非法值时安全降级。
static func read_saved_event(settings_source: Object, action: StringName) -> InputEventKey
static func write_saved_event(settings_source: Object, action: StringName, event: InputEventKey) -> bool
static func erase_saved_event(settings_source: Object, action: StringName) -> bool
```

### `core/input/key_binding_manager.gd`

```gdscript
signal binding_changed(action: StringName, event: InputEvent)
signal bindings_reset

const SETTINGS_SECTION: String = "input"
const SETTINGS_MANAGER_PATH: NodePath = ^"/root/SettingsManager"

func capture_project_defaults() -> void          # 幂等；只快照一次
func apply_saved_bindings() -> void
func get_binding_event(action: StringName) -> InputEventKey    # 运行时真实生效的键位
func get_default_event(action: StringName) -> InputEventKey
func get_conflicting_actions() -> Array[StringName]            # 当前互相重复的全部动作
func rebind(action: StringName, event: InputEventKey) -> Dictionary
    ## 返回 {ok: bool, reason: String, saved: bool, conflicts: Array[StringName]}
func reset_all_to_defaults() -> void
func set_settings_source(source: Object) -> void               # 测试注入点；生产由 _ready 解析
```

`get_conflicting_actions()` 而不是 `find_conflict(action, event)`：面板一次刷新要把所有重复键标红，逐个动作查询会做 10×10 次比较；一次性返回重复动作集合更简单，也让「允许同键 + 红色标出」这条规则只有一处实现。

## 4. 存储格式

`SettingsManager` 分组 `input`，键为动作名，值为字典（`user://settings.cfg`）：

```ini
[input]
move_up={"ctrl":false,"physical_keycode":87,"shift":false,"alt":false,"meta":false}
```

- 只存 `physical_keycode`（非 0 时）或回退的 `keycode` 二者之一，加四个修饰键布尔值。**优先物理键码**：WASD 类操作跟随键位物理位置，换键盘布局不会让移动键漂移。
- `decode_event` 的校验口径：必须是 `Dictionary`；`physical_keycode` / `keycode` 至少一个为正整数；修饰键字段必须是 `bool`。任何一条不满足即返回 `null`，调用方回退项目默认值并 `push_warning`，对应 PRD 的 R9 / AC7。
- 恢复默认时用 `erase_setting` 删除键，而不是写回默认值：配置里没有记录才真正等于「未修改过」，与 `SettingsManager.erase_setting` 的既有语义（`core/autoloads/SettingsManager.gd:50-66`）一致。
- 不写入 `res://`、不使用 `ProjectSettings.set_setting`，符合 `.trellis/spec/frontend/state-management.md:58`。

## 5. 兼容性与既有契约

- **只替换键盘事件**：应用新键位时逐条 `action_erase_event` 掉 `InputEventKey` 实例，保留该动作上的其它事件类型。这样将来给某个动作补手柄/鼠标绑定时，玩家改键盘不会把那些绑定一起清掉。
- **`project.godot` 的 `[input]` 段保持不变**：它是默认键位的唯一来源，也是 `tests/godot/test_map_ui_contract.gd:386`、`tests/godot/building_system_tests.gd:139-145`、`tests/godot/test_player_movement_input_contract.gd` 的断言对象。玩家的改动只落在 `user://settings.cfg`。
- **`UILargeMap.gd` 的 `open_map` 名字仍硬编码为动作名**，不改动；本功能只换键位不换动作名，因此 `UIOptionPanel` 与地图脚本之间没有新增依赖。
- **既有失败测试不修**：`map_ui_contract::test_map_interaction_and_option_panel_contracts` 当前已失败，原因是 `scripts/map_scripts/UILargeMap.gd` 没有 `@export var open_map_action: StringName = &"open_map"`（`test_map_ui_contract.gd:392`）。该失败与本任务无关；由于 `McpTestSuite.assert_true` 在首个失败后短路（`addons/godot_ai/testing/test_suite.gd:188-195`），该测试里针对 `option_panel.tscn` 的 5 条断言目前实际不生效——所以新增的测试套件必须**独立**断言面板结构，不能依赖它。
- **`ui_accept` 不在范围内**：`core/ui/login_menu_controller.gd:83` 使用 Godot 内置动作，改绑会影响全部 Control 焦点行为（详见 PRD「Out of Scope」）。

## 6. 交互细节与取舍

| 细节 | 决定 | 理由 |
|---|---|---|
| 等待按键时按 ESC | 取消本次改键，不弹出暂停菜单 | 与 Godot 自带输入映射编辑器一致；等待期间行在 `_input` 阶段消费事件并 `set_input_as_handled()`，因此 `pause_menu.gd:96` 的 `_unhandled_input` 收不到该事件（AC3） |
| 能否把动作绑到 ESC | 不能 | 上一条的必然结果，属于已知限制，在面板说明文案中不额外承诺 |
| 修饰键组合 | 支持（Ctrl/Alt/Shift/Meta 随按键一起记录） | 存储与比较天然包含修饰位，不增加 UI 成本；同键不同修饰不算重复 |
| 纯修饰键单独按下 | 忽略，继续等待 | 否则玩家按 Shift 会得到一个无意义的绑定 |
| 冲突处理 | 允许重复，重复键文案标红 | 用户决策；不在服务层拒绝，只由 View 表达 |
| 冲突范围 | 仅限 10 个可重绑动作之间 | 与内置 `ui_*` 比较会误伤常见诉求（例如把移动绑到方向键会与 `ui_up` 重复），因此不把内置动作算作冲突 |
| 落盘失败 | 内存中仍然生效，但反馈文案明确提示「重启后会丢失」 | 符合 `state-management.md:70`「不得假称已跨版本保存」 |
| 面板高度 | `720 × 440` → `760 × 560` | 10 行 + 分组标题 + 说明/反馈/按钮在 `440` 高度下只能看到约 5 行；`560` 在 `720` 视口下仍有余量，列表继续用 `ScrollContainer` 兜底 |

## 7. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 新 autoload 打乱启动顺序，导致存档/时间系统异常 | 插在 `SettingsManager` 之后、`WeatherManager` 之前，不触碰 `SaveManager` 及其参与者的相对顺序；回归 `save_system_contract`、`run_start_loadout_contract` |
| `UIOptionPanel` 同时被暂停菜单与登录菜单复用，改动影响两处 | 只新增分类与子节点，不改动既有两个分类的行为；两处宿主都做冒烟验证 |
| 编辑器改写 `option_panel.tscn`（UID、节点顺序）产生额外 diff | 场景改动统一走编辑器 MCP 并 `scene_save`，改完立即 `git status` 核对只保留本次需要的改动 |
| 键位记录损坏导致启动报错 | `decode_event` 全量类型校验 + 回退默认值 + `push_warning`；AC7 用运行期 `game_eval` 覆盖 |
| 玩家把 `pause_game` 改到别的键后无法打开暂停菜单 | 属于玩家自身选择；「全部恢复默认」始终可用（登录菜单入口不依赖任何可重绑按键） |

回滚方式：删除 `core/input/` 两个新脚本与行场景、撤销 `project.godot` 的 autoload 行、还原 `option_panel.tscn` / `UIOptionPanel.gd` / 文档。`user://settings.cfg` 里的 `[input]` 段在缺少 `KeyBindingManager` 时无人读取，不产生副作用。

## 8. 测试设计

新增 `tests/godot/test_key_binding_settings_contract.gd` + 转发壳 `tests/test_key_binding_settings_contract.gd`（`test_run` 只扫描 `res://tests` 顶层，见 `tests/godot/test_save_system_contract.gd:159` 的既有说明）。

| 测试 | 覆盖 | 关键点 |
|---|---|---|
| `test_project_actions_match_rebindable_registry` | R2 / AC9 | 解析 `project.godot` 的 `[input]` 动作名集合，与 `get_action_names()` 双向相等。这是防「新增动作漏进面板」的唯一硬约束 |
| `test_option_panel_exposes_key_binding_category` | R1 / AC1 | 实例化 `option_panel.tscn`，断言 `%KeyBindingCategoryButton` 是 `Button`、`%KeyBindingSettings` 是 `VBoxContainer`、`%BindingList`、`%ResetAllBindingsButton`、`%BindingFeedbackLabel` 存在；同时复核既有 `%MapCategoryButton` / `%MiniMapZoomSlider` / `%ResetMapButton` / `%BackButton` 未被破坏 |
| `test_key_binding_row_scene_contract` | R4 | 实例化行场景，断言 `%ActionName`、`%KeyButton`、`rebind_requested` 信号与 `setup` / `refresh` / `is_listening` 方法存在 |
| `test_encode_decode_round_trip` | R7 / R9 | 物理键、修饰键组合往返相等；`null` / `{}` / 缺字段 / 字段类型错误 / 零键码一律返回 `null` |
| `test_read_saved_event_falls_back_on_corrupt_value` | R9 | 桩设置源返回垃圾值 → `null`；返回合法字典 → 事件；`settings_source` 为 `null` → `null` 且不抛错 |
| `test_rebind_replaces_only_keyboard_events` | R6 / R5 | 夹具在 `InputMap` 里为 `move_up` 装上「键盘 + 手柄」两个事件（沿用 `tests/godot/test_inventory_component_contract.gd:700-725` 的临时动作夹具与清理写法），`rebind` 后断言新键生效、旧键消失、**手柄事件仍在**；再把 `move_up` 与 `move_down` 绑成同键，断言 `get_conflicting_actions()` 同时包含两者 |
| `test_autoload_registered_after_settings_manager` | 启动顺序 | `ProjectSettings.get_setting("autoload/KeyBindingManager")` 非空且能解析到服务脚本；`project.godot` 文本中 `SettingsManager` 行先于 `KeyBindingManager` 行 |

运行期（`test_run` 没有 autoload，`InputMap` 也不含项目动作，见 `tests/test_pause_menu_contract.gd:83-85`）覆盖不到的部分，统一交给编辑器 MCP 的运行验证，见 `implement.md` 的验证清单。
