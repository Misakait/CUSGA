# 按键绑定设置 — 实施计划

## 0. 基线（改动前已实测，2026-10-12）

编辑器 MCP `test_run`（`scene_open("res://scenes/main_menu_scenes/login_menu.tscn")` 后）：

- `total=543, passed=492, failed=11, skipped=40`
- `load_errors`: `test_item_room_content.gd (cannot instantiate — abstract or broken)`

**11 项既有失败（均与本任务无关，不修）**：

1. `board_controller_contract::test_shared_log_and_error_texts`
2. `crafting_recipe_contract::test_production_scenes_avoid_csharp_crafting_scripts`
3. `final_migration_audit_contract::test_custom_type_script_metadata_matches_attached_script`
4. `final_migration_audit_contract::test_inlined_host_exposes_named_replacements`
5. `gameflow_chain_contract::test_chain_boundaries`
6. `map_ui_contract::test_map_interaction_and_option_panel_contracts` ← 与本次改动同区域，**已确认根因**：`scripts/map_scripts/UILargeMap.gd` 缺少 `@export var open_map_action: StringName = &"open_map"`（`tests/godot/test_map_ui_contract.gd:392`）。不修，但必须确认本次改动没有让它变多
7. `reusable_gathering::test_production_plain_item_assets_use_gdscript_item_data`
8. `save_system_contract::test_save_manager_is_first_autoload_before_participants`
9. `world_interaction_coordinator_contract::test_cross_language_boundaries`
10. `world_interaction_coordinator_contract::test_production_script_shape`
11. `world_interaction_coordinator_contract::test_shared_log_and_error_texts`

验收口径：改动后 `failed` 仍为 11 项且集合不变，新增套件全绿。

## 1. 硬约束（来自 `agent.local.md`，优先级高于 `AGENTS.md`）

- 验证一律走已打开的 Godot 4.7.1 编辑器 MCP（`addons/godot_ai`）；**不得**使用 `godot-mono` / 命令行 Godot / `--check-only --script`。
- 测试结束后只 `project_manage(op="stop")`，**不关闭编辑器**。
- **尊重原版**：不重命名既有变量，不删除/篡改既有注释；对 `UIOptionPanel.gd` 只做**增量**修改。
- **文档同步**：功能代码改动后必须同步 `docs/游戏机制与玩法内容.md`（新增「按键绑定设置」小节，并在「局内暂停菜单」小节补充设置面板新增分类的事实与具体键位数值）。
- **学习反馈摘要 + Git 提交描述**：改动完成后在回复中给出，并**追加写入**项目根目录 `临时反馈文档.md`（时间戳格式 `YYYY-MM-DD HH:MM`，只追加不覆盖）。
- PowerShell 5.1 读文本必须显式 `-Encoding UTF8`。

## 2. 实施清单（按顺序）

### 步骤 1：数据层
1. `script_create("res://core/input/key_binding_registry.gd")`，实现 `design.md` §3 的全部 `static` 函数与 `REBINDABLE_ACTIONS`。
   - 动作顺序与分组：`移动` = move_up / move_down / move_left / move_right；`界面` = toggle_inventory / toggle_crafting / open_map / check；`交互` = interact_building / pause_game。
   - 中文显示名：向上移动 / 向下移动 / 向左移动 / 向右移动 / 打开背包 / 打开合成 / 打开地图 / 检查 / 交互建筑 / 暂停游戏。
   - `check` 的 `note` 为「当前版本未使用」，面板以次要颜色显示，避免玩家以为它没生效。
   - 每个变量、每个公开函数都要有中文 `##` 文档注释（含参数与返回值）。
2. `filesystem_manage(op="scan")`，确认生成 `.gd.uid` 旁车。

