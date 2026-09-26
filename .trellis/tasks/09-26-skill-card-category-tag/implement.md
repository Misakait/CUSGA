# 执行计划：技能卡类别标签与分类贴图

对应 `prd.md`（R1–R6）与 `design.md`（第 1–7 节）。所有验证走已打开的 Godot 4.7.1 编辑器 MCP（`addons/godot_ai`），不使用命令行 Godot。

> 状态：**已完成**。执行期的方案偏差与踩坑见文末「执行记录」。

## 0. 前置检查（未通过则先停下）

- [x] `session_manage(op="list")` / `editor_state` 确认编辑器已打开且加载 CUSGA 项目。
      **实际**：MCP 同时连着两个编辑器，默认激活的是另一个项目 `hsr-kill`（正在运行游戏），其报错与项目结构均与本次无关。必须显式 `session_activate` 到 CUSGA 会话后才能验证。期间编辑器重载重连过一次，会话 id 变为 `cusga@ec3a4ad0f3a94952`。
- [x] `git status` 记录改动前基线（2 个与本次无关的未提交改动：`items/environment/campfire.tres`、`scenes/battle_scenes/battle.tscn`，全程未覆盖）。
- [x] 记录基线测试结果：`test_run(suite="item_chain_boundary_contract")` = **9/9 全绿**。

## 1. 数据契约：新增类别字段（R1）

- [x] `script_patch` 在 `resources/item/card/skill_card_data.gd` 的 `CardTags` 声明后追加四个类别常量与 `CardCategory` 导出字段。
- [x] `filesystem_manage(op="scan")` 刷新，`script_patch` 诊断为空（无 `Parse Error` / `SCRIPT ERROR`）。
- [x] **降级判定点：未触发** —— `@export_enum` 实测在 4.7.1 可用，保持首选方案。
- [x] 既有三段声明原文与顺序未变（`Skill:9` / `cost:12` / `CardTags:15`，新字段在 `:36`）。

## 2. 资源回填：69 张技能卡（R3）

- [x] 一次性 Python 改写脚本放系统临时目录（**未进仓库**，收尾已删除）。
- [x] 运行前把 `resources/skill_cards` 全量备份到临时目录（**未进仓库**，收尾已删除）。
- [x] 核对 diff：`69 files changed, 69 insertions(+), 0 deletions(-)`，且逐文件检查 `non_one_line_diffs=0`。
- [x] 抽查 `bmob.tres` / `test_card_2.tres` 确认插入位置在 `CardTags` 行之后、其余行未被触碰；`Select-String` 统计 `^CardCategory = 1$` = **69 行**。
- [x] `scan` 后在真实游戏进程内读回类别（见第 5 节 `game_eval`）。

> 回滚点 A：**被触发过一次**。首次回填因换行符二次转换把文件内容改坏（diff 膨胀到 714/645），已按要求整体回滚后重做，最终形态达标。详见「执行记录」第 3 项。

## 3. 视图：按类别切换卡面贴图（R4）

- [x] `script_patch` 在 `scripts/card_scripts/skill_card.gd` 增加四个贴图常量与 `_resolve_card_frame()` 映射函数。
- [x] `init_card_data()` 末尾设置 `$Sprite2D.texture`；未分类与未知值统一走兜底贴图。
- [x] `scan` + 测试运行确认无解析错误。
- [x] `SkillCard.tscn` **零改动**（`git status` 中不存在该文件）。

## 4. 契约同步与新增测试（R5）

- [x] `tests/godot/test_item_chain_boundary_contract.gd`：`ITEM_CLASS_ROWS` 追加 `CardCategory`；`GD_EXPORT_SNIPPETS` 追加与脚本完全一致的逐字声明片段。
- [x] 新建 `tests/godot/test_skill_card_category_contract.gd`（6 个测试）**以及** `tests/test_skill_card_category_contract.gd` 顶层壳文件 —— 缺壳文件会导致套件注册不上（见 `design.md` 5.3）。
- [x] 未新建任何 `.cs` 文件（`SkillCardData.cs` 已删除，C# 对照断言自动跳过）。

## 5. 验证（必做，顺序执行）

| 目的 | 命令 | 结果 |
|---|---|---|
| 刷新脚本与资源 | `filesystem_manage(op="scan")` | 完成 |
| 字段奇偶与登记表 | `test_run(suite="item_chain_boundary_contract")` | **9/9 通过** |
| 新增类别契约 | `test_run(suite="skill_card_category_contract")` | **6/6 通过**（38 条断言） |
| 卡面 / 物品链回归 | `test_run(suite="gameplay_port_contract")` | **4/4 通过** |
| 手牌缓存回归 | `test_run(suite="player_hand_cache_contract")` | **3/3 通过** |
| 开局抽卡回归 | `test_run(suite="run_start_skill_card_contract")` | **20/20 通过** |
| 采集回归 | `test_run(suite="reusable_gathering")` | 57 通过 / **1 既有失败**（见下） |
| 战斗场景冒烟 | `project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")` → `logs_read(source="game")` → `editor_screenshot(source="game")` → `project_manage(op="stop")` | 无 `SCRIPT ERROR` / `Parse Error` |
| 卡面换色实证 | `game_eval`：0 / 1 / 2 / 3 / 99 五例 | 全部命中预期贴图 |
| 真实手牌实证 | `game_eval` 遍历战斗场景中的 `SkillCard` | 3 张攻击牌为红模板、1 张未分类卡为通用模板 |
| 主场景冒烟 | `project_run(mode="main")` → `logs_read(source="game")` → `project_manage(op="stop")` | 日志干净 |

