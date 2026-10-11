# 使用登录菜单替换主菜单并接入四项功能

## Goal

用已有的 `login_menu.tscn` 作为项目启动菜单，给四个菜单按钮接入真实功能，并让玩家可以只用键盘完成选择和确认。

## Background And Confirmed Facts

- `project.godot` 当前启动场景仍由旧主菜单 UID 指向，需改为 `login_menu.tscn`。
- `SceneManager.SCENE_MAP["main_menu"]` 当前指向 `main_menu.tscn`；仓库、新商店和暂停菜单仍使用 `main_menu` 这个场景 ID，因此保留该 ID，只替换它对应的场景路径。
- `login_menu.tscn` 已包含背景、四个 Button、中文标签、未按下和按下纹理，四个 Button 已设置 `toggle_mode = true`，但没有脚本、信号连接或键盘导航逻辑。
- 开始游戏的现有入口是 `res://scenes/Main.tscn`。
- 游戏仓库的现有入口是 `GlobalEventBus.scene_requested.emit("warehouse")`，由 `SceneManager` 切换到 `WarehouseNew.tscn`。
- `scenes/ui_scenes/option_panel.tscn` 与 `scripts/ui_scripts/UIOptionPanel.gd` 已实现设置页和返回信号，可作为登录菜单的设置内容复用。
- 项目输入映射已有 `move_up`（W）和 `move_down`（S）；本菜单还需处理 Enter 确认，不能依赖鼠标操作才能完成流程。

## Requirements

### R1 主菜单替换

项目运行时第一屏必须是 `login_menu.tscn`。所有返回主菜单的现有流程仍使用 `main_menu` 场景 ID，但实际加载登录菜单，避免同时维护两套主菜单行为。

### R2 四项功能

- 「开始游戏」：切换到 `res://scenes/Main.tscn`。
- 「游戏设置」：打开可操作的现有设置页；设置页可以返回登录菜单，返回后焦点和互斥状态仍然有效。
- 「游戏仓库」：通过现有场景事件进入仓库界面；仓库返回主菜单后仍回到登录菜单。
- 「离开游戏」：调用 Godot 的退出流程结束游戏。

### R3 键盘导航

- 菜单显示后四个按钮中恰好有一个获得焦点，默认选择「开始游戏」。
- 按 W 将焦点向上移动，按 S 将焦点向下移动，导航在四个按钮之间循环。
- 按 Enter 确认当前焦点按钮，效果与鼠标点击该按钮一致。
- 鼠标点击仍可使用，并且点击后焦点、按下状态和功能选择保持一致。

### R4 Toggle 互斥与纹理

- 四个按钮保留 Toggle 模式；按钮进入 `button_pressed = true` 时使用场景的 pressed 纹理，未按下时使用 normal 纹理。
- 任意时刻四个按钮最多一个处于按下状态；选择新按钮时必须同步释放其他三个按钮。
- 菜单首次显示、返回菜单和设置页关闭后都不能留下多个按下按钮或无效的焦点。

### R5 UI 合理性与兼容

- 可以调整节点类型、布局和新增控制节点，但保留现有资源风格、中文标签和四项入口。
- 设置页与菜单显示层级不能互相遮挡，按钮在 1280×720 视口下可见且可操作。
- 不改变仓库、商店、暂停菜单已有的业务逻辑；只更新它们在需要时对主菜单路径的兼容引用。

## Acceptance Criteria

- [x] 启动项目首屏加载 `scenes/main_menu_scenes/login_menu.tscn`，不存在主菜单脚本解析或资源加载错误。
- [x] 点击或按 Enter 选择四个按钮时，分别进入 Main、打开设置、进入仓库、退出进程；设置页可返回登录菜单，仓库可返回登录菜单。
- [x] 通过 Godot 真实发送 W、S、Enter，焦点按顺序循环移动并触发当前按钮；鼠标点击也能触发同一功能。
- [x] 通过运行时读取四个按钮的 `button_pressed`，任何时刻按下数量不超过 1；切换选择时 pressed 纹理随状态改变。
- [x] 主菜单与设置页截图中四个入口布局合理、文字完整、没有互相遮挡；运行日志没有本次改动引入的 `SCRIPT ERROR`、`Parse Error` 或 `Failed to load script`。
- [x] 修改完成后重新检查 `git status`，只保留本任务需要的代码、场景、项目配置和任务文档，用户原有未跟踪菜单资源不被回退。

## Out Of Scope

- 不重写 `SceneManager` 的缓存机制，不修改仓库、商店和游戏内暂停菜单的业务规则。
- 不新增第三方插件、字体或图片资源；优先复用当前登录菜单和设置页资源。
- 不改变已有存档格式、输入动作的含义或 Main 场景内玩法逻辑。

## Open Questions

无。开始游戏、设置、仓库和退出的现有代码入口均已在仓库中确认。
