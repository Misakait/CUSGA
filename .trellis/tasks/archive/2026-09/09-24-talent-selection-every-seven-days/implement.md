# 执行计划：天赋选择每七天弹出与十张测试天赋卡

技术设计见同目录 `design.md`，需求与验收见 `prd.md`。本文件只记录**怎么做、按什么顺序做、每步怎么验证、出错怎么退**。

## 前置条件

- Godot 编辑器必须处于打开状态并加载 CUSGA 工程。已验证：会话 `cusga@5fea6c0f9f459e02`，Godot 4.7.1-stable，`readiness: ready`。
- 不要使用 `godot-mono` 命令行（AGENTS.md 已声明本机 4.6.3 CLI 与工程 4.7.1 冲突）。
- 每次编辑器操作后跑 `git status`，确认没有把 Tab 缩进之类的连带改动混进提交。

## 阶段 P1：修缺陷 + 造资源

这两项互不依赖，且都能在**不动界面**的前提下独立验证，所以放在最前面 —— 界面出问题时可以先排除资源层。

### P1.1 修 `attribute_talent_effect.gd` 的组件解析

- **文件**：`resources/talents/attribute_talent_effect.gd`（约 51-60 行）
- **改法**：先 `target_player.get("Attributes")`，再兜底 `get_node_or_null("Components/AttributeComponent")`，都拿不到时 `push_warning` 后返回。理由与风险见 `design.md` 第 5 节。
- **风险等级**：低。这是本次唯一的「修 bug」改动，影响面限于属性类天赋。
- **验证**：`test_run(suite="player")` 确认 `test_player_contract.gd` 仍全绿（该套件里的天赋用例应走 `skip`，因为 C# 源已退役）。
- **回滚点**：单文件、单函数，`git checkout` 即退。

### P1.2 新增 10 个天赋卡资源

- **目录**：`resources/talents/`（与 `CardPoolDirectory` 默认值一致）
- **文件清单与字段值**：见 `design.md` 第 7 节的表格，逐行照填。
- **序列化形状**：照抄 `resources/skill_cards/fire_phys_huoji.tres` 的结构 —— 根 `script` = `talent_data.gd`（uid `uid://bb22vtin03ntv`），`Effects = Array[Resource]([SubResource("...")])`，子资源 `script` = `attribute_talent_effect.gd`（uid `uid://bopo8uyh7ijeo`）。
- **注意**：`TalentName` / `Description` 是中文，写文件必须保证 UTF-8；不要用 PowerShell 的 `Set-Content` 默认编码写这些文件。
- **验证**：
  1. `filesystem_manage(op="scan")` 让编辑器登记新资源。
  2. `resource_manage(op="load")` 逐个读回，确认 `TalentName` / `Description` / `TalentTexture` 非空，且 `Effects` 有 1 条。
  3. `filesystem_manage(op="search", type="Resource", path="res://resources/talents")` 确认 `.tres` 恰好 10 个。
- **回滚点**：删目录下的 10 个 `.tres` 与对应 `.uid`。

## 阶段 P2：界面与选择逻辑

P2 的四步必须**成组提交**：改动 `talent_screen.tscn` 的节点结构会让 P2.4 之前的契约断言失败，中途停下来会留下一个红着的测试套件。

### P2.1 `talent_manager.gd`：池装配 + 暂停归还 + 浮窗注入

- **文件**：`resources/talents/talent_manager.gd`
- **三处改动**：
  1. 新增 `@export var CardPoolDirectory: String = "res://resources/talents"` 与 `@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")`；`_ready()` 里用「目录枚举（排序）+ `AllTalentsPool` 去重追加」装配 `_available_talents`。递归扫描写法照抄 `core/gameflow/run_start_skill_card_draft.gd:_collect_card_resources`。
  2. 新增 `_was_paused_before_open`，打开前记录、`OnTalentSelected` 里归还（替换现在的无条件 `paused = false`）。
  3. `_draw_three_talents()` 里对每张新卡调用 `SetTooltipPanel(_tooltip_panel)`。