### 步骤 2：领域服务
3. `script_create("res://core/input/key_binding_manager.gd")`，实现 `design.md` §3 的服务契约。
   - `_ready()`：解析 `SETTINGS_MANAGER_PATH`（`get_node_or_null`，缺失时 `push_warning` 一次并继续）→ `capture_project_defaults()` → `apply_saved_bindings()`。
   - `_apply_event(action, event)`：逐条 `action_erase_event` 掉 `InputEventKey`，再 `action_add_event`；动作不存在时 `push_warning` 并跳过。
   - `rebind()` 返回 `{ok, reason, saved, conflicts}`；`saved=false` 时不谎称已保存。
4. `project.godot`：在 `SettingsManager="*res://core/autoloads/SettingsManager.gd"` 之后插入 `KeyBindingManager="*res://core/input/key_binding_manager.gd"`。
   - **只加这一行**，不得调整其它 autoload 的相对顺序。
5. `filesystem_manage(op="scan")` → `editor_state` 确认无 `Parse Error` / `Failed to load script`。

### 步骤 3：行 View
6. `scene_manage(op="create", path="res://scenes/ui_scenes/key_binding_row.tscn", root_type="HBoxContainer", root_name="KeyBindingRow")`。
7. 在根下建 `ActionName`（`Label`，`custom_minimum_size = 170×0`）、`Note`（`Label`，`size_flags_horizontal = 3`，灰色 `modulate`）、`KeyButton`（`Button`，`custom_minimum_size = 200×40`），三者都 `unique_name_in_owner = true`。
8. `script_create("res://scripts/ui_scripts/key_binding_row.gd")` 后 `script_attach` 到根；实现 `setup()` / `refresh()` / `is_listening()` / `rebind_requested` 信号。
   - 等待按键：`_on_key_button_pressed` 进入监听并 `set_process_input(true)`；`_input` 里忽略 `echo` 与松开事件、忽略纯修饰键、ESC 取消、其余按键发出意图；所有被消费的事件都 `get_viewport().set_input_as_handled()`。
   - `refresh(event, is_conflicting)`：`is_conflicting` 为真时对 `font_color` / `font_hover_color` / `font_pressed_color` / `font_hover_pressed_color` / `font_focus_color` 五个主题色做红色覆盖，为假时 `remove_theme_color_override` 逐个移除（只覆盖 `font_color` 会在悬停/按下时看不到红色）。
9. `scene_save`。

### 步骤 4：面板接线
10. `scene_open("res://scenes/ui_scenes/option_panel.tscn")`，用 MCP 增量编辑：
    - `Body/Categories` 下新增 `KeyBindingCategoryButton`（`Button`，`toggle_mode = true`，`custom_minimum_size = 0×48`，文本「按键」，`unique_name_in_owner = true`）。
    - `Body` 下新增 `KeyBindingSettings`（`VBoxContainer`，`visible = false`，`unique_name_in_owner = true`），内含：`SectionTitle`（「按键绑定」）、`Description`（说明文案 + 「按 ESC 取消」）、`ScrollContainer`（`size_flags_vertical = 3`、`horizontal_scroll_mode = 0`）→ `BindingList`（`VBoxContainer`，`size_flags_horizontal = 3`，`unique_name_in_owner = true`）、`BindingFeedbackLabel`（`Label`，`autowrap_mode = 2`）、`ResetAllBindingsButton`（`Button`，文本「全部恢复默认」）。
    - `Center/Panel.custom_minimum_size` 由 `720×440` 改为 `760×560`。
    - `scene_save`。
11. `script_patch` 增量修改 `scripts/ui_scripts/UIOptionPanel.gd`：
    - 新增 `@onready` 引用、`KEY_BINDING_ROW_SCENE` 预载、`KEY_BINDING_MANAGER_PATH`。
    - `_ready()` 末尾追加：连接第三个分类按钮与「全部恢复默认」、连接 `KeyBindingManager` 的 `binding_changed` / `bindings_reset`（存在才连）、`_build_binding_rows()`。
    - 既有两个分类处理函数**只各加一行** `_key_binding_settings.hide()`；新增 `_on_key_binding_category_pressed()`。
    - 新增 `_build_binding_rows()` / `_refresh_binding_rows()` / `_on_row_rebind_requested()` / `_on_reset_all_bindings_pressed()` / `_set_feedback()` / `_exit_tree()`（断开服务信号）。
    - `refresh_from_settings()` 末尾追加 `_refresh_binding_rows()`。
