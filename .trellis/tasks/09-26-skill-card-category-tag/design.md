# 技术设计：技能卡类别标签与分类贴图

本设计对应 `prd.md` 的 R1–R6。所有新增注释按项目规则使用中文，公共成员使用 `##` 文档注释。

## 1. 边界与改动面

| 层 | 文件 | 改动性质 |
|---|---|---|
| 数据契约 | `resources/item/card/skill_card_data.gd` | 新增类别常量 + 类别导出字段（追加在 `CardTags` 之后） |
| 资源数据 | `resources/skill_cards/*.tres`（69 个） | 在 `[resource]` 块显式插入 `CardCategory = 1` |
| 视图 | `scripts/card_scripts/skill_card.gd` | 新增贴图映射常量 + 在 `init_card_data()` 里按类别设置底板贴图 |
| 契约测试 | `tests/godot/test_item_chain_boundary_contract.gd` | 更新 SkillCardData 的字段登记表与默认值片段 |
| 新契约测试 | `tests/godot/test_skill_card_category_contract.gd` | 新增套件（常量 / 默认值 / 资源回填 / 源码形状） |
| 套件注册 | `tests/test_skill_card_category_contract.gd` | 顶层壳文件；没有它 `test_run` 发现不到该套件（见 5.3） |

明确不碰：`resources/combat_skills/*.tres`、`scenes/skill_card_scenes/SkillCard.tscn` 的节点结构、`core/save/*`、`core/gameflow/run_snapshot.gd`、`card_table/*`。

## 2. 数据契约

### 2.1 字段定义

在 `skill_card_data.gd` 的 `CardTags` 声明之后追加：

```gdscript
## 卡牌类别标签：攻击 / 防御 / 状态的分类取值。
##
## 未分类必须固定在 0：它同时是 CardCategory 的默认值，而 Godot 保存资源会省略
## 「等于默认值」的属性行。把未分类放在 0，显式填写的三类值才能持久保留在 .tres 里，
## 也不会让未配置的新卡静默退化成攻击牌。
const CARD_CATEGORY_UNCLASSIFIED: int = 0
const CARD_CATEGORY_ATTACK: int = 1
const CARD_CATEGORY_DEFENSE: int = 2
const CARD_CATEGORY_STATUS: int = 3

## 卡牌类别标签；默认未分类，未配置时卡面回退到通用模板而不是误显示为攻击牌。
@export_enum("未分类", "攻击", "防御", "状态") var CardCategory: int = CARD_CATEGORY_UNCLASSIFIED
```

设计要点：

- **类型选 `int` + `@export_enum`**：与项目既有导出惯例一致（`combat_skill_data.gd:41` 的 `Element: int`、`:44` 的 `TargetingType: int` 都是 int），同时让 Inspector 直接给中文下拉，`.tres` 中落为整数。
- **`@export_enum` 已验证可用**：项目此前未使用过该注解（全仓库 grep 无命中），实现期实测 Godot 4.7.1 正常解析、诊断为空，无需启用下面的降级方案。保留降级记录以防将来版本变化：① 脚本内 `enum CardCategoryKind { ... }` + `@export var CardCategory: CardCategoryKind`；② 纯 `@export var CardCategory: int = 0` + `@export_range(0, 3, 1)`。
- **跨脚本常量引用不可行（实现期实测，已改变方案）**：`const X: int = OTHER_SCRIPT.SOME_CONST` 会被 GDScript 拒绝，报 `Assigned value for constant "X" isn't a constant expression` —— 常量初始化器只接受常量表达式，跨脚本常量不属于常量表达式。因此卡面脚本**不能**直接引用数据脚本的类别常量，改为在 `skill_card.gd` 声明**镜像常量**（`CATEGORY_ATTACK/DEFENSE/STATUS`），并由新增契约套件断言两侧数值恒等；这与项目既有的 `scripts/shop/shop_control.gd` 的 `FAILURE_*` 镜像做法一致，避免把编译期能发现的问题推迟到运行时的字典查询。
- 不声明 `class_name`：延续 `skill_card_data.gd:6` 的既有理由（避免与兼容层全局类型重名）。

### 2.2 `.tres` 序列化形态

回填后每张技能卡 `[resource]` 块新增一行：

```
CardCategory = 1
```

数值只写整数（`@export_enum` 序列化为 int）。由于 1 ≠ 默认值 0，Godot 后续保存该资源时不会删除这一行。

## 3. 类别判定与回填

### 3.1 判定口径

| 判定 | 条件 | 结果 |
|---|---|---|
| 攻击 | 伤害总量 > 0 且（无护盾 或 伤害总量 ≥ 护盾总量） | `1` |
| 防御 | 护盾总量 > 伤害总量 | `2` |
| 状态 | 伤害总量 = 0 且 护盾总量 = 0 | `3` |