- **保持不动**：`AllTalentsPool` 默认空数组、`CardScenePrefab` 导出、`OnTalentSelected(selected_talent)` 签名、`OnCardClicked` 连接方式、Fisher-Yates 洗牌写法、选后 `erase` 语义。
- **风险等级**：中。这是本次改动最集中的文件，且它的契约断言最多。
- **回滚点**：单文件。

### P2.2 `talent_card.gd`：共享视觉常量 + 悬停浮窗

- **文件**：`resources/talents/talent_card.gd`
- **改法**：
  - 顶部 `const CARD_VISUALS := preload("res://core/card_visual_config.gd")`。
  - `_on_hover_enter` / `_on_hover_exit` 的缩放值与时长改用 `CARD_VISUALS.CARD_HOVER_SCALE` / `CARD_NORMAL_SCALE` / `SCALE_TWEEN_DURATION`；`z_index` 改用 `CARD_Z_INDEX_HOVER` / `CARD_Z_INDEX_NORMAL`。
  - 新增 `SetTooltipPanel(panel: Node)` 与内部 `_tooltip_panel`；悬停进入时 `show_tooltip(TalentName, Description)`，离开时 `hide_tooltip()`，全部用 `has_method` 守卫。
- **保持不动**：`Initialize(data)` 签名、`OnCardClicked(data)` 信号、`pivot_offset` 的底部中心算法、`_ready()` 里的三个 `_clickArea` 连接。
- **风险等级**：低。
- **回滚点**：单文件。

### P2.3 `talent_screen.tscn`：补界面框架

- **文件**：`scenes/talents/talent_screen.tscn`
- **目标结构**：见 `design.md` 第 6.1 节（`Overlay` + `Content/TitleLabel` + `Content/CardsContainer` + `Content/HintLabel`，无确认按钮）。
- **必须同步**：根节点的 `CardsContainer` 导出改为 `NodePath("Content/CardsContainer")`；`process_mode = 3`、`CardScenePrefab`、`AllTalentsPool = Array[Resource]([])` 全部保持。
- **风险等级**：中（结构变了，契约断言跟着变）。
- **回滚点**：单文件。

### P2.4 更新契约断言

- **文件**：`tests/godot/test_inventory_component_contract.gd`（`test_talent_manager_production_scene_contract`，约 1587、1597 行）
- **改法**：`screen.get_node("HBoxContainer")` → `screen.get_node("Content/CardsContainer")`；错误文案同步更新。**只改路径，不删断言**；顺带新增对 `Overlay` 与 `TitleLabel` 存在性的断言（净增防护）。
- **不要动**：同一用例里的 `AllTalentsPool` 为空、`CardScenePrefab` 路径、`OnTalentSelected` 存在、`process_mode == ALWAYS` 四条断言，以及 `test_talent_card_serialized_node_contract` 全部内容。
- **风险等级**：高敏感（改测试），必须在提交信息里说明理由。

### P2 验证

```
test_run(suite="inventory")      # 覆盖 test_inventory_component_contract.gd
test_run(suite="player")         # 覆盖 test_player_contract.gd
```

两条都要全绿。重点确认 `test_talent_card_serialized_node_contract`、`test_talent_resource_schema_contract`、`test_talent_manager_production_scene_contract` 三条天赋用例通过。

## 阶段 P3：挂载与运行验证

### P3.1 `Main.tscn` 挂载天赋界面

- **文件**：`scenes/Main.tscn`
- **改法**：新增 `ext_resource` 指向 `res://scenes/talents/talent_screen.tscn`，并在 `UI/HUDLayer/HUDRoot` 下、紧随 `SkillCardDraftScreen`（第 245-248 行）之后加一个实例节点，命名 `TalentScreen`，`layout_mode = 1`。
- **为什么放 `HUDRoot` 下**：`TooltipPanelPath` 的默认值 `../TooltipPanel` 依赖这个层级；`TooltipPanel` 与 `SkillCardDraftScreen` 都在这里。
- **风险等级**：低，但**层级写错会让界面永远不弹**，所以必须靠 P3.2 的运行验证兜住。
- **回滚点**：单文件。

### P3.2 运行验证（必做，不能只靠契约测试）

