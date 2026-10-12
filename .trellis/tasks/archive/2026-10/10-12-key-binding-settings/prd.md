# 按键绑定设置

## Goal

在参数设置面板（`scenes/ui_scenes/option_panel.tscn`）新增「按键」分类，让玩家能查看并修改本作全部 10 个已注册输入动作的键位；修改立即生效、自动保存，重开游戏后仍然有效。

用户价值：玩家不必再忍受固定键位（例如 WASD 与个人习惯冲突），键位偏好与已有的「地图」「背包」偏好一样跨重启保留。

技术设计与实施步骤分别见同目录的 `design.md` 与 `implement.md`。

## Background（已确认事实）

### 现有输入动作清单（来源：`project.godot:62` 起的 `[input]` 段）

| 动作名 | 注册行 | 当前键位 | 键位字段 | 代码消费方 |
|---|---|---|---|---|
| `move_up` | `project.godot:79` | W | `physical_keycode:87` | `scripts/player_scripts/PlayerChar.gd:18`、`scripts/player_scripts/states/Idle.gd:26`、`states/Walk.gd:29`、`states/ClickWalk.gd:38,53,65`、`core/gameflow/world_interaction_coordinator.gd:208,547` |
| `move_down` | `project.godot:84` | S | `physical_keycode:83` | 同上 |
| `move_left` | `project.godot:89` | A | `physical_keycode:65` | 同上 |
| `move_right` | `project.godot:94` | D | `physical_keycode:68` | 同上 |
| `toggle_inventory` | `project.godot:64` | B | `physical_keycode:66` | `core/ui/hud/hud_controller.gd:15,52` |
| `toggle_crafting` | `project.godot:69` | Tab | `keycode:4194306` | `core/ui/hud/hud_controller.gd:13,43` |
| `interact_building` | `project.godot:74` | F | `physical_keycode:70` | `core/building/building_controller.gd:205` |
| `open_map` | `project.godot:104` | T | `physical_keycode:84` | `scripts/map_scripts/UILargeMap.gd:43` |
| `pause_game` | `project.godot:99` | ESC | `keycode:4194305` | `core/ui/hud/pause_menu.gd:16,97`、`core/building/building_controller.gd:187,377` |
| `check` | `project.godot:109` | Enter | `physical_keycode:4194309` | **全仓库无任何引用**（历史遗留，仍按用户要求纳入面板，并以「当前版本未使用」标注） |

`rg` 全仓库扫描确认：以上 10 个动作之外，没有任何 `.gd` 通过 `Input.is_action_*` / `InputMap.*` / `event.is_action_*` 使用其它自定义动作。移动向量统一走 `Input.get_vector("move_left","move_right","move_up","move_down")`。

### 现有设置面板

- 场景 `scenes/ui_scenes/option_panel.tscn`，脚本 `scripts/ui_scripts/UIOptionPanel.gd`。
- 面板被两处复用：`scenes/ui_scenes/pause_menu.tscn:120`（局内暂停菜单）与 `scenes/main_menu_scenes/login_menu.tscn:144`（主菜单「游戏设置」）。
- 现有分类：`%MapCategoryButton`（地图）+ `%InventoryCategoryButton`（背包），各自对应 `%MapSettings` / `%InventorySettings` 容器；切换逻辑在 `UIOptionPanel.gd:72-83`。
- 偏好落盘统一走 `SettingsManager` 自动加载（`core/autoloads/SettingsManager.gd`，`project.godot:38`），文件为 `user://settings.cfg`；现有约定是「修改会立即生效并自动保存」（`option_panel.tscn:108` 的说明文案）。

### 约束（来自项目规范）

