# 实现计划：登录菜单替换主菜单

## 顺序清单

1. 使用 `trellis-before-dev` 读取前端规范并核对菜单控制器、节点路径、输入动作和资源引用。
2. 新增登录菜单控制脚本，声明中文文档注释，连接四个 Button，维护焦点和 Toggle 互斥。
3. 修改 `login_menu.tscn`：挂载控制脚本、补充设置页实例/显示层级和必要的布局约束；保持现有按钮纹理与标签。
4. 修改 `SceneManager.gd`、`project.godot` 和 `pause_menu.gd`，让主菜单 ID 与返回路径加载登录菜单。
5. 用 `rg` 重新检查主菜单路径、节点名、信号名和入口引用，确认旧主菜单调用不会漏改。
6. 通过 Godot 编辑器 MCP 扫描文件，运行登录菜单冒烟测试；读取日志和截图。
7. 在运行中的 Godot 游戏内发送 W、S、Enter，检查焦点、四个 `button_pressed` 状态、设置返回、仓库返回、暂停返回和退出行为。
8. 运行最小相关测试或场景验证，停止运行中的游戏但不关闭编辑器；重新读取 `git status`，确认无关改动未被覆盖。

## 验证命令与门槛

- 静态检查：`rg` 查找 `main_menu.tscn`、`login_menu.tscn`、`scene_requested`、四个 Button 节点名和 `option_panel` 的全部引用。
- Godot MCP：`session_manage(op="list")` 或 `editor_state` 确认编辑器加载本项目；`filesystem_manage(op="scan")` 刷新脚本和场景。
- 冒烟：`project_run(mode="custom", scene="res://scenes/main_menu_scenes/login_menu.tscn")`，读取 `logs_read(source="game")` 和 `editor_screenshot(source="game")`。
- 运行时：用 `game_eval` 读取四个按钮的 `button_pressed`、当前焦点和菜单可见性；用 `game_manage` 输入事件覆盖 W、S、Enter、设置返回、仓库返回和暂停返回。
- 收尾：只调用 `project_manage(op="stop")` 停止游戏；不得关闭 Godot 编辑器。若出现脚本解析错误、场景加载失败或本次改动引入资源错误，必须先修复再完成任务。

## 风险与回滚点

- `login_menu.tscn` 是用户当前未跟踪资源：编辑前保存其现有节点和资源引用，若需调整只做最小挂载和布局变更。
- `project.godot` 当前已有用户改动：只替换启动场景字段，验证差异后保留其他改动。
- `SceneManager` 使用缓存并保留 `main_menu` ID：不重命名 ID，避免仓库和商店回退流程失效。
- 设置页是可复用场景，若与 Node2D 菜单布局冲突，优先新增全屏 `CanvasLayer`/`Control` 容器，不把设置逻辑复制到菜单脚本。
