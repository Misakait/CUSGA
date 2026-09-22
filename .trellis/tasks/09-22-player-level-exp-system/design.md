# 技术设计：玩家等级与经验值系统

## 1. 边界与职责划分

本任务只新增一个**独立的等级规则组件**，并用最小胶水把它接到现有系统上。三个职责严格分离：

| 角色 | 承担者 | 职责 |
| --- | --- | --- |
| 规则与状态 | 新增 autoload `PlayerLevel` | 拥有等级、经验、经验曲线、待发属性点；发出变更信号 |
| 属性点消费 | `entities/player.gd` | 监听等级系统的发点信号，把点数交给自己的 `AttributeComponent.EarnPoints` |
| 展示 | `core/ui/attribute_summary_ui.gd` + `AttributeSummaryUI.tscn` | 读取等级并显示在属性栏第一行 |

**关键解耦约束**：`PlayerLevel` **不得**引用玩家实体、不得引用场景节点、不得引用任何 UI。它只认识自己的数值和信号；「点数最终落到哪个属性组件」完全由玩家实体决定。这样等级系统可以在没有玩家、没有 UI 的纯逻辑环境中被测试和复用。

`PlayerLevel` 也**不修改** `AttributeComponent`：属性点的分配权完全留给玩家（`TryAllocatePoint`），等级系统只负责「发点」。

## 2. 新增 autoload：`core/progression/player_level.gd`

放在 `core/progression/`，与既有的 `player_progression.gd`（仓库/带入栏容量升级）同目录 —— 两者都是「玩家成长」域的全局服务，但语义互不重叠。

### 2.1 常量（全部集中在脚本顶部，便于检查器/源码直接调参）

```gdscript
const SettingsSection: String = "player"      ## 存档分组，与 PlayerWallet/PlayerProgression 同组
const LevelKey: String = "level"              ## 等级存档键
const ExperienceKey: String = "experience"    ## 经验存档键
const PersistAcrossRuns: bool = false         ## 与 PlayerWallet / PlayerProgression 同值（开发期不跨运行保存）

const MinLevel: int = 1                       ## 最低等级
const MaxLevel: int = 50                      ## 满级等级
const BaseExperienceRequirement: int = 100    ## 1→2 级所需经验
const ExperienceRequirementStep: int = 50     ## 每高一级增加的所需经验
const AttributePointsPerLevel: int = 3        ## 每次升级发放的属性点
```

经验曲线：`GetExperienceRequirement(level) = BaseExperienceRequirement + ExperienceRequirementStep * (level - MinLevel)`。

| 当前等级 | 升到下一级所需经验 |
| --- | --- |
| 1 | 100 |
| 2 | 150 |
| 3 | 200 |
| … | 每级 +50 |
| 49 | 2500 |
| 50（满级） | 0（无下一级） |

### 2.2 状态与信号

```gdscript
signal LevelChanged(level: int)                                          ## 等级变化，携带新等级
signal ExperienceChanged(current_experience: int, required_experience: int)  ## 经验变化，携带当前经验与下一级需求
signal AttributePointsGranted(pending_points: int)                       ## 有可领取属性点，携带当前挂起总数

var Level: int = MinLevel                 ## 当前等级
var CurrentExperience: int = 0            ## 当前等级内已累积经验
var PendingAttributePoints: int = 0       ## 已发放但尚未被玩家领取的属性点
```

`AttributePointsGranted` 携带的是**挂起总数**而非增量：监听者收到信号后统一调用 `ClaimPendingAttributePoints()` 一次性领取并清零。这个「总数 + 领取清零」模型天然幂等 —— 玩家实体漏接一次信号，下次信号或下次 `_ready` 补领时仍能拿到全部点数，不会丢也不会重复发。

### 2.3 公开接口