- `.trellis/spec/frontend/state-management.md:34-104`：玩家**偏好**走 `SettingsManager` → `user://settings.cfg`；**不得**写入 `res://` 或项目配置文件，因此不能通过 `ProjectSettings.set_setting` / `ProjectSettings.save()` 持久化键位。
- 同规范 `:59-61`：读取方必须提供安全默认值并在读取后校验领域值；存储键使用稳定英文 `section/key`，显示文案与存储值分离；UI 组件只发出变更意图，由领域拥有者校验并写入。
- `.trellis/spec/frontend/quality-guidelines.md:23-25`：改动脚本/节点/信号前用 `rg` 查引用；`.tscn` 导出值不等于运行时注入成功，必须真实场景运行验证。
- `AGENTS.md` / `agent.local.md`：验证必须通过已打开的 Godot 4.7.1 编辑器 MCP；不得使用旧版命令行 Godot；对既有代码只做增量修改，不重命名变量、不删改既有注释；改动后必须同步 `docs/游戏机制与玩法内容.md` 并追加 `临时反馈文档.md`。
- `tests/godot/test_map_ui_contract.gd:386-387` 已锁定 `open_map` 在 `project.godot` 中绑定物理 T 键，且 `UILargeMap.gd` 不得硬编码按键。键位持久化走 `settings.cfg`，因此该断言必须继续通过。
- 改动前基线（编辑器 MCP `test_run`）：`total=543, passed=492, failed=11, skipped=40`。其中 `map_ui_contract::test_map_interaction_and_option_panel_contracts` 已失败，根因是 `scripts/map_scripts/UILargeMap.gd` 缺少 `@export var open_map_action: StringName = &"open_map"`（`tests/godot/test_map_ui_contract.gd:392`），与本任务无关，不在本次修复范围。由于该断言失败会让同一测试方法后续断言短路，新增测试必须独立断言面板结构。完整既有失败清单见 `implement.md` §0。

## Requirements

- **R1 分类入口**：参数设置面板新增第三个分类「按键」，与现有「地图」「背包」互斥切换；`UIOptionPanel` 的两个宿主（暂停菜单、登录菜单）都能进入该分类。
- **R2 动作清单**：分类内列出上表全部 10 个已注册动作，按功能分组显示中文名（显示名与动作名分离）；`check` 额外标注「当前版本未使用」。
- **R3 查看当前键位**：每行显示该动作当前生效的按键文本（读取运行时 `InputMap`，而不是读取 `project.godot`）。
- **R4 重绑**：点击某行的按键按钮后进入「等待按键」状态，玩家按下键盘按键即完成绑定；等待期间该按键不得泄漏给游戏其它输入处理（按 ESC 不弹出暂停菜单，而是取消本次改键）。支持随按键一起记录 Ctrl/Alt/Shift/Meta；纯修饰键单独按下被忽略。
- **R5 冲突处理**：允许两个动作绑定同一个键，但界面必须把重复键的文案标红，让玩家能看出存在同键动作。冲突范围只统计这 10 个可重绑动作之间，不把 Godot 内置 `ui_*` 动作算作冲突。
- **R6 立即生效**：绑定成功后立即写入运行时 `InputMap`，玩家回到游戏后新键位立刻可用，不需要重启或重进场景。
- **R7 持久化**：绑定结果写入 `SettingsManager` 的 `user://settings.cfg`；游戏重启后自动恢复到玩家设定的键位。落盘失败时本次运行仍然生效，但界面必须明确提示「重启后会丢失」。
- **R8 全部恢复默认**：提供「全部恢复默认」按钮，一键把 10 个动作恢复到项目默认键位（启动时从 `InputMap` 快照，唯一来源仍是 `project.godot`），并清除已保存的键位偏好。
- **R9 容错**：`settings.cfg` 缺失、键位记录损坏或动作在 `InputMap` 中不存在时，必须回退到项目默认键位并给出可见日志，不得阻塞启动或让面板报错。

## Acceptance Criteria