- 伤害总量 = Σ(`DamageEffect.BaseDamage` × `HitCount`)。
- 护盾总量 = Σ(`ApplyShieldCardEffect.ShieldStatus.DefaultShieldAmount`)。
- 判定依据效果资源的**导出字段**（`BaseDamage`/`HitCount`，以及 `ShieldStatus.DefaultShieldAmount`），与 `combat_skill_data.gd:19-23`、`:116-123` 既有的「按字段协议而非语言身份识别效果」的做法保持一致。

### 3.2 回填方式

用一次性 Python 文本改写脚本（放在系统临时目录，不进仓库），对 69 个 `.tres`：

1. 定位 `[resource]` 块（`get_resource_block` 式切分，避免误改 `[sub_resource]`）。
2. 在 `CardTags = ...` 行之后插入 `CardCategory = <值>`；若该文件没有 `CardTags` 行，则退化为在 `CardName = ...` 行之后插入。
3. 若已存在 `CardCategory =` 行则替换而不是重复插入（幂等，可安全重跑）。

**为什么用文本插入而不是 `ResourceSaver.save()`**：Godot 保存会省略等于默认值的属性行，用引擎重存这 69 个文件会把 `cost = 10` 之类的既有显式行整批删掉，产生与本次任务无关的巨大 diff。文本插入只增加一行，改动最小且可审阅。

**换行符必须按原文件字节保留（实现期踩坑与处置）**：仓库 `core.autocrlf=true`，这批 `.tres` 在工作区是 **LF 与 CRLF 混合**的，而 git 的归一化会掩盖这一点，所以「工作区看起来干净」并不代表换行符统一。批量改写必须先探测每个文件自己的换行符、把已有 `\r\n` 规范成 `\n` 再插入，最后才按该文件的原始换行符还原。若直接在含 `\r\n` 的文本上做 `replace("\n", "\r\n")`，既有 `\r\n` 会被二次转换成 `\r\r\n`，文件内容被真实改坏，`git diff` 立刻膨胀成 714 insertions / 645 deletions。本次实现第一次就踩了这个坑，处置方式是 `git checkout -- resources/skill_cards` 整体回滚后按上述顺序重做，最终 diff 收敛为**每文件恰好 +1 行、0 删除**。

回填结果必须是 **69 张全部为 `CardCategory = 1`**（现有卡无纯防御卡、无纯状态卡，`test_card_2` 按平局规则归攻击）。

## 4. 视图契约

### 4.1 贴图映射

在 `scripts/card_scripts/skill_card.gd` 增加：

```gdscript
## 类别 → 卡面底板贴图。未分类不在表中，由 CARD_FRAME_UNCLASSIFIED 兜底。
const CARD_FRAME_ATTACK: Texture2D = preload("res://res/Card/skillcardboard/技能卡模板-红.png")
const CARD_FRAME_DEFENSE: Texture2D = preload("res://res/Card/skillcardboard/技能卡模板-绿.png")
const CARD_FRAME_STATUS: Texture2D = preload("res://res/Card/skillcardboard/技能卡模板-蓝.png")

## 未分类或类别缺失时的兜底底板，沿用本次改动前一直在用的通用模板。
const CARD_FRAME_UNCLASSIFIED: Texture2D = preload("res://res/skillcard/技能卡模板2.png")
```

`init_card_data()` 末尾追加一行设置 `$Sprite2D.texture`，并用一个私有函数把 `CardCategory` 映射为贴图，对未知整数走兜底分支。

### 4.2 为什么改在 `init_card_data()`

`init_card_data()` 是三个复用点的唯一数据入口（`player_hand.gd:82`、`run_start_skill_card_draft.gd:458`、以及其它实例化点），把换贴图放在这里，三处界面自动一致，不需要给 `SkillCard.tscn` 的三个使用方各写一遍。

### 4.3 尺寸安全

三张新模板与在用的 `技能卡模板2.png` 都是 140×100（实测 PNG 头），`SkillCard.tscn` 的 `Sprite2D.scale = (1.5, 1.5)` 与 `Area2D` 碰撞形状都无需改动，也不会有视觉偏移。

## 5. 契约同步

### 5.1 既有套件

`tests/godot/test_item_chain_boundary_contract.gd`：

- `ITEM_CLASS_ROWS` 的 `SkillCardData` 行（`:22`）字段数组改为 `["Skill", "cost", "CardTags", "CardCategory"]`，与实际声明顺序一致。
- `GD_EXPORT_SNIPPETS` 的技能卡行（`:34`）追加新字段的**逐字**声明片段，并保留原有三段。
- C# 垫片 `SkillCardData.cs` 已删除，`csharp_optional.gd` 会让 C# 侧对照自动收起，本次不需要、也不得新建任何 `.cs`。

### 5.2 新增套件

新建 `tests/godot/test_skill_card_category_contract.gd`（`extends McpTestSuite`，提供 `suite_name()`），覆盖：