- [x] 阻塞判定：本次改动未引入 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` / 资源加载错误，相关套件全绿。
- [x] 测试结束后只 `project_manage(op="stop")`，**未关闭 Godot 编辑器**。

### 既有失败（非本次引入，未处理）

`test_run(suite="reusable_gathering")` 的 `test_production_plain_item_assets_use_gdscript_item_data`：
断言「普通生产物品资产数量必须保持为 103」，而 `res://items` 下引用 `item_data.gd` 的 `.tres` 实测为 **102** 个。

判定为非本次引入的依据：

1. 收集范围是 `res://items`（`test_reusable_gathering_interaction.gd:1220` 递归扫描），与本次改动面（`resources/item/card/`、`resources/skill_cards/`、`scripts/card_scripts/`、`tests/`）完全不相交；
2. `git status` 中 `items/` 下只有用户自己的 `campfire.tres`，本次未触碰任何 `items/` 文件；
3. 分别在 `battle.tscn` 与 `main_menu.tscn` 两种编辑场景下重跑，失败完全一致，排除工具提示的场景幻影失败。

旁边另有一条既有加载错误：`tests/test_item_room_content.gd` 解析失败（`Function "get_tree()" not found in base self`），同样早于本次改动。两者都属于用户进行中的物品迁移工作，按要求不扩大改动面。

## 6. 收尾

- [x] 重新 `git status` 复核：本次改动 = `resources/item/card/skill_card_data.gd`、`scripts/card_scripts/skill_card.gd`、69 个 `resources/skill_cards/*.tres`、`tests/godot/test_item_chain_boundary_contract.gd`、2 个新增测试文件（含其 `.uid`，仓库跟踪 `.uid`）；`card_table/` **无改动**。
- [x] 用户既有的两个改动保持原样（内容分别是 Godot 保存时附加的 `metadata/_custom_type_script` 与 `unique_id`，与本次无关）。
- [x] 临时回填脚本与临时备份目录已删除，且从未落在仓库内。

## 风险文件与回滚点

| 文件 | 风险 | 回滚 |
|---|---|---|
| `resources/skill_cards/*.tres`（69） | 文本批量改写 | 回滚点 A（**已实际用过一次**）或 `git checkout -- resources/skill_cards` |
| `resources/item/card/skill_card_data.gd` | 破坏既有字段契约 | `git checkout --` 单文件 |
| `scripts/card_scripts/skill_card.gd` | 卡面贴图缺失导致空白卡 | `git checkout --` 单文件 |
| `tests/godot/test_item_chain_boundary_contract.gd` | 登记表与脚本文本不一致 | `git checkout --` 单文件 |

## 执行记录（实现期偏差与踩坑）

| # | 现象 | 根因 | 处置 |
|---|---|---|---|
| 1 | `script_patch` 返回 `GDScript reload failed (error code 43)` 却没有具体消息 | 诊断走了 fallback 分支 | 用 `script_manage(op="find_symbols")` 交叉验证脚本能否真正解析，再触发一次 patch 以取得 log_capture 级诊断 |
| 2 | 卡面脚本写 `CARD_DATA_SCRIPT.CARD_CATEGORY_ATTACK` 报 `isn't a constant expression` | GDScript 常量初始化器只接受常量表达式，跨脚本常量不算 | 改为镜像常量 `CATEGORY_*`，并由新契约套件断言两侧数值恒等（与 `scripts/shop/shop_control.gd` 的 `FAILURE_*` 同法） |
| 3 | 首次回填后 diff 膨胀为 714 insertions / 645 deletions | 在含 `\r\n` 的文本上做 `replace("\n", "\r\n")`，把既有 `\r\n` 二次转换成 `\r\r\n`；`core.autocrlf=true` 掩盖了工作区 LF/CRLF 混合的事实 | `git checkout -- resources/skill_cards` 整体回滚；改写脚本改为「先探测并规范化成 `\n` → 插入 → 按该文件原始换行符还原」（回滚点 A） |
| 4 | `test_run` 报 `No suite named 'skill_card_category_contract' is registered (52 discovered)` | discovery 只列 `res://tests` 的直接子项、不递归，`tests/godot/` 靠顶层壳被发现；`editor_reload_plugin` 不刷新该缓存 | 按项目惯例在 `tests/` 顶层补壳文件 `@tool` + `extends "res://tests/godot/..."`，再 `scan` |
| 5 | 套件本身 `reload=Parse error` | `SkillCard.get_script_constant_map()` 不能通过类名调用（`get_script_constant_map()` 是 Script 实例方法） | 改用套件内的 `_constants_of()`（先 `load()` 成 Script 实例再取常量表） |
| 6 | 计划中的「实例化 `SkillCard.tscn` 断言 `$Sprite2D.texture`」无法实现 | 非 `@tool` 的 Node2D 脚本在编辑器里只能得到占位实例、方法不可调用 | 套件改为源码形状断言；真实贴图断言移到冒烟阶段的 `game_eval`（`design.md` 5.3） |
| 7 | `test_run(suite="player_hand_lifecycle")` 报套件名不存在 | 该文件是 `extends SceneTree` 的独立运行脚本，不注册为 `McpTestSuite` | 改跑注册名 `player_hand_cache_contract` |
| 8 | `Session cusga@... disconnected while request was in flight`，一次写入未落盘 | 编辑器重载导致插件重连、会话 id 变更 | 重新 `session_activate` 到新会话 id，并用 `Test-Path` 确认后重做该次写入 |

## `task.py start` 前检查

- [x] `prd.md` 无阻塞开放问题，验收标准可观测。
- [x] `design.md`、`implement.md` 已就绪（复杂任务三件套齐全）。
- [x] 用户已明确批准最新一版规划摘要。