12. `filesystem_manage(op="scan")`。

### 步骤 5：契约测试
13. `script_create("res://tests/godot/test_key_binding_settings_contract.gd")`，实现 `design.md` §8 的 7 个用例（`extends McpTestSuite`，`suite_name()` 返回 `key_binding_settings_contract`）。
14. `script_create("res://tests/test_key_binding_settings_contract.gd")`，内容为 4 行转发壳：
    ```gdscript
    @tool
    extends "res://tests/godot/test_key_binding_settings_contract.gd"

    ## MCP 测试入口转发到 tests/godot，保持项目现有测试发现路径。
    ```
15. `test_run(suite="key_binding_settings_contract", verbose=true)`，必须全绿。

### 步骤 6：运行期验证（编辑器 MCP）
16. `project_run(mode="main")` → `logs_read(source="game")` 无 `SCRIPT ERROR` / `Parse Error`。
17. `game_eval` 断言：
    - `InputMap.action_get_events("move_up")` 的键位等于项目默认（W）。
    - `get_node("/root/KeyBindingManager").rebind(&"move_up", 方向键上事件)` 返回 `ok=true`，且 `InputMap` 立即反映新键位。
    - `get_conflicting_actions()` 在故意制造重复时同时返回两个动作。
    - `reset_all_to_defaults()` 后 10 个动作回到默认键位。
18. `editor_screenshot(source="game")` 打开暂停菜单 → 参数设置 → 按键，确认 10 行、分组标题、红色冲突标记与滚动条外观。
19. 真实输入验证 AC2 / AC3：在面板里把 `move_up` 改成方向键上 → 回到游戏按「上」角色上移、按 W 不动；等待按键状态下按 ESC 不弹暂停菜单而是取消。
20. 持久化验证 AC5：改键 → `project_manage(op="stop")` → 重新 `project_run(mode="main")` → `game_eval` 断言键位仍为玩家设定值。
21. 损坏恢复验证 AC7：改坏 `user://settings.cfg` 的 `[input]` 段 → 重启 → 断言回退默认值、控制台有 `push_warning`、主菜单正常。
22. 登录菜单宿主验证：`project_run(mode="main")` 后从主菜单进入「游戏设置 → 按键」，确认同一个面板实例可用。
23. `project_manage(op="stop")`。
24. `test_run` 全量复跑，确认 `failed` 仍为 11 项且集合与基线一致。

### 步骤 7：文档与反馈
25. 更新 `docs/游戏机制与玩法内容.md`：新增「## 按键绑定设置」小节（记录 10 个动作的默认键位、存储位置、冲突规则、恢复默认行为），并在「局内暂停菜单」小节补充设置面板现在有三个分类的事实。
26. 追加写入 `临时反馈文档.md`：时间戳 + 学习反馈摘要 + Git 提交描述。
27. `git status` 核对，只保留本次任务需要的改动（编辑器可能改写 `project.godot` 的 autoload 路径为 `uid://`、重排 `.tscn` 的 ext_resource）。

## 3. 验证命令速查

| 目标 | 命令 |
|---|---|
| 刷新脚本 | `filesystem_manage(op="scan")` |
| 单套件 | `test_run(suite="key_binding_settings_contract", verbose=true)` |
| 全量回归 | `test_run()` |
| 跑游戏 | `project_run(mode="main")` |
| 运行期断言 | `game_eval(code=...)` |
| 运行日志 | `logs_read(source="game")` |
| 画面 | `editor_screenshot(source="game")` |
| 停止 | `project_manage(op="stop")` |

## 4. 风险点与回滚