| 接口 | 行为 |
| --- | --- |
| `AddExperience(amount) -> int` | 非正数或已满级返回 0；否则累加经验并连续结算升级，返回实际入账值 |
| `TryLevelUp() -> bool` | 经验足够时扣除经验升 1 级并返回 true；不足或满级返回 false |
| `AddLevels(count) -> int` | 不消耗经验直接提升至多 `count` 级，返回实际提升级数；满级时返回 0 |
| `GetLevel() -> int` | 读取当前等级 |
| `GetExperience() -> int` | 读取当前等级内已累积经验 |
| `GetExperienceToNextLevel() -> int` | 读取升级所需经验；满级返回 0 |
| `GetExperienceRequirement(level) -> int` | 纯规则查询：指定等级升到下一级的需求；满级返回 0 |
| `IsMaxLevel() -> bool` | 是否已满级 |
| `ClaimPendingAttributePoints() -> int` | 领取挂起属性点并清零；无可领取时返回 0 |

### 2.4 升级结算算法

三级复用同一个私有原语，避免三处各写一遍「升级要发点」的规则：

```gdscript
## 提升一级并累积属性点；不发信号，由调用方统一决定信号时机。
func _apply_level_gain() -> void:
	Level += 1
	PendingAttributePoints += AttributePointsPerLevel
```

`AddExperience` 的连续升级循环：

```gdscript
CurrentExperience += amount
while not IsMaxLevel():
	var required := GetExperienceToNextLevel()
	if required <= 0 or CurrentExperience < required:
		break
	CurrentExperience -= required
	_apply_level_gain()
	LevelChanged.emit(Level)
if IsMaxLevel():
	CurrentExperience = 0     # 满级后不再需要经验，避免留下永远无法消耗的残值
```

**满级语义**：`AddExperience` 在满级时直接返回 0、不改任何数值（快速短路，不产生无意义的信号）。

### 2.5 持久化

沿用 `PlayerWallet` 的模式：`_settings_manager` 经 `get_node_or_null("/root/SettingsManager")` 解析，缺失时只影响跨运行保存。

- `PersistAcrossRuns == false` 时，`_ready()` 清除遗留存档键，运行内生效。
- 读取时校验：等级钳制到 `1..MaxLevel`；经验钳制到 `0..(需求-1)`，非法值回退默认并 `push_warning`。
- **只持久化等级与经验**。属性点不做第二份存档 —— 点数一旦被 `EarnPoints` 领取就已属于属性组件，再存一份会导致重载后重复发点。

## 3. 玩家实体消费路径：`entities/player.gd`

玩家根脚本新增一个「领取属性点」的消费入口，遵循项目既有的「解析 autoload → 连接信号 → `_exit_tree` 精确断开」模式（与它现有处理 `GlobalEventBus` 天赋事件的方式完全一致）。

```gdscript
## 等级系统 autoload 节点路径。
const PLAYER_LEVEL_PATH: NodePath = ^"/root/PlayerLevel"

## 等级系统节点，只按稳定方法/信号协议访问。
var _player_level: Node = null
```

`_ready()` 末尾新增：

```gdscript
_player_level = get_node_or_null(PLAYER_LEVEL_PATH)
_bind_player_level()
```

```gdscript
## 订阅等级系统的发点信号，并补领本次绑定前已累积的属性点。
func _bind_player_level() -> void:
	if _player_level == null:
		return
	if _player_level.has_signal(&"AttributePointsGranted") \
			and not _player_level.is_connected(&"AttributePointsGranted", _on_attribute_points_granted):
		_player_level.connect(&"AttributePointsGranted", _on_attribute_points_granted)
	# 玩家可能在升级之后才进入场景（场景切换、重载），这里补领历史挂起点数。
	_grant_pending_attribute_points()
```

```gdscript
## 领取挂起属性点并写入属性组件；属性组件不具备发点能力时保持挂起，绝不静默丢弃。
func _grant_pending_attribute_points() -> void:
	if _player_level == null or Attributes == null:
		return
	if not _player_level.has_method("ClaimPendingAttributePoints") or not Attributes.has_method("EarnPoints"):
		return
	var claimed: int = int(_player_level.call("ClaimPendingAttributePoints"))
	if claimed <= 0:
		return
	Attributes.call("EarnPoints", claimed)
```

`_exit_tree()` 按既有风格补一条 `_player_level.disconnect(...)`。

**为什么用「先探测能力、再领取」的顺序**：先 `Claim` 再发现组件不支持，就必须设计退点接口来补漏。把能力检查放在领取之前，让不支持的组合退化为「点数继续挂起」，用更少的代码消灭了丢点的可能性。

