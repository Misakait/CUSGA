# Minimal Feature Start

在 CUSGA 开始新功能前使用本指南。目标是只加载当前 GDScript 代码能够证明的规则，并保持改动范围最小。

## 创建任务

不要静默创建 Trellis 任务，先取得用户同意。

- 只影响单个系统的小功能通常只需要 `prd.md`。
- 跨多个系统或涉及架构调整的功能需要 `prd.md`、`design.md` 和 `implement.md`。

## 第一次扫描

先判断功能范围：

- 核心玩法、组件或资源：读取 `backend` 的目录、玩法、资源、测试和质量规范。
- UI、场景或输入：读取 `frontend` 的目录、组件、状态、类型安全和质量规范。
- 跨层流程：同时读取相关 backend/frontend 规范，并从实际场景入口追踪到 Model、Controller 和 View。

本项目是纯 GDScript。使用 `rg` 和文件读取工具查找 `.gd`、`.tscn`、`.tres` 与 `project.godot` 的引用；不要安装或使用 GitNexus / CodeGraph。

## 修改前

- 搜索目标脚本路径、`class_name`、方法、信号、节点路径和序列化字段的全部引用。
- 查看相关场景和资源，确认动态调用与节点连接不能仅靠静态搜索判断。
- 选择能够覆盖真实调用链的最小 Godot 编辑器测试：有对应测试时用 `test_run`，否则用 `project_run` 冒烟测试。
- 保留协作者已有改动。若用户只要求检查或规划，不修改文件。

## 最小实现形状

- 新数据配置：复用现有 GDScript `Resource` 和 `.tres` 结构。
- 新核心规则：放在已有 `core/<system>/` 或 `entities/components/` 所属模块。
- 新 UI 流程：View 只显示状态与上报意图，Controller 调用 Model 修改数据。
- 新地图或战斗行为：沿用现有状态机、信号顺序和资源协议。
- 除非任务明确要求并说明现有扩展点无法承载，否则不新增框架、数据库、全局单例、测试框架或通用架构层。

## 最小验证

- 新增或修改脚本：`filesystem_manage(op="scan")`。
- 数据、组件或算法：对应的 `test_run(suite=..., test_name=...)`。
- 场景或运行时集成：`project_run` + `logs_read(source="game")`，最后 `project_manage(op="stop")`。
- UI：在运行时验证交互，并使用 `editor_screenshot(source="game")` 检查画面。
- 主流程：从主菜单进入游戏，确认没有新的脚本或资源加载错误。

测试只停止正在运行的游戏，不关闭 Godot 编辑器。