| 高风险文件 | 风险 | 回滚点 |
|---|---|---|
| `project.godot` | 新增 autoload 行影响启动顺序 | 删掉该行即回到基线 |
| `scenes/ui_scenes/option_panel.tscn` | 同时被暂停菜单与登录菜单实例化，改坏会影响两处 | `git checkout -- scenes/ui_scenes/option_panel.tscn` |
| `scripts/ui_scripts/UIOptionPanel.gd` | 增量修改可能破坏既有分类切换 | `git checkout -- scripts/ui_scripts/UIOptionPanel.gd` |
| `scripts/map_scripts/UILargeMap.gd` | **不改动**；其既有失败是基线的一部分 | 不涉及 |

## 5. 提交前复核

- [x] `test_run` 全量：`failed` 集合与基线完全一致，新增套件全绿。
- [x] 运行日志无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
- [x] `project.godot` 的 `[input]` 段与 `open_map` 的物理 T 键未被改动。
- [x] `docs/游戏机制与玩法内容.md` 已同步。
- [x] `临时反馈文档.md` 已追加。
- [x] 回复中包含学习反馈摘要与分点 Git 提交描述。

## 6. 执行记录与偏差（2026-10-12）

### 6.1 与计划的偏差

| 计划 | 实际 | 原因 |
|---|---|---|
| 步骤 13 写 7 个用例 | 实际 **9 个用例 / 135 条断言** | 补了「行脚本必须用 `_input` 且调用 `set_input_as_handled`」与「损坏记录（含整条非字典）必须退化」两组断言 |
| 步骤 18 用 `editor_screenshot` 目视确认 | 改为**程序化核验布局**（`get_global_rect` / `size` / `is_visible_in_tree`） | 当前模型不支持读图；改用可断言的数值代替目视 |
| 步骤 19 用真实键盘验证 AC2/AC3 | 用 `Input.parse_input_event` 在游戏进程内派发真实事件 + **探针节点**验证消费 | 更精确：探针 `_unhandled_input` 在等待期间看不到 ESC、空闲时看得到，构成正反双向证明 |
| 步骤 23 只跑一次 `project_run` | 跑了 4 次（含 2 次为验证跨重启持久化与容错） | AC5 / AC7 必须跨进程验证 |
| `script_create`（MCP）创建脚本 | 改用本地 `write` 工具 + `filesystem_manage(op="scan")` | MCP `script_create` 两次触发会话断连（请求在途时 session disconnected），文件未创建 |

### 6.2 实施中发现并修复的真实缺陷（计划中未预见）

1. **`ConfigFile.get_value` 传 `null` 默认值会打印 C++ 错误。** 首次启动产生 5 条
   `Couldn't find the given section "input" and key "move_up", and no default was given.`
   修法：新增 `const MISSING_RECORD: Dictionary = {}` 作哨兵，`read_saved_event` 取回哨兵时静默返回 `null`。
   回归断言：假设置源记录 `last_default`，断言其非空。

2. **GDScript 的 `==` 在两侧类型不同时抛错，而不是返回 `false`。** 原实现 `if stored == MISSING_RECORD`
   在玩家手改配置把值写成字符串/整数时抛 `Invalid operands ... in operator '=='`，把「配置损坏」
   升级为**启动崩溃**。修法：改用 `typeof(stored) == TYPE_DICTIONARY and (stored as Dictionary).is_empty()`。
   回归断言：损坏记录集合扩展为 `[{"physical_keycode": "坏了"}, "完全不是字典", 12345]`。

3. **编辑器长会话的 GDScript 编译缓存不会被 `scan` 或 `CACHE_MODE_REPLACE` 刷新。**
   改完脚本重跑套件仍报**旧行号**的错误。有效手段是 `script_patch`（返回 `reloaded: true`）。
   已把测试内的 `preload` 改为 `setup()` + `ResourceLoader.load(..., CACHE_MODE_REPLACE)`，
   但仍需一次 `script_patch` 才能让编辑器同步磁盘版本。

### 6.3 最终验证数字

- 全量 `test_run`：`total=552, passed=502, failed=11, skipped=39`
  （基线 `total=543, passed=492, failed=11, skipped=40`；失败集合逐条同名同套件一致）。
