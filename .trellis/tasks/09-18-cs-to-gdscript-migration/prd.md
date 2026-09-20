# C# 全量迁移 GDScript

## Goal

按照 cs迁移gds要求.md 分阶段将项目自有 C# 游戏代码等价迁移为纯 GDScript，并迁移全部引用与验证运行行为

## Requirements

- 全面盘点项目自有 C#、GDScript、场景、Resource、Autoload、工程文件及跨语言引用。
- 按依赖顺序分阶段迁移，第一阶段优先处理可独立验证的局外长按交互模块。
- 迁移必须保留原有公开属性、信号语义、节点路径、行动值换算、取消行为和完成回调时序。
- 每个阶段必须同步更新场景、Resource、测试及旧脚本引用；未完成迁移前不得删除剩余 C#。
- 最终阶段才清理项目自有 `.cs`、`.csproj`、`.sln` 和 C# 项目特性；第三方插件代码不在本任务删除范围内。
- 每阶段使用 GodotAI MCP 做脚本读取、场景保存、测试运行和日志检查；发现脚本错误、资源加载错误或 C# 编译错误必须先修复。

## Acceptance Criteria

- [ ] 迁移分析记录 200 个项目 C# 文件（排除 `.godot` 临时产物和第三方插件）及主要依赖分层。
- [ ] 第一阶段长按控制器与圆环指示器由 GDScript 提供等价实现，主场景和 Godot 测试不再引用对应 C# 脚本。
- [ ] 第一阶段保留零行动值即时完成、正行动值按 `cost / 10.0` 等待、取消不回调、圆环目标锚定和场景退出清理行为。
- [ ] 迁移后通过脚本解析、场景加载、聚焦测试及项目启动检查。
- [ ] 后续阶段完成后，全项目无项目自有 C# 运行时引用；残留第三方 C# 依赖有明确说明。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