1. `skill_card_data.gd` 中四个类别常量存在且取值为 0/1/2/3。
2. 类别字段默认值为未分类（实例化一个空资源后读回默认值）。
3. 代表性资源加载后类别可读：`test_card_2.tres` 读取为攻击（平局规则），并抽查若干纯伤害卡同样为攻击。
4. 69 张技能卡 `.tres` 全部包含显式 `CardCategory =` 行（用 `FileAccess` 文本检查，证明回填确实落盘、不被默认值吞掉）。
5. `skill_card.gd` 中三张类别贴图常量指向 `技能卡模板-红/绿/蓝.png`，兜底常量指向 `技能卡模板2.png`。
6. ~~实例化 `SkillCard.tscn` 并喂入四种类别数据后断言 `$Sprite2D.texture`~~ —— **实现期确认在编辑器内不可行**，见 5.3；改用源码形状断言 + 运行期 `game_eval` 承担等价证据。

### 5.3 套件注册与运行期验证（实现期发现）

**新套件必须在 `tests/` 顶层加壳文件。** `test_run` 的 discovery（`addons/godot_ai/handlers/test_handler.gd:318`）只列 `res://tests` 的**直接子项且不递归**，`tests/godot/` 下的套件全部靠顶层同名壳被发现。壳文件内容为：

```gdscript
@tool
extends "res://tests/godot/test_skill_card_category_contract.gd"
```

只把文件放进 `tests/godot/` 会让套件"文件存在但注册不上"，`test_run` 报 `No suite named ... is registered (52 discovered)`。实现期验证：插件重载（`editor_reload_plugin`）**不会**刷新 discovery 缓存，补上壳文件后重新 `filesystem_manage(op="scan")` 即可被发现。

**贴图切换的真实证据走运行期 `game_eval`。** `SkillCard` 是非 `@tool` 的 Node2D 脚本，编辑器测试里 `PackedScene.instantiate()` 只能得到占位实例、方法不可调用（`test_run_start_skill_card_contract.gd:15-18` 已记录同一限制），所以套件只断言源码形状（四张贴图常量、资源真实存在、`init_card_data` 确实写出 `$Sprite2D.texture`）。等价的可执行证据由冒烟阶段的 `game_eval` 提供：`duplicate()` 一张真实卡 → 改 `CardCategory` → 实例化 `SkillCard.tscn` → 调用 `init_card_data()` → 读 `$Sprite2D.texture.resource_path`。实测：0 与 99 → `技能卡模板2.png`；1 → `技能卡模板-红.png`；2 → `技能卡模板-绿.png`；3 → `技能卡模板-蓝.png`；并在真实战斗手牌中确认攻击牌为红模板、未分类卡为通用模板。

## 6. 兼容性与风险

| 风险 | 评估 | 处理 |
|---|---|---|
| 新增导出字段破坏既有字段奇偶校验测试 | 确定会发生 | 同一改动内更新登记表（5.1），并在验证阶段跑该套件（实测 9/9 通过） |
| `@export_enum` 未被项目使用过 | 已消除 | 实现期实测 4.7.1 可用、诊断为空，未触发降级（2.1） |
| GDScript 不允许跨脚本常量初始化 | 确定存在 | 卡面改用镜像常量，并由契约套件断言两侧数值恒等（2.1） |
| 新套件放进 `tests/godot/` 会被 discovery 漏掉 | 确定存在 | 必须在 `tests/` 顶层补壳文件，否则报「未注册」（5.3） |
| 批量文本改写破坏 `.tres` 换行符 | 确定存在（已踩） | 先规范化再按原换行符还原；踩坑后整体回滚重做，最终每文件 +1 行、0 删除（3.2） |
| 编辑器测试无法实例化非 `@tool` 卡面 | 确定存在 | 套件只做源码形状断言，真实贴图切换由运行期 `game_eval` 承担（5.3） |
| Godot 保存资源省略默认值行 | 确定存在 | 默认值取未分类（0），显式回填值 1 不会被省略（2.2） |
| 表格同步抹掉类别 | 已排除 | `upsert_existing_skill_card()` 逐字段替换，不重写文件 |
| 非战斗界面（开局抽卡）未换贴图 | 已排除 | 抽卡界面调用同一个 `init_card_data()` |
| 三张贴图导致卡面文字可读性问题 | 低 | 三张模板与旧模板同为 140×100，`scale`/碰撞无需改动；实机冒烟确认卡面正常渲染 |

## 7. 回滚

- 代码与测试：`git checkout -- resources/item/card/skill_card_data.gd scripts/card_scripts/skill_card.gd tests/godot/test_item_chain_boundary_contract.gd`，并删除新增测试文件。
- 资源：`git checkout -- resources/skill_cards`（回填只加行，回滚即整体还原）。
- 无运行期存档兼容问题：类别是资源静态配置，不进入存档 / 快照编解码（`core/save/save_slot_codec.gd` 只按 `CardId` 存取，不受影响）。