- [ ] AC1 暂停菜单「参数设置 → 按键」与主菜单「游戏设置 → 按键」都能看到 10 行绑定项，中文名与当前键位正确（W/S/A/D、B、Tab、F、T、ESC、Enter），`check` 行带有「当前版本未使用」标注。
- [ ] AC2 在面板中把 `move_up` 改为方向键上，关闭设置回到游戏后按「上」角色向上移动，按 W 不再移动。
- [ ] AC3 等待按键状态下按 ESC 不会弹出暂停菜单，而是取消本次重绑（按钮文案恢复为当前键位）。
- [ ] AC4 把两个动作绑到同一个键后，界面不报错、两个动作都生效，且这两行的键位文案以红色显示；把其中一个改成别的键后红色消失。
- [ ] AC5 修改键位后退出游戏并重新启动，面板显示的键位与修改后一致，且该键位在游戏中实际生效。
- [ ] AC6 点击「全部恢复默认」后 10 个动作回到 W/S/A/D、B、Tab、F、T、ESC、Enter，游戏中立即生效，重启后仍是默认值。
- [ ] AC7 手工把 `user://settings.cfg` 的 `[input]` 记录改成非法内容后启动游戏：游戏正常进入主菜单，控制台有可诊断警告，面板显示默认键位。
- [ ] AC8 现有回归测试继续通过：全量 `test_run` 的失败集合与基线（`implement.md` §0 的 11 项）完全一致，不新增失败；`project.godot` 的 `open_map` 仍绑定物理 T 键、`[input]` 段未被改动。
- [ ] AC9 新增契约测试锁定「`project.godot` 的 `[input]` 动作集合 == 可重绑动作清单」双向相等，防止以后新增动作漏进面板。
- [ ] AC10 新键位只替换该动作的键盘事件；为动作预置的手柄/鼠标事件在改键后仍然存在（由契约测试覆盖）。

## Out of Scope

- **鼠标与手柄绑定**：项目当前没有任何 `joy_*` 绑定，鼠标操作全部是硬编码的 `Input.is_mouse_button_pressed` / 控件 `gui_input`（例如 `core/building/building_controller.gd:490`），不是 InputMap 动作；本任务只做键盘单键绑定。相关兼容性要求仅限「改键不得破坏已有非键盘事件」（AC10）。
- **Godot 内置 `ui_*` 动作**：`core/ui/login_menu_controller.gd:83` 使用内置 `ui_accept`（回车/空格），它由 Godot 的 Control 焦点系统全局消费，改绑会影响所有按钮、滑条和列表的确认行为，风险面远超「10 个已注册动作」。用户已确认范围为 `project.godot` 已注册的 10 个动作，故不纳入，也不计入冲突统计。
- **单个动作的「恢复默认」按钮**：用户已确认只做「全部恢复默认」。
- **多备用键位**：每个动作只保留一个键位。
- **把键位写回 `project.godot`**：违反「偏好不得写入项目配置」的规范。
- **修复 `UILargeMap.gd` 缺少 `open_map_action` 导出字段导致的既有测试失败**：与本功能无关，保持基线不动。
- **把某个动作绑定到 ESC**：等待按键时 ESC 固定用于取消（与 Godot 自带输入映射编辑器一致），因此 ESC 不可作为绑定目标。属于已知限制，不在面板文案中承诺。

## Key Decisions

| 决策 | 结论 | 来源 |
|---|---|---|
| 动作范围 | `project.godot` 已注册的全部 10 个动作，含未被使用的 `check` | 用户确认 |
| 改键能力 | 单键绑定 + 冲突标红 + 全部恢复默认 | 用户确认 |
| 冲突处理 | **允许同键，重复键文案标红提示** | 用户决策 |
| 键位持久化位置 | `SettingsManager` → `user://settings.cfg` 的 `[input]` 段 | 规范约束 |
| 默认键位来源 | 启动瞬间从 `InputMap` 快照，不复制键码表 | 技术决策（`design.md` §2） |
| 领域拥有者 | 新增 autoload `KeyBindingManager`，排在 `SettingsManager` 之后 | 技术决策（`design.md` §1） |
| 存储键码 | 优先 `physical_keycode`，回退 `keycode`，附修饰键布尔值 | 技术决策（`design.md` §4） |

## Risks / Deferred Items

- 新增 autoload 会改变 `[autoload]` 段内容，需回归 `save_system_contract` 与 `run_start_loadout_contract`；插入位置已避开 `SaveManager` 与参与者的相对顺序。
- `option_panel.tscn` 同时被暂停菜单与登录菜单实例化，两处宿主都必须冒烟验证。
- 面板高度由 `720×440` 调整为 `760×560`，会同时影响「地图」「背包」两个既有分类的可用空间（列表用 `ScrollContainer` 兜底）。
- `check` 目前无任何代码消费，面板中改它不会产生可见效果；已在界面上以「当前版本未使用」标注，等将来接入功能时自动生效。
