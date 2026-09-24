# Quality Guidelines

本规范适用于当前 GDScript 代码库。

## 风格

- GDScript 使用制表符缩进、LF 换行，并保留文件末尾换行。
- 类名、脚本路径、节点名和序列化字段沿用所在模块的现有命名方式；修改公开名称前先检查场景与资源引用。
- 能明确类型时使用类型标注；从 `Dictionary`、动态属性或 `Array` 取得 `Variant` 时，不要用可能触发不安全推断的 `:=`。
- 可选节点使用 `get_node_or_null`，跨动态边界调用前使用 `has_method`、`has_signal`、`is_instance_valid` 等守卫。
- Model 只保存数据和业务规则，不直接操作 UI 节点；View 根据 Model 状态显示，Controller 解释输入并调度两者。

## 文档与注释

- 公共类、公共方法和公共函数使用 `##` 文档注释。
- 文档注释必须说明参数、返回值和重要前置条件。
- 复杂算法、信号顺序、缓存生命周期和兼容协议需要中文行内注释，说明为什么需要该设计。
- 不添加只复述下一行代码的注释。

## 依赖与状态安全

- 修改前使用 `rg` 搜索脚本路径、`class_name`、方法、信号、节点路径和资源字段在 `.gd`、`.tscn`、`.tres`、`project.godot` 中的引用。
- GitNexus 和 CodeGraph 不支持本项目的 GDScript，不能用于本项目的影响分析，也不要重新安装或建立索引。
- 修改状态前先完成合法性检查。涉及背包、装备、生命、能量或缓存时，保持现有对象身份和信号顺序。
- 动态调用和场景连接不能只靠文本搜索证明安全，必须通过相应测试或真实场景运行验证。
- 自动生成文件只允许由对应生成流程修改；如果其源文件已经退役，应先确认生成器的当前兼容行为。

## 验证

- 验证前确认 Godot 4.7.1 编辑器已打开并加载 CUSGA。
- 新增或修改脚本后执行 `filesystem_manage(op="scan")`。
- 有对应测试时运行聚焦的 `test_run(suite=..., test_name=...)`。
- 场景、autoload 或运行流程改动使用 `project_run`、`logs_read(source="game")` 和 `project_manage(op="stop")` 冒烟测试。
- UI 改动还要使用 `editor_screenshot(source="game")` 检查画面。
- `SCRIPT ERROR`、`Parse Error`、`Failed to load script` 和本次改动引入的资源加载错误必须处理。
- 测试结束后停止游戏，但不得关闭 Godot 编辑器。
