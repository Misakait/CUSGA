# 技能卡类别标签与分类贴图

## Goal

为玩家技能卡资源（`SkillCardData`）新增一个 `@export` 类别标签，把卡牌划分为**攻击牌 / 防御牌 / 状态牌**三类，按类别在卡面切换红 / 绿 / 蓝技能卡模板贴图，使玩家能一眼从卡面颜色读出卡牌定位。

## Background（已确认事实，均来自仓库证据）

### 卡牌数据链

- 玩家技能卡资源共 **69 个**，位于 `resources/skill_cards/*.tres`，全部绑定 `res://resources/item/card/skill_card_data.gd`；该脚本的 `Skill` 字段指向实际战斗技能 `resources/combat_skills/*.tres`。
- 卡牌包装层 `resources/item/card/skill_card_data.gd:9-15` 当前导出字段只有 `Skill`、`cost`、`CardTags`；`Skill` / `cost` 在文件中先声明，`CardTags` 最后声明。
- 战斗技能 `core/combat/skills/combat_skill_data.gd:41-47` 持有 `Effects: Array[Resource]`，效果子类位于 `core/combat/effects/`：
  - `damage_effect.gd:29-47`：`BaseDamage`（默认 10）、`HitCount`（默认 1）、`PrimaryDamageMultiplier`（默认 1.0）→ 伤害量算作 `BaseDamage × HitCount`。
  - `apply_shield_card_effect.gd:10`：`ShieldStatus` → `core/combat/buffs/shield_status_data.gd` 的 `DefaultShieldAmount` → 护盾量。
  - `apply_status_card_effect.gd` / `modify_attribute_effect.gd`：施加状态或属性修正，无直接伤害、无护盾数值。
- 现有 69 张卡的效果构成（脚本化扫描 `resources/skill_cards` + `resources/combat_skills` 得出）：
  - **68 张纯伤害卡**（含 `bmob`、`test_card_1` 这类"伤害 + 附带状态"的卡，按本规则仍归攻击）。
  - **1 张攻防混合卡** `test_card_2`：伤害 20、护盾 20，数值相等。
  - **0 张纯防御卡、0 张纯状态卡。**

### 卡面显示链

- `scenes/skill_card_scenes/SkillCard.tscn:14-16` 的 `Sprite2D` 当前硬编码底板贴图 `res://res/skillcard/技能卡模板2.png`，`scale = (1.5, 1.5)`。
- 卡面数据由 `scripts/card_scripts/skill_card.gd:64-76` 的 `init_card_data()` 填充（名称/元素/描述/标签/费用）。
- `init_card_data()` 的三个调用点，即需要覆盖的全部界面：战斗手牌 `scripts/card_scripts/player_hand.gd:82`、开局技能卡抽取 `core/gameflow/run_start_skill_card_draft.gd:458`（场景 `scenes/ui_scenes/skill_card_draft_screen.tscn:4`）、以及复用同一卡面场景的其它实例化点。
- 目标贴图由上一次提交 `e3d6791` 提供：`res/Card/skillcardboard/技能卡模板-红.png`、`-绿.png`、`-蓝.png`。三张图与在用的 `技能卡模板2.png` **尺寸完全一致（140×100）**，可直接替换 `texture`，无需调整 `scale` 或偏移。（同批还有粉/紫/橙，本次不使用。）

### 受影响的既有契约与工具

