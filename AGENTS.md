# CUSGA 项目 AI 核心规则

> **执行任何命令或修改代码前必须阅读本文件。**
> 如果项目根目录存在 `agent.local.md`，还必须读取该文件；其中的本地协作约束优先于本文件。

## 1. 项目技术基线

- 本项目使用 **Godot 4.7.1 + GDScript**。
- 当前仓库没有 `.cs`、`.csproj` 或 `.sln` 文件，不需要 .NET SDK，也没有 C# 编译步骤。
- 不运行 `dotnet build`、`dotnet test`、`dotnet run`、`dotnet format` 或 `godot-mono`。
- 不安装、运行或重新建立 GitNexus / CodeGraph 索引。这两类工具不支持本项目使用的 GDScript，不能作为依赖与影响分析依据。
- 查找 GDScript、场景和资源引用时，使用 `rg`、文件读取工具以及 Godot 编辑器运行验证。

## 2. Godot 验证规则

- 涉及 `.gd`、`.tscn`、`.tres`、autoload 或运行时集成的改动，必须通过已打开的 **Godot 4.7.1 编辑器 MCP**（`addons/godot_ai`）验证。
- 验证前先用 `editor_state` 或 `session_manage(op="list")` 确认编辑器已打开并加载 CUSGA。没有连接时，要求用户打开编辑器；不得改用旧版命令行 Godot。
- 测试结束后只调用 `project_manage(op="stop")` 停止运行中的游戏，**不得关闭 Godot 编辑器**。

| 验证目标 | 编辑器 MCP 操作 |
|---|---|
| 刷新新增或修改的 GDScript | `filesystem_manage(op="scan")` |
| 运行 `tests/godot/` 下的测试 | `test_run(suite=..., test_name=...)` |
| 冒烟测试指定场景 | `project_run(mode="custom", scene="res://X.tscn")`，读取 `logs_read(source="game")`，最后 `project_manage(op="stop")` |
| 检查运行时状态 | `game_eval(code=...)` 或 `game_command` |
| 检查 UI 画面 | `editor_screenshot(source="game")` |

- 修改场景或运行流程时，优先冒烟测试被修改的场景，通常还要测试主场景。
- `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 和本次改动引入的资源加载错误都是阻塞问题。
- 资源 UID 警告只有在涉及本次修改文件时才视为阻塞问题。
- `--check-only --script` 和直接 `--script` 不能正确加载项目 autoload，不得作为通过或失败的判断依据。
- Godot 编辑器可能改写版本控制文件。验证结束后必须重新运行 `git status`，只保留本次任务需要的改动，不得覆盖用户已有改动。

## 3. 文档与注释规则

- 公共类、公共方法和公共函数必须使用 GDScript 文档注释 `##`，并明确说明参数和返回值。
- 复杂、非直观或有顺序要求的逻辑必须添加行内注释。
- 注释必须解释“为什么这样做”，不要重复代码表面行为。
- 所有代码注释使用中文。
- 不为了缩短代码而删除保障理解所必需的说明。

## 4. GDScript 依赖检查

- 修改脚本前，使用 `rg` 查找脚本路径、`class_name`、方法名、信号名和节点路径在 `.gd`、`.tscn`、`.tres`、`project.godot` 中的引用。
- 动态调用（`call`、`has_method`、信号名字符串）无法靠静态搜索完整证明安全，必须补充对应的 Godot 运行时验证。
- 重命名脚本、节点、方法、信号或资源字段时，必须同时检查场景序列化字段和资源引用，不能只修改脚本中的文本。
