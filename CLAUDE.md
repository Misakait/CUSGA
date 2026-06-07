# CLAUDE.md

> CUSGA — Godot 4.6 + C# (.NET 8) 2D 游戏项目。此文件引导 Claude Code 在该仓库中工作。

## 项目概览

CUSGA 是一款基于 Godot 4.6（Mono/C# 版本）+ .NET 8 的 2D 游戏，使用 C# 与 GDScript 混合开发。当前包含地图探索、地形交互、遭遇战斗、背包/仓库、装备与词条、制作系统等核心玩法模块。

## 构建与验证命令

> **关键约束**：Husky 钩子会在本地 `dotnet build` / `dotnet test` 时尝试写入 `.git/config`，沙箱环境会崩溃。**所有 dotnet 命令必须加 `env CI=true` 前缀绕过钩子。**

### 构建主工程

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

### 构建测试工程

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

### Godot 运行时验证

当改动涉及 GDScript、`.tscn` 场景、Godot 资源、C# `[GlobalClass]` 类型、autoload 访问或场景/运行时集成时，必须用 `godot-mono --headless` 额外验证：

```bash
# 构建 Godot C# 解决方案并刷新全局类
godot-mono --headless --path . --build-solutions --quit

# 解析检查单个 GDScript 文件
godot-mono --headless --path . --check-only --script res://path/to/script.gd

# 运行 Godot 运行时测试
godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd
godot-mono --headless --path . --script res://tests/godot/skill_targeting_type_codegen_tests.gd

# 冒烟测试场景
godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5
```

### 代码格式化

```bash
dotnet format CUSGA.sln
```

## 技术栈

- **引擎**：Godot 4.6（Mono/C# 版），渲染后端 `gl_compatibility`
- **SDK**：Godot.NET.Sdk/4.6.3，目标框架 `net8.0`（Android 为 `net9.0`）
- **语言**：C#（主逻辑）+ GDScript（场景/UI/动画脚本）
- **物理**：Jolt Physics
- **测试**：C# 控制台测试 (`tests/CUSGA.Tests/`) + Godot 运行时脚本测试 (`tests/godot/`)
- **代码工具**：Husky（pre-commit 钩子）、CodeGraph（C# 符号索引）、GitNexus（代码智能）

## 目录结构

```text
core/                    核心系统（C#）
  application/           应用层 — EncounterManager, GameplayPort
  attributes/            属性系统 — AttributeModifier, IReadOnlyAttribute
  autoloads/             Godot 自动加载 — TimeSystem, WeatherManager
  board/                 棋盘/卡牌 — BoardController, BoardCardView
  combat/                战斗系统 — DamageFormula, DamagePayload, ElementalSystem
    buffs/               Buff 状态 — Burn, Shield, Vulnerable 等
    effects/             战斗效果
    skills/              战斗技能
    status/              状态实例
  constants/             常量定义
  crafting/              制作系统 — CraftingService, CraftingFailureReason
  debug/                 调试工具
  gameflow/              游戏流程
  interfaces/            接口定义
  inventory/             背包 — ItemStack
  map/                   地图系统 — PassageGuard, RoomTerrain 等
  ui/                    UI 系统 — crafting, draggable, hud, warehouse

entities/                实体与组件（C#）
  components/            ECS 组件 — AttributeComponent, BattleDeckComponent,
                         CombatComponent, EquipmentComponent, StatusComponent ...
  Monster.cs, Player.cs  实体定义

resources/               Godot 资源文件（.tres）
  buffs/                 Buff 数据资源
  combat_skills/         战斗技能资源（按元素/类型命名）
  items/                 物品资源
  monsters/              怪物数据资源

scenes/                  Godot 场景文件（.tscn）
  battle_scenes/         战斗场景
  inventory/             背包 UI 场景
  crafting/              制作 UI 场景
  map_scenes/            地图场景（earth/fire 等元素区域）
  main_menu_scenes/      主菜单场景

scripts/                 GDScript 脚本
  anim/                  动画 — CardAnimations, ScreenTransitions
  battle_scripts/        战斗脚本 — battle_manager, monster_manager, player_manager
  card_scripts/          卡牌脚本 — card_manager, deck_manager, player_hand
  map_scripts/           地图脚本
  generated/             自动生成的脚本（如 SkillTargetingType.gd）

addons/                  编辑器插件
  card_csv_sync/         CSV 卡牌同步
  skill_targeting_type_codegen/  技能目标类型代码生成（C# 枚举 → GDScript）

tests/
  CUSGA.Tests/           C# 单元测试
  godot/                 Godot 运行时脚本测试
```

## Autoload 系统

项目注册了 7 个自动加载单例（按加载顺序）：
1. `GlobalEventBus` — 全局事件总线
2. `TimeSystem` — 时间/昼夜系统
3. `WeatherManager` — 天气管理
4. `ItemsControl` — 物品控制
5. `GlobalWarehouse` — 全局仓库
6. `SceneManager` — 场景管理
7. `ScreenTransitions` — 屏幕过渡

## 代码约定

- **注释语言**：所有代码注释使用中文
- **XML 文档**：所有 public 类、方法、函数必须有标准 XML 文档注释，显式说明参数和返回值
- **内联注释**：复杂/非直观逻辑（如制作结算、战斗状态转换）必须添加内联注释，重点解释 **为什么** 这样做而非描述做了什么
- **可读性优先**：代码保持简洁，但绝不为了简短牺牲必要的解释性注释

## 工具使用指南

### CodeGraph（C# 代码索引）

CodeGraph 是 tree-sitter 驱动的符号知识图谱，用于结构化查询。**GDScript 不在索引范围内**。

| 场景                        | 工具                  |
| --------------------------- | --------------------- |
| 查找符号定义                | `codegraph_search`    |
| 谁调用了函数 Y              | `codegraph_callers`   |
| Y 调用了什么                | `codegraph_callees`   |
| 修改 Z 的影响范围           | `codegraph_impact`    |
| 查看 Y 的签名/源码/docstring | `codegraph_node`      |
| 获取某领域的聚焦上下文      | `codegraph_context`   |
| 探索不熟悉的模块            | `codegraph_explore`   |
| 列出路径下的文件            | `codegraph_files`     |

- 优先使用 CodeGraph 做结构查询，避免用 grep 验证其结果
- GDScript 符号仍用 `rg` / `grep` 搜索

### GitNexus（代码智能）

- **编辑任何符号前**必须运行 `gitnexus_impact` 检查影响范围
- **提交前**必须运行 `gitnexus_detect_changes()` 验证改动范围
- HIGH 或 CRITICAL 风险时需警告用户

### Godot 编辑器插件

- `resources_spreadsheet_view` — 资源表格视图
- `card_csv_sync` — CSV 卡牌同步
- `skill_targeting_type_codegen` — 技能目标类型代码生成（C# → GDScript）

## 输入映射

- `B` 键 — 切换背包 (`toggle_inventory`)
- `F1` (keycode 4194306) — 切换制作界面 (`toggle_crafting`)

## 物理层

| 层 | 名称     |
| -- | -------- |
| 1 | 卡牌     |
| 2 | 卡牌槽位 |
| 3 | 禁用卡牌 |
| 4 | 怪物卡   |
