# 执行计划：战斗中怪物详情面板

## 0. 前置

- [x] `session_manage(op="list")` 确认 CUSGA 会话可用；真实运行前游戏处于 stopped，启动后 `current_scene=res://scenes/battle_scenes/battle.tscn`。
- [x] `git status` 记录基线；编辑器会改写版本控制文件，收尾重新复核。

## 1. 怪物侧（先做数据源，后做 UI）

- [x] `entities/monster.gd`：
  - 新增 `MonsterDetailRequested(monster)` 信号、`_on_area_2d_input_event` 与 `input_event` 连接/断开。
  - 新增 `GetElementDisplayName(element)`，`_get_element_display_name` 改为委托。
- [x] `rg` 检查 `_get_element_display_name` / `input_event` / `MonsterDetailRequested` 未被意外重命名或重复定义。

## 2. 面板场景与脚本

- [x] 新建 `scenes/battle_scenes/monster_detail_panel.tscn`：
  - 根 `Control`（`FULL_RECT`、`mouse_filter=STOP`、`visible=false`、挂脚本）。
  - `Dimmer`（`ColorRect`，0.55 黑，`STOP`）、`Center`（`CenterContainer`，`IGNORE`）、`DetailPanel`（`PanelContainer`，主题 `Battle.tres`，`custom_minimum_size=(920,560)`）。
  - 左列 `InfoPanel`（`PanelContainer` + 独立 `StyleBoxFlat`，宽 280）：`NameLabel`、`ElementLabel`、`HpTitle`、`HpBar`(ProgressBar)、`HpValueLabel`、`HSeparator`、`AttrTitle`、`AttributeList`。
  - 右列：`Header`（`Label`"技能池" + `CloseButton`"关闭"）、`SkillScroll`（`ScrollContainer`，横向滚动关闭、纵向自动）、`SkillList`（`VBoxContainer`，横向填充）。
  - 所有动态引用节点 `unique_name_in_owner = true`。
- [x] 新建 `scripts/battle_scripts/monster_detail_panel.gd`：实现 `ShowMonster` / `ClosePanel` / `IsPanelOpen` / `BuildSnapshot`、`PanelOpened` / `PanelClosed`、`_input` 的 `Esc` 消费、`_process` 失效兜底、`_exit_tree` 清理。脚本加 `@tool`，否则 `test_run` 在编辑器内只能拿到占位实例。
- [x] `filesystem_manage(op="scan")`；通过真实运行启动战斗场景确认面板场景可加载、无解析错误。

## 3. 接进战斗

- [x] `battle.tscn` 增加 `MonsterDetailLayer`（`CanvasLayer`，默认 `layer = 1`）+ 面板实例 `MonsterDetailPanel`；保存场景。
- [x] `battle_manager.gd`：新增 `card_manager`、`monster_detail_panel` 引用；在 `_ready` / `_on_monsters_spawned` 连接怪物请求；实现 `_on_monster_detail_requested` / 打开与关闭协调；`_handle_combat_end` 关闭面板。
- [x] `card_manager.gd`：`_handle_drag_mode_input` 按下分支补 GUI 悬停守卫（仅按下分支）。
- [x] `rg` 确认 `MonsterDetailLayer/MonsterDetailPanel` 路径与场景一致。

## 4. 测试

- [x] 新增 `tests/godot/test_battle_monster_detail_panel_contract.gd`（`@tool extends McpTestSuite`，`suite_name() = "battle_monster_detail_panel_contract"`）：
  - 技能预览顺序/隐藏/描述回退；
  - 空数据占位；
  - 单实例切换、`PanelOpened`/`PanelClosed` 次数、信号断开；
  - 怪物释放后自动关闭；
  - `Esc` 消费与 `viewport.is_input_handled()`；
  - `battle.tscn` 层级与唯一实例装配断言。