**为什么由玩家实体主动领取，而不是等级系统主动推送**：等级系统不知道玩家在哪里，也不该知道。主动推送需要它去 `get_tree()` 里找玩家节点，那是把实体查找的耦合引进了全局规则层。

## 4. 展示路径

### 4.1 场景：`scenes/inventory/AttributeSummaryUI.tscn`

在 `VBoxContainer/AttributeGrid` 的**最前面**插入两行节点，使等级成为属性栏第一行（该 Grid 为 2 列，声明顺序即渲染顺序）：

```text
VBoxContainer
├─ Title ("属性")
└─ AttributeGrid
   ├─ LevelLabel  ("等级")     ← 新增，必须声明在 PhysAtkLabel 之前
   ├─ LevelValue  (unique_name_in_owner, 右对齐)  ← 新增
   ├─ PhysAtkLabel …（以下既有节点位置不变）
```

### 4.2 脚本：`core/ui/attribute_summary_ui.gd`

- 新增 `const PLAYER_LEVEL_PATH: NodePath = ^"/root/PlayerLevel"`（**必须是 `NodePath`**：用 `StringName` 传 `get_node_or_null` 会触发 Parser Error）。
- 新增 `var _player_level: Node = null` 与 `var _level_value: Label = null`。
- 新增公开注入点 `BindPlayerLevel(player_level: Node) -> void`：与既有 `Bind(attributes)` 同一模式，供显式注入与编辑器侧契约测试使用；`_ready()` 中若未注入则自动从 `/root/PlayerLevel` 解析。**这是本设计唯一的测试可注入点**，否则等级来源写死在 autoload 路径上就无法在 `test_run` 环境（无 autoload）中验证显示逻辑。
- `_refresh_level()`：有等级源时显示等级数字，无等级源时显示 `-`（与其余属性值同一降级占位符），保证独立运行任何不含该 autoload 的场景都不报错。
- 连接 `LevelChanged` 驱动刷新；`_exit_tree()` 中精确断开。

等级数值读取走「方法优先、属性兜底」：

```gdscript
var level: int = int(_player_level.call("GetLevel")) if _player_level.has_method("GetLevel") else int(_player_level.get("Level"))
```

## 5. 兼容性与回归风险

| 风险 | 说明 | 对策 |
| --- | --- | --- |
| `test_player_contract.gd` 用字面量锁定 `player.gd` | 它只断言「必须保留」既有字段/方法/路径，**不禁止新增** | 只新增、不修改既有成员；新路径常量必须是 `NodePath`；脚本内不得出现 `TODO` |
| `test_production_language_binding_contract.gd` 扫描生产脚本中的 `.cs` | 扫描前剥离注释，代码与字符串字面量中出现 `.cs` 会失败 | 新脚本正文不出现 `.cs` 字面量 |
| `test_attribute_summary_ui_contract.gd` 的最小测试树 | `attribute_summary_ui.gd` 的 `_ready()` 用 `get_node("%LevelValue")` 强取节点；测试夹具只构造它知道的标签，缺 `LevelValue` 会直接报错 | 必须同步在夹具的标签列表中补 `LevelValue` |
| 编辑器 `test_run` 环境无 autoload | `PlayerLevel` 在编辑器测试环境中不存在，等级来源解析为 null | 生产脚本全部走 `get_node_or_null` + 能力探测；UI 提供 `BindPlayerLevel` 注入点 |
| `PlayerLevel._ready()` 在无 `SettingsManager` 时报错 | 编辑器测试环境没有该 autoload | 契约测试**不触发** `_ready()`，只 `new()` 后调用规则方法；持久化策略以常量锁定方式验证（与既有 `PlayerWallet` 测试同一做法） |

## 6. 回滚形态

三处改动互相独立，可分别回滚：

1. 删除 `core/progression/player_level.gd` 并从 `project.godot` 注销 autoload → 等级系统消失；UI 与玩家实体因能力探测自动降级（UI 显示 `-`，玩家不再领取点数），**不会报错**。
2. 只回滚 `player.gd` → 等级系统仍可用，仅属性点不再落到玩家身上（点数继续挂起）。
3. 只回滚 UI 两个文件 → 等级逻辑与发点完全不受影响。