自然玩法到达第 7 天需要 1200 时间点（6 天 × 200 点 ≈ 120 次地图移动），**必须**用调试入口推进时间：

1. `project_run(mode="custom", scene="res://scenes/Main.tscn")`
   - **不是 `mode="main"`**：`run/main_scene` 指向主菜单 `scenes/main_menu_scenes/main_menu.tscn`（`README.md:92`），`mode="main"` 起的主菜单里没有 `/root/Main`，后续 `game_eval` 会以 `Node not found` 失败。
   - 注意 `game_eval` 抛出的运行时错误会让游戏停在 debugger 断点（`game_status.status == "break"`），此后 eval 一律返回 `EVAL_GAME_NOT_READY`，必须先 `project_manage(op="stop")` 再重启。因此断言要尽量在一次 eval 里做完。
2. `editor_state` 轮询到 `game_capture_ready`
3. 开局会停在技能卡抽取界面（`draft_visible=true`、`paused=true`），先 `draft.hide()` + `get_tree().paused = false` 让它退场，否则天赋界面会与它叠加
4. 用 `game_eval` 调 `/root/TimeSystem` 的 `PassTime(1200)` 推进到第 7 天（`_current_day % 7 == 0` 才发信号；6 次天数递增 × 200 时间点）
5. `game_eval` 读 `visible` / `paused` / `Content/CardsContainer` 子节点数确认弹出
   - 取卡片时**必须过滤 `is_queued_for_deletion()`**：`_draw_three_talents` 先 `queue_free()` 旧卡再 `add_child` 新卡，同一帧内 `get_child(0)` 拿到的是待删除的旧卡
6. 悬停后**要等过 `hover_delay`（0.8 秒）**才能读到 `TooltipPanel.visible == true`：`show_tooltip` 只挂起请求，真正的 `show()` 由 `_process` 在延迟到点后执行（`TooltipPanel.tscn` 已设 `process_mode = 3`，暂停时照常推进，所以不是暂停导致的失效）
7. 点击一张卡 → 读 `Components/AttributeComponent` 的 `GetEffectiveValue(属性枚举)`，确认数值真的变了（AC4 的关键，也是 P1.1 修复是否生效的判据）
8. `project_manage(op="stop")`

再跑一次到第 14 天（`PassTime(1400)`），确认第二次弹出且已学过的卡不在池中（AC5）。

实测结论：以上全部通过，含 PhysDef `100 → 105`、池 `10 → 9`、第 14 天抽出的 3 张不含已学卡。

### P3.3 编译确认（已作废）

原计划的 `env CI=true dotnet build CUSGA.sln --no-restore` **不适用**：当前检出中 C# 已完全退役，`**/*.cs`、`**/*.csproj`、`**/*.sln` 均为 0 个匹配，该命令直接报 `MSB1009: 项目文件不存在`。无 C# 产物需要编译，`AC9` 相应作废。

## task.py start 前的检查清单

- [ ] `prd.md` 无遗留的未决问题（Q1 已由用户确认：未选中回池、学过的移除）
- [ ] `design.md` 与本文件都存在
- [ ] 用户已对最终规划摘要给出明确批准
- [ ] 编辑器会话仍在线

## 需要注意的坑

| 坑 | 规避方式 |
|---|---|
| 编辑器保存会重排 `.cs` 缩进并改写 `CUSGA.csproj` 的 SDK 版本 | 每阶段结束跑 `git status`，回收无关改动 |
| 手写 `.tres` 时中文被写成非 UTF-8 | 用文件工具写，不用 shell 重定向 |
| `.tres` 的 `ext_resource` 漏 uid 导致编辑器反复重写 | 脚本 uid 照 `design.md` 第 7 节给出的固定值填 |
| 契约测试在 P2.3 与 P2.4 之间必然失败 | P2 四步成组完成后再跑测试 |
| 直接改 `_current_day` 会跳过信号 | 推进时间一律走 `PassTime` |
| `talent_screen.tscn` 挂在 `HUDRoot` 之外的层级会让 `../TooltipPanel` 解析失败 | 挂载点固定在 `UI/HUDLayer/HUDRoot` 下 |
