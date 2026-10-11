# 技术设计：登录菜单替换主菜单

## 1. 边界与所有者

- `scenes/main_menu_scenes/login_menu.tscn`：负责登录菜单的视图节点、纹理、标签和设置页实例。
- 新增菜单控制脚本（放在 `core/ui/`）：负责按钮注册、互斥状态、焦点、W/S 导航、Enter 确认以及四个功能入口。它只协调 UI 和场景请求，不保存玩法数据。
- `core/autoloads/SceneManager.gd`：继续以 `main_menu` 作为主菜单稳定 ID，但把该 ID 的路径改为 `login_menu.tscn`。
- `project.godot`：把 `run/main_scene` 改为登录菜单场景 UID/路径对应的启动场景。
- `core/ui/hud/pause_menu.gd`：返回主菜单的硬编码场景路径需与登录菜单保持一致，避免暂停菜单退出后加载旧主菜单。

## 2. 数据流

```text
W/S -> LoginMenuController._unhandled_input -> _select_index(index, true)
Enter/鼠标 -> Button.pressed -> _on_button_pressed(button)
                           -> _select_index(index, true)（释放其他按钮）
                           -> Main / Settings / GlobalEventBus(warehouse) / quit
```

设置页使用已有 `UIOptionPanel` 的 `back_requested` 信号。打开设置时隐藏菜单按钮容器并显示设置页；收到返回信号时恢复菜单并重新聚焦当前按钮。仓库通过现有 SceneManager/事件入口切换；Main 使用 `change_scene_to_file` 进入，不复制仓库或游戏初始化逻辑。

## 3. Toggle 互斥实现

- 四个 Button 全部保留 `toggle_mode = true`，pressed 状态继续由场景样式显示。
- 四项共用 `ButtonGroup`，`allow_unpress = false`，防止原生按钮切换时产生多选。
- 控制器维护有序按钮数组和当前索引。按钮 pressed 信号触发时，先对其他按钮调用 `set_pressed_no_signal(false)`，再用 `set_pressed_no_signal(true)` 固定当前按钮，避免递归信号和中间多选状态。
- 初始化和返回菜单时只通过同一套选择函数设置状态，确保不会出现焦点与 pressed 状态不同步。
- 为避免“点击已按下按钮后变成全未按下”，按钮处理始终把当前选择保持为按下状态；四项菜单必须始终有一个当前选择。

## 4. 键盘导航

- 控制器使用 `_unhandled_input`，只消费 `move_up`、`move_down` 和 `ui_accept`（Enter）的按下事件，避免吞掉 Button 默认的鼠标/键盘处理。
- W/S 使用模运算在四个按钮索引间循环，并调用 `grab_focus()`；焦点改变同时更新 Toggle 选择。
- Enter 调用当前按钮的 `pressed.emit()`，确保鼠标和键盘共用同一条业务路径。

## 5. 兼容与回滚

- 只替换主菜单映射和暂停菜单返回路径，保留 `main_menu` ID，仓库/商店/暂停菜单无需改调用协议。
- 如果登录菜单运行验证失败，可回滚 `project.godot` 启动路径和 `SceneManager`/暂停菜单路径，旧 `main_menu.tscn` 仍在仓库中作为资源，不删除。
- 复用用户现有图片、字体与图标；登录菜单改为全屏 Control，使用 CenterContainer 与 VBoxContainer 居中排列四按钮。按钮尺寸为 360×84，纵向间隔 16；设置页与菜单切换显示。
