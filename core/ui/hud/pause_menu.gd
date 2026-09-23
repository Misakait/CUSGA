extends Control

## 局内暂停菜单。
##
## 宿主是 `Main/UI/HUDLayer/HUDRoot`：该节点在局外探索与局内战斗中都不会被释放
## （局内战斗把 `battle.tscn` 作为 Main 的子节点挂载，`current_scene` 仍是 Main），
## 因此一份实例就能覆盖两种状态，不需要新增 Autoload，也不需要在 `battle.tscn`
## 里重复一份（见 .trellis/spec/frontend/state-management.md「局内战斗的 UI 宿主」）。
##
## 本组件只承担三个映射：「继续游戏」与「暂停/恢复」共同映射到 `SceneTree.paused`
## 的开与关，「退出游戏」映射为一次场景切换。它不读写任何玩法状态——继续游戏只是
## 解除全局暂停，不会改写时间、库存或战斗进度；退出游戏也只是换回主菜单场景，
## 不在此处结算或保存任何东西。

## 暂停开关的输入动作名，在 project.godot 中注册并绑定 ESC。
const PAUSE_ACTION: StringName = &"pause_game"

## 退出游戏时切回的主菜单场景路径。
##
## 刻意走 `change_scene_to_file` 而不是 `GlobalEventBus.scene_requested`：
## `SceneManager` 只在主菜单、仓库、商店之间切换，进入 Main 之后它的 `_current_id`
## 仍然停在 `"main_menu"`，此时发 `scene_requested("main_menu")` 会被
## `_on_scene_requested` 的 `scene_id == _current_id` 判据提前吞掉，玩家按「退出游戏」
## 将毫无反应。这条路径与 `main_menu.gd` 进入游戏时使用的
## `change_scene_to_file(Main_scene_path)` 保持对称，进出使用同一套场景语义。
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu_scenes/main_menu.tscn"

## 右上角常驻的暂停键。
@onready var _pause_button: Button = %PauseButton

## 暂停时才显示的整屏浮层，承载遮罩与菜单面板。
@onready var _pause_overlay: Control = %PauseOverlay

## 菜单第一行的「继续游戏」按钮。
@onready var _continue_button: Button = %ContinueButton

## 菜单中的「退出游戏」按钮。
@onready var _exit_button: Button = %ExitButton

## 菜单是否处于展开状态。
##
## 用它而不是直接读 `SceneTree.paused` 作为开关判据：天赋选择界面
## （resources/talents/talent_manager.gd）也会把全局暂停置为 true，两者共用同一个
## 全局开关，必须有本地标志才能区分「菜单开着」与「别的系统正在暂停游戏」。
var _is_menu_open: bool = false

## 本次打开菜单之前，全局是否已经处于暂停状态。
##
## 关闭菜单时只有「暂停由本次打开造成」才由本组件解除，避免把天赋选择等其它系统的
## 暂停一起关掉，让本该停住的界面重新开始运行。
var _was_paused_before_open: bool = false


## 初始化子控件引用，并把暂停键与菜单按钮接入各自流程。
## 返回值：无。
func _ready() -> void:
	# 暂停期间本节点必须继续处理输入与按钮事件，否则菜单弹出后再也关不掉自己。
	# 与天赋选择界面（talent_manager.gd）保持同一约定。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_exit_button.pressed.connect(_on_exit_button_pressed)


## 场景被释放时归还全局暂停状态。
##
## 正常退出走 `_on_exit_button_pressed`，这里只兜住非正常释放（例如外部换场景、
## 编辑器停跑）。没有这层兜底时，Main 在暂停状态下被释放会让下一个场景带着
## `paused = true` 启动，表现为整屏无响应且没有可见原因。
## 返回值：无。
func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _is_menu_open and not _was_paused_before_open:
		tree.paused = false


## 在未处理输入阶段响应暂停开关。
##
## 用 `_unhandled_input` 而不是 `_input`：正在编辑文本或自行处理 ESC 的 UI
## 应当优先消费该事件，菜单只在没人要这个按键时才接管。
## 参数 event：尚未被其它节点消费的输入事件。
## 返回值：无。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PAUSE_ACTION):
		toggle_pause_menu()
		get_viewport().set_input_as_handled()


## 切换暂停菜单的展开状态。
## 返回值：无。
func toggle_pause_menu() -> void:
	if _is_menu_open:
		close_pause_menu()
	else:
		open_pause_menu()


## 展开菜单并暂停游戏。
##
## 重复调用是幂等的：已在展开状态时直接返回，不会重复记录暂停前状态。
## 返回值：无。
func open_pause_menu() -> void:
	if _is_menu_open:
		return

	_is_menu_open = true
	# 先记录原状态再接管暂停，关闭时才能只归还自己造成的改变。
	_was_paused_before_open = get_tree().paused
	get_tree().paused = true
	_pause_overlay.visible = true


## 收起菜单并恢复游戏。
##
## 重复调用是幂等的：未展开时直接返回。
## 返回值：无。
func close_pause_menu() -> void:
	if not _is_menu_open:
		return

	_is_menu_open = false
	_pause_overlay.visible = false
	if not _was_paused_before_open:
		get_tree().paused = false


## 把暂停键的一次点击转发为切换请求。
## 返回值：无。
func _on_pause_button_pressed() -> void:
	toggle_pause_menu()


## 收起菜单并继续游戏。
##
## 与「再按一次暂停键」完全等价，因此直接复用 `close_pause_menu`：暂停的归还判据
## （只解除本次打开造成的暂停）只存在一处，继续游戏与关闭菜单不可能出现两套行为。
## 返回值：无。
func _on_continue_button_pressed() -> void:
	close_pause_menu()


## 退出游戏并回到主菜单。
##
## 换场景前必须由本组件解除全局暂停：Main 被释放后不再有节点负责把它置回 false，
## 主菜单会带着 `paused = true` 启动，表现为整屏无响应。
## 返回值：无。
func _on_exit_button_pressed() -> void:
	# 先把菜单状态收起，避免 Main 释放后残留「开着的菜单」这一本地状态被复用。
	_is_menu_open = false
	_pause_overlay.visible = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
