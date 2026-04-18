extends Node
class_name HoverTooltipComponent

# ==========================================
# 悬停提示框触发组件 (Hover Tooltip Component)
# ==========================================
# 挂载在需要显示详细描述的节点下（如卡牌、怪物等）。
# 自动寻找父节点的碰撞区域或直接接收配置的信号，触发全屏唯一的 TooltipPanel。
# 遵循组件化开发规范。
# ==========================================

@export_category("提示框内容")
## 提示框显示的标题内容
@export var tooltip_title: String = "未命名"
## 提示框显示的详细描述内容，支持多行
@export_multiline var tooltip_description: String = "暂无描述"

@export_category("触发设置")
## 如果勾选，组件会在 ready 时自动寻找父节点的 Area2D 或 Control 节点，并连接鼠标悬停信号
@export var auto_connect_parent: bool = true

# ==========================================
# 内部引用
# ==========================================
## 全局提示框节点的引用（通常挂载在场景的 UI 层下，路径可通过组寻找或单例注册）
var _tooltip_panel: TooltipPanel = null

func _ready() -> void:
	# 延迟初始化，等待场景加载完毕后寻找唯一的 TooltipPanel
	call_deferred("_find_tooltip_panel")

	if auto_connect_parent:
		_setup_signals()

## 在场景中寻找 TooltipPanel 实例。
func _find_tooltip_panel() -> void:
	# 方案1：通过组名寻找 (推荐在 TooltipPanel 节点上添加 "tooltip_panel" 分组)
	var panels = get_tree().get_nodes_in_group("tooltip_panel")
	if panels.size() > 0:
		_tooltip_panel = panels[0] as TooltipPanel
	else:
		# 方案2：回退方案，遍历寻找（不太推荐，仅供兜底）
		var ui_node = get_tree().current_scene.get_node_or_null("UI")
		if ui_node:
			_tooltip_panel = ui_node.get_node_or_null("TooltipPanel") as TooltipPanel

## 自动连接父节点的相关鼠标信号
func _setup_signals() -> void:
	var parent = get_parent()
	if not parent:
		return

	# 如果父节点是 Control (UI 节点)
	if parent is Control:
		if not parent.mouse_entered.is_connected(_on_mouse_entered):
			parent.mouse_entered.connect(_on_mouse_entered)
		if not parent.mouse_exited.is_connected(_on_mouse_exited):
			parent.mouse_exited.connect(_on_mouse_exited)
		return

	# 如果父节点不是 Control，但它有 Area2D 子节点（2D物理节点）
	var area = parent.get_node_or_null("Area2D")
	if area is Area2D:
		if not area.mouse_entered.is_connected(_on_mouse_entered):
			area.mouse_entered.connect(_on_mouse_entered)
		if not area.mouse_exited.is_connected(_on_mouse_exited):
			area.mouse_exited.connect(_on_mouse_exited)
		return

	# 如果父节点本身就是 Area2D
	if parent is Area2D:
		if not parent.mouse_entered.is_connected(_on_mouse_entered):
			parent.mouse_entered.connect(_on_mouse_entered)
		if not parent.mouse_exited.is_connected(_on_mouse_exited):
			parent.mouse_exited.connect(_on_mouse_exited)
		return

	# 针对特定脚本的自定义信号兼容（例如卡牌脚本 SkillCard 可能自定义了 hovered 信号）
	if parent.has_signal("hovered") and parent.has_signal("hovered_off"):
		if not parent.hovered.is_connected(_on_custom_hovered):
			parent.hovered.connect(_on_custom_hovered)
		if not parent.hovered_off.is_connected(_on_custom_hovered_off):
			parent.hovered_off.connect(_on_custom_hovered_off)
		return

## 对外接口：手动更新提示内容（适用于属性动态变化的怪物或卡牌）
func update_tooltip_content(new_title: String, new_description: String) -> void:
	tooltip_title = new_title
	tooltip_description = new_description

	# 如果当前正在显示此组件的提示，立即刷新
	if _tooltip_panel and _tooltip_panel._is_visible:
		_tooltip_panel.show_tooltip(tooltip_title, tooltip_description)

# ==========================================
# 信号回调区
# ==========================================

func _on_mouse_entered() -> void:
	if _tooltip_panel:
		_tooltip_panel.show_tooltip(tooltip_title, tooltip_description)

func _on_mouse_exited() -> void:
	if _tooltip_panel:
		_tooltip_panel.hide_tooltip()

func _on_custom_hovered(_node) -> void:
	_on_mouse_entered()

func _on_custom_hovered_off(_node) -> void:
	_on_mouse_exited()