- [x] 顶层发现层 `tests/test_battle_monster_detail_panel_contract.gd` 只做 `extends` 转发（runner 只扫描 `res://tests/` 顶层）。
- [x] `test_run(suite="battle_monster_detail_panel_contract")` 通过：**8 / 8**。
- [x] 回归：`monster_contract` 11/12、`monster_data_contract` 5/7、`click_mode_target_contract` 9/9、`pause_menu_contract` 12/12、`health_bar_ui_contract` 1/1、`combat_skill_contract` 11/14、`battle_time_link_contract` 8/8、`vital_component_contract` 6/7、`attribute_component_contract` 10/19、`monster_drop_pool` 6/6、`time_panel_ui_contract` 1/1、`day_night_filter_contract` 8/8，均 `failed=0`（`passed + failed < total` 为 skip）。计划里的 `target_selection_visual_tests` 不存在，改用 `click_mode_target_contract`。
- [x] `world_interaction_coordinator_contract` 6/10、`failed=3`，失败项与本任务无关（该脚本未被本任务改动），属既有失败。

## 5. 真实运行验证

- [x] `project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")`，`game_status.status="live"`、`current_run_errors=[]`、`recent_errors=[]`。
- [x] 当前 MCP 版本没有 `game_eval`，改用 `game_manage(op="input_mouse"/"input_key")` 发送真实输入；`input_mouse` 的位置是窗口像素，需按窗口/视口比例换算（本机 `2512×1413` 窗口对应 `1280×720` 视口，比例 `1.9625`）。
- [x] 右键点击第一只怪物（视口 `240,150`）→ 面板可见，名称“黄沙岩隐兽”、五行“土”、生命 `1000 / 1000`、五项属性 `150/110/80/80/95`，技能“测试卡2”及描述正确。
- [x] 面板打开时再次右键其他怪物 → 目标保持“游荡盗匪”，数据不切换；点击面板覆盖区不改变怪物 `scale`，没有穿透到 `Area2D`。
- [x] `Esc` 关闭 → `visible=false`；`tree_paused=false`，`process_frames` 从 `200435` 推进到 `200993`，战斗未暂停。
- [x] 切换目标：关闭后右键第二只 → “游荡盗匪”，4 个技能与 3 条技能间分割线；第三只 → “枯木精”，4 个技能、3 条分割线，技能列表 11 个子节点（4×2 + 3），滚动区高 `444px`，长描述自动换行。
- [x] 关闭按钮点击 → 面板关闭；点击面板外的遮罩 → 面板关闭。
- [ ] 对怪物 `Health.TakeDamage` 做真实运行刷新：当前 MCP 没有运行时求值入口，无法在面板打开时主动扣血；实时刷新已由契约测试用真实 `ValueChanged` 信号路径覆盖。
- [x] `editor_screenshot(source="game")` 检查布局；`logs_read(source="game")` 与 `source="editor"` 均为 0 条错误。
- [x] `project_manage(op="stop")`，只停止游戏，未关闭编辑器。

## 6. 文档与收尾

- [x] `docs/游戏机制与玩法内容.md`：在“目标选择视觉反馈”之后新增“战斗中查看怪物详情”一节（触发、层级、只读规则、不暂停、Esc 与关闭、技能池来源）。
- [x] `.trellis/spec/frontend/component-guidelines.md`：补充“战斗内只读模态面板”的可执行契约（宿主层级、输入消费、单实例绑定、失效兜底）。
- [x] `.trellis/spec/frontend/directory-structure.md`：修正测试目录说明——`test_run` 只扫描 `tests/` 顶层，`tests/godot/` 的测试真身需要顶层 shim 转发。
- [x] `git status` / `git diff --stat` 复核，只保留本任务改动；按改动分组写提交说明。
- [ ] `task.py archive`：等分支与提交信息确认后再执行。

## 回滚点

- 第 1 步后：仅 `monster.gd` 新增信号与方法，可整体还原。
- 第 2 步后：两个新文件可整体删除。
- 第 3 步后：`battle.tscn`/`battle_manager.gd`/`card_manager.gd` 各自独立的小改动，按文件还原。
- 任一步出现阻塞级 `SCRIPT ERROR`：回退该步改动，重新 `filesystem_manage(op="scan")` 后复跑测试。

## 验证命令

```
python .trellis/scripts/get_context.py --mode phase --step 2.1
# Godot MCP（通过本地 MCP 客户端脚本调用）
session_manage {"op":"list"}
filesystem_manage {"op":"scan"}
test_run {"suite":"battle_monster_detail_panel_contract","verbose":true}
project_run {"mode":"custom","scene":"res://scenes/battle_scenes/battle.tscn"}
game_manage {"op":"input_mouse","params":{"event":"button","position":{"x":471,"y":294},"button":"right","pressed":true}}
logs_read {"source":"game"}
project_manage {"op":"stop"}
```