## 7. 测试方案

### 新增 `tests/godot/test_player_level_contract.gd`（suite `player_level_contract`）

**必须同时补一个发现壳 `tests/test_player_level_contract.gd`**：插件的测试发现（`addons/godot_ai/handlers/test_handler.gd` 的 `_discover_suites`）只 `DirAccess.open("res://tests")` 扫**顶层且不递归**，而真实实现都放在 `tests/godot/`；`res://tests/*.gd` 一律是 4 行 `extends "res://tests/godot/..."` 转发壳。缺少壳的套件不会被 `test_run` 发现（表现为 `INVALID_PARAMS: No suite named ...`，且重载插件与 `scan` 都无法救回）。

**形状锁定**：脚本存在、带 uid 旁车、不声明 `class_name`、常量与经验曲线字面量逐字锁定、方法面存在。

**行为验证**（`new()` 实例，不触发 `_ready()`，因此无 autoload 依赖）：

- 初始：等级 1、经验 0、未满级。
- 边界累积：`AddExperience(99)` → 等级 1 / 经验 99 / 返回 99；再 `AddExperience(1)` → 等级 2 / 经验 0。
- 连续升级：1 级时 `AddExperience(1050)` → 等级 6 / 经验 50（消耗 100+150+200+250+300 = 1000）。
- 曲线：`GetExperienceToNextLevel()` 在 1/2/49 级分别返回 100/150/2500；50 级返回 0。
- 满级：`AddLevels(999)` → 实际提升 49 级、等级 50、`IsMaxLevel()` 为真；随后 `AddExperience(100)` 返回 0 且数值不变；`TryLevelUp()` 返回 false。
- 零值与负数：`AddExperience(0)` / `AddExperience(-5)` / `AddLevels(0)` 均返回 0 且不改数值。
- `TryLevelUp()`：经验不足返回 false 且数值不变；经验足够返回 true、扣除经验并升级。
- 属性点：每升 1 级挂起 +3；`ClaimPendingAttributePoints()` 返回累计值并清零；重复领取返回 0。
- 信号载荷：`LevelChanged`、`ExperienceChanged`、`AttributePointsGranted` 的触发次数与参数逐一断言。

### 修改 `tests/godot/test_attribute_summary_ui_contract.gd`

- 夹具 `_new_attribute_summary_ui()` 的标签列表中补 `LevelValue`（否则 `_ready()` 取节点失败）。
- 新增用例：未注入等级源时显示 `-`；`BindPlayerLevel(fake)` 后显示等级；fake 发出 `LevelChanged` 后文本立即更新；切换到另一个等级源时解除旧连接；退出场景树后解除全部连接。
- 既有 `_assert_all_values` 占位符断言保持对其余标签生效。

### 回归套件

`player_contract`、`production_language_binding_contract`、`contract` 相关全量套件。

## 8. 验证方式（编辑器 MCP）

```text
test_run(suite="player_level_contract")
test_run(suite="attribute_summary_ui_contract")
test_run(suite="player_contract")                        # 回归
test_run(suite="production_language_binding_contract")   # 回归：确认无 .cs 字面量
project_run(mode="main") + logs_read(source="game")      # 断言无 SCRIPT ERROR
game_eval(...)                                           # 运行中的游戏里断言 autoload 可用、发点真的落到 Attributes
editor_screenshot(source="game")                         # 目视确认属性栏第一行的等级行
```

`game_eval` 需要断言三件事：`PlayerLevel` 节点存在且 `GetLevel()` 为 1；`AddExperience(100)` 后等级为 2、玩家 `AvailablePoints` 增加 3；`ClaimPendingAttributePoints()` 再取为 0。

## 9. 文档同步

`docs/游戏机制与玩法内容.md` 新增「等级与经验系统」一节，记录：等级范围、经验曲线公式与关键节点数值（1→2 需 100、49→50 需 2500、满级累计 63700）、每级 3 点属性点（满级累计 147 点）、属性点来源与分配方式、以及「当前不接入任何玩法发放经验」的现状说明。