- `tests/godot/test_item_chain_boundary_contract.gd:22` + `:34` + `:299-313` 会**逐字断言** `skill_card_data.gd` 的 `@export` 字段名与顺序等于 `["Skill", "cost", "CardTags"]`（`assert_eq(gd_names, row[3])`）。新增导出字段必然使该断言失败，必须在同一改动内更新登记表，否则属于本次改动引入的回归。
- `tests/godot/test_item_chain_boundary_contract.gd:31-40` 还断言 `skill_card_data.gd` 必须保留 `@export var Skill: Resource`、`@export var cost: int = 10`、`@export var CardTags: Array[String] = []` 三段声明原文。
- C# 垫片 `resources/item/card/SkillCardData.cs` **已物理删除**（`Test-Path` 返回 False），`tests/godot/csharp_optional.gd` 会让 C# 对照断言自动跳过，因此本次只需处理 GDScript 侧。
- 现有 69 张 `.tres` 由 Python 同步脚本生成，文件内显式写出了等于默认值的行（如 `cost = 10`）。Godot 保存资源时会省略等于默认值的属性行，这一点决定了类别默认值的取值（见 R1）。
- `tests/godot/test_gameplay_port_contract.gd:251` 对技能卡 `.tres` 做的是"必须包含这些字段标记"的包含式断言（`Skill = ExtResource(`、`cost =`、`CardTags =` 等），新增字段不会使其失败。
- 卡牌表格链路 `card_table/export_current_cards.py` 的 `upsert_existing_skill_card()`（`:1690-1754`）逐字段替换，不重写整份文件，因此表格同步不会抹掉 `.tres` 中的类别行。

## Requirements

### R1 类别字段（`CardCategory`）

在 `resources/item/card/skill_card_data.gd` 新增类别字段，声明**追加在 `CardTags` 之后**，既有声明与顺序不得改动：

- 字段名 `CardCategory`，类型 `int`，使用 `@export_enum` 提供 Inspector 中文下拉，取值与顺序为 `未分类(0) / 攻击(1) / 防御(2) / 状态(3)`。
- **默认值 = 未分类（0）**。理由：Godot 保存资源会省略等于默认值的属性行，若默认值为"攻击"，则 69 张卡显式写入的攻击值会在任何一次 Inspector 保存后消失；把默认值设为未分类后，"显式填写的三分类值"才能持久留在 `.tres` 里，也让未配置的新卡不会静默退化成攻击牌。
- 同时声明与上述取值一一对应的具名常量，供脚本与测试引用，避免裸数字。

### R2 类别判定规则（用于回填现有卡）

- 造成伤害的卡 → **攻击牌**。
- 抵御伤害或获得护盾的卡 → **防御牌**。
- 同时具备伤害与护盾的卡 → 比较两者数值大小决定类别；**数值相等时归攻击牌**。
- 既无伤害也无防御、只施加状态的卡 → **状态牌**。
- 数值口径：伤害取该卡 `DamageEffect.BaseDamage × HitCount` 之和；护盾取 `ApplyShieldCardEffect.ShieldStatus.DefaultShieldAmount` 之和。

### R3 回填现有 69 张卡

按 R2 判定并把结果**显式**写入每张 `resources/skill_cards/*.tres` 的 `[resource]` 块（不依赖默认值），使资源自带类别。当前判定结果为 69 张全部为攻击牌（`CardCategory = 1`），其中包含按平局规则归攻击的 `test_card_2`。

### R4 卡面按类别换贴图

`scripts/card_scripts/skill_card.gd` 在 `init_card_data()` 中按卡牌类别设置卡面底板贴图：

- 攻击 → `res://res/Card/skillcardboard/技能卡模板-红.png`
- 防御 → `res://res/Card/skillcardboard/技能卡模板-绿.png`
- 状态 → `res://res/Card/skillcardboard/技能卡模板-蓝.png`
- 未分类（含缺少类别字段的旧资源）→ 回退到现有 `res://res/skillcard/技能卡模板2.png`，不误显示为某一类。

映射取自 `CardCategory` 字段；由于三个调用点都经由 `init_card_data()`（`player_hand.gd:82`、`run_start_skill_card_draft.gd:458`），战斗手牌、玩家手牌与开局抽卡三处表现一致。

### R5 契约同步与新增契约

- 更新 `tests/godot/test_item_chain_boundary_contract.gd` 的 `ITEM_CLASS_ROWS`（SkillCardData 行）与 `GD_EXPORT_SNIPPETS`，使其反映新增字段后的真实字段名与顺序，并保留既有三段声明的断言。
- 新增最小契约测试（遵循 `.trellis/spec/backend/resource-data-guidelines.md:23` 对新资源契约的要求），覆盖：类别常量与默认值、代表性技能卡资源加载后的类别读取、69 张卡均带显式类别行、卡面贴图映射与类别一致。

### R6 表格链路保持现状