- 单套件 `key_binding_settings_contract`：9/9 通过。
- 运行期 `game_eval`：AC1–AC7 全部实测通过，含跨重启持久化与 4 种损坏形态容错。
- 收尾 `settings.cfg` 已恢复默认，无 `[input]` 残留。

### 6.4 收尾遗留（需用户决定）

`resources/monster/anvil_cuihuotiewei.tres` 与 `resources/monster/tree_kumujing.tres` 被编辑器
文件系统扫描**自行加入了一条未被任何地方引用的 `ext_resource`（`loot_drop.gd`）**。这两处与本任务
无关（`grep` 确认文件内没有对应的 `ExtResource("...")` 使用点）。

**关键发现：编辑器每次扫描都会把它加回来。** 用户要求还原后我执行了一次 `git checkout`，两个文件
确实恢复了；但随后一次 `script_patch`（它会触发文件系统扫描）让两个文件在 `20:49:53` 被**再次改写**，
mtime 就是证据。因此还原必须放在**所有编辑器交互之后**作为最后一步，否则等于白做。最终已在全部
MCP 调用结束后还原，`git status` 中不再出现这两个文件。

## 7. 用户验收后的更正（2026-10-12 21:01）

### 7.1 `check` 的文案是错的

用户指出 `check`（Enter）不是「检查 / 当前版本未使用」，而是**开始界面的确认键**（W/S 选择、
Enter 确认，例如 Enter 进入主菜单「游戏仓库」）。

查证结论：用户描述的**行为属实**，我的**载体判断错误**。

| 事实 | 证据 |
|---|---|
| `check` 绑 Enter | `project.godot`：`physical_keycode: 4194309` |
| 但没有任何代码读 `check` | `rg` 全仓库 `.gd` / `.tscn` 无 `&"check"` 使用点 |
| 开始界面确认读的是内置 `ui_accept` | `core/ui/login_menu_controller.gd:83` |
| 有焦点时按钮会先消费 `ui_accept` | 按钮 `toggle_mode` + `_select_index(..., true)` 调 `grab_focus()`；第 83 行只是失焦回退 |
| 两者同时触发 | 内置 `ui_accept` 默认绑定本身就包含 Enter |

**处置（用户选择「只改文案，不动逻辑」）**
- `key_binding_registry.gd`：`check` 的 `display` 改「确认」，`note` 改「开始界面确认（Enter 由引擎内置绑定提供）」。
- 文档动作表补真实用途；「已知边界」写清 `ui_accept` 与 `check` 的关系及要真正接管需做的改动。
- 新增断言：任何条目的 `note` 不得包含「未使用」，每个条目必须有非空 `display`，`check` 的 `note` 非空。

### 7.2 改文案撑破了面板布局（本任务自查发现）

`Note` 原本没开自动换行，Label 最小宽度 = 整段文字宽度。318px 的说明把整行最小宽度顶到 **712px**
（可用 494px），面板被撑到 **925px** 高。运行期实测数据：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 面板尺寸 | `760 × 925` | `760 × 560` |
| 行最小宽度 / 可用宽度 | `712 / 494`（溢出） | `335 / 494` |
| `check` 行高 | `101px`（3 行） | `49px`（2 行） |
| 说明列宽 | `100px` | `160px` |

修法：`Note` 设 `autowrap_mode = 3`；`ActionName` 最小宽度 `170px` → `110px`（最长名称「向上移动」
约 64px，170 是当初给多了）。并加断言钉住 `autowrap_mode`。

### 7.3 更正后的验证数字

- `key_binding_settings_contract`：**9/9 通过**（动作集合用例断言数 22 → 43，行场景用例 12 → 15）。
- 全量 `test_run`：`total=552, passed=502, failed=11, skipped=39`，失败集合与基线逐条一致。
- 运行期实测：10 行显示名与键位文案全部正确，`check` 行说明显示为「开始界面确认（Enter 由引擎内置绑定提供）」，
  面板 `760 × 560` 且 `any_row_overflow = false`。
- 编辑器会话在更正期间掉线一次（`count=0`），重连为 `cusga@abf5a9ad313425ff` 后完成全部验证。


