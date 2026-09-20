# CUSGA

CUSGA 是一个基于 **Godot 4.7.1 + C#（.NET 8）** 的 2D 游戏项目，当前包含地图探索、地形交互、遭遇战斗、背包/仓库、装备与词条、制作系统等核心玩法模块。

## 技术栈

- Godot 4.7.1（启用 C#）
- .NET 8.0（`Godot.NET.Sdk/4.7.1`）
- C# + GDScript 混合开发

## 当前功能概览

- **地图与场景流转**：地图间移动、房间加载、昼夜切换。
- **通道驻守怪物**：夜晚通道可被怪物驻守，击败后才能通过。
- **战斗接入**：世界场景与战斗场景切换，支持按地形/天数缩放怪物。
- **地形交互**：地形卡点击交互、采集与遭遇逻辑。
- **背包与仓库**：背包 UI、全局仓库、物品增减与堆叠。
- **装备与标签**：装备槽位、装备标签校验、夜间遭遇概率修正。
- **制作系统**：材料校验、空间校验、制作失败原因返回。

## 目录结构（核心）

```text
core/                  核心系统（application/combat/crafting/map/ui 等）
entities/              实体与组件（Player、Monster、各类 Component）
resources/             游戏资源定义（怪物、道具、配方、交互、天气等）
scenes/                Godot 场景（Main、地图、战斗、UI、背包、制作等）
scripts/               GDScript 脚本（地图按钮、动画、UI、代码生成输出等）
tests/CUSGA.Tests/     C# 测试工程（控制台测试入口）
tests/godot/           Godot 运行时脚本测试
addons/                编辑器插件（如技能目标类型代码生成）
```

## 环境要求

- **Godot 4.7.1（Mono/C# 版本）** — 当前 `project.godot` 的 `config/features` 为 `("4.7", "C#", "Forward Plus")`
- .NET SDK 8.0+

> **注意目录名会误导人**：本仓库所在文件夹叫 `Godot_v4.6.3-stable_mono_win64`，同级还有一个 `Godot_v4.6.3-stable_mono_win64_console.exe`，这些都是**遗留物，不是项目用的引擎**。
> 项目实际使用 **4.7.1**：编辑器会话报 `4.7.1-stable`，`CUSGA.csproj` 引用 `Godot.NET.Sdk/4.7.1`，且 `addons/godot_ai` 要求 Godot ≥ 4.7。
> 判断版本请以这三处为准，不要看文件夹名。

## 快速开始

1. 进入项目目录：

   ```bash
   cd /path/to/CUSGA
   ```

2. 用 Godot 打开 `project.godot`。

   项目通过编辑器内的 `addons/godot_ai` 插件对外提供 MCP 接口：AI 可据此读写场景与脚本、运行游戏、抓取运行日志、执行 Godot 运行时测试，甚至直接在运行中的游戏里执行 GDScript 并取回返回值。

   > **不使用 `godot-mono` 命令行。**
   > 本机虽已安装 Godot Mono（`E:\Godot\` 下有 4.5.1 / 4.6.1 / 4.6.3 / 4.7.1），但未加入 PATH，也不在验证流程内。
   > 需要 Godot 侧验证时，请保持**编辑器处于打开状态**，由 AI 通过编辑器 MCP 完成；编辑器未打开时请先打开 Godot，不要改用命令行。

## 构建与验证

> 本项目启用了 Husky 钩子。命令行构建建议显式加 `CI=true`，避免本地钩子写入限制导致失败。

### 1) 构建主工程

```bash
env CI=true dotnet build CUSGA.sln
```

### 2) 构建 C# 测试工程

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj
```

### 3) 运行 Godot 运行时测试

统一通过**编辑器 MCP**执行，不再使用 `godot-mono --headless`：

- `test_run` — 执行 `tests/godot/` 下的全部运行时脚本测试（等价于原先逐条 `--script` 调用），可用 `suite` / `test_name` 过滤单个用例
- `game_eval` — 在运行中的游戏里执行 GDScript 并取回返回值
- `logs_read(source="game")` — 读取游戏运行日志，捕获 `SCRIPT ERROR` / `push_error`
- `project_run` — 启动游戏（`mode="custom"` 可指定场景），结束用 `project_manage(op="stop")`

### 4) （可选）格式化 C# 代码

```bash
dotnet format CUSGA.sln
```

## 开发说明

- 主场景配置在 `project.godot` 的 `run/main_scene`（Godot 使用 UID 引用；当前为 `uid://qwckbjjp11ca`，对应场景文件 `scenes/main_menu_scenes/main_menu.tscn`）。
- 自动加载节点（Autoload）包括：`GlobalEventBus`、`TimeSystem`、`WeatherManager`、`ItemsControl`、`GlobalWarehouse`、`SceneManager`、`ScreenTransitions`。
- `addons/skill_targeting_type_codegen` 会将 C# 枚举同步生成到 `scripts/generated/SkillTargetingType.gd`。