本次**不**把类别接入 `card_table` 同步链路：不改 `card_table/export_current_cards.py`、`skill_cards.csv`、`card_tables.xlsx` 表头与 `card_table/README.md`。类别只在 `.tres` / Godot Inspector 中维护。

- 已验证的安全性依据：`upsert_existing_skill_card()`（`card_table/export_current_cards.py:1690-1754`）逐字段替换，不重写整份文件，表格同步不会抹掉 `.tres` 中的类别行。
- 已接受的代价：日后用表格新增卡牌时，`create_skill_card_resource()`（`:1595-1626`）生成的资源不含类别行，类别为未分类，需到 Inspector 补填（卡面此时显示原模板，不会误报为攻击牌）。

## Acceptance Criteria

- [x] `skill_card_data.gd` 暴露 `CardCategory`，`Skill` / `cost` / `CardTags` 三段声明原文与顺序未变，字段声明顺序为 `Skill` → `cost` → `CardTags` → `CardCategory`。
- [x] `CardCategory` 默认值为未分类；攻击 / 防御 / 状态取值与 R1 约定一致，Inspector 显示中文下拉。
- [x] `resources/skill_cards/*.tres` 全部 69 张都含显式 `CardCategory` 行且值为攻击（1），与 R2 规则一致；加载后 `CardCategory` 读回 1。
- [x] 卡面底板贴图随类别变化：攻击红、防御绿、状态蓝，未分类回退到 `技能卡模板2.png`；可在运行时实例化验证（含战斗手牌与开局抽卡两条路径）。
- [x] `test_run(suite="item_chain_boundary_contract")` 与新增契约套件全部通过，无失败、无 `SCRIPT ERROR` / `Parse Error` / 资源加载错误。
- [x] 战斗场景与开局抽卡界面冒烟运行无新增报错，卡面文字（名称 / 元素 / 描述 / 标签 / 费用）显示不受影响。
- [x] `card_table` 目录与相关脚本无改动。

### 验收证据（实现期实测）

| 验收项 | 证据 |
|---|---|
| 字段与顺序 | `skill_card_data.gd:9` / `:12` / `:15` / `:36`；`script_patch` 诊断为空 |
| 69 张回填 | `git diff --numstat resources/skill_cards` = 69 文件 / 69 insertions / 0 deletions；契约套件 `test_production_cards_carry_explicit_category` 通过 |
| 贴图切换 | `game_eval` 实测：`0`、`99` → `技能卡模板2.png`；`1` → `-红`；`2` → `-绿`；`3` → `-蓝` |
| 真实手牌 | `game_eval` 遍历战斗场景：3 张攻击牌为红模板，1 张未分类卡为通用模板 |
| 套件结果 | `skill_card_category_contract` 6/6、`item_chain_boundary_contract` 9/9、`gameplay_port_contract` 4/4、`player_hand_cache_contract` 3/3、`run_start_skill_card_contract` 20/20 |
| 冒烟 | 战斗场景与主场景 `project_run` 后游戏日志无 `SCRIPT ERROR` / `Parse Error` |
| `card_table` | `git status` 中无 `card_table/` 改动 |

> 关于「开局抽卡界面冒烟」：未另做 UI 点击式实机走查，覆盖由两条等价证据承担 —— 抽卡界面经由同一个 `init_card_data()` 绑定卡面（`run_start_skill_card_draft.gd:458`），该入口已在真实游戏进程内被 `game_eval` 逐类别验证；`run_start_skill_card_contract` 20/20 另覆盖抽卡界面把正确的卡交给卡面视图。

## Out of Scope

- 不修改 `resources/combat_skills/*.tres` 的战斗数值与效果。
- 不改动粉 / 紫 / 橙三张模板贴图的用途。
- 不改动卡面文本布局、`CardIcon` 元素图标与 `LockColor` 锁定遮罩逻辑。
- 不改动 `card_table` 表格同步链路（见 R6）。
- 不把类别接入保存 / 快照编解码（`core/save/save_slot_codec.gd`、`core/gameflow/run_snapshot.gd`）——类别是资源静态配置，不是运行期可变状态。
