extends Control

## 玩家生命条视图。
##
## 视图只读取生命组件的稳定属性和信号，不参与生命上限、伤害或恢复结算。

## GameplayPort 节点路径；场景必须提供，运行时不应动态修改。
@export var GameplayPortPath: NodePath

## 提供玩家生命组件的 GameplayPort；兼容现有 C# 与后续 GDScript 实现。
var _gameplay_port: Node = null
## 当前绑定的生命组件；只要求 ValueChanged、CurrentValue 与 MaxValue 协议。
var _health: Node = null
## 展示当前值与上限比例的进度条。
var _health_bar: ProgressBar = null
## 展示“当前值 / 上限”文本的标签。
var _health_label: Label = null


## 解析场景节点，并绑定 GameplayPort 提供的玩家生命组件。
## 返回值：无。
func _ready() -> void:
	if GameplayPortPath.is_empty():
		push_error("HealthBarUI.GameplayPortPath 未设置")
		return
	_health_bar = get_node("%HealthBar") as ProgressBar
	_health_label = get_node("%HealthLabel") as Label
	_gameplay_port = get_node(GameplayPortPath) as Node
	Bind(_gameplay_port.get("PlayerHealth") as Node)


## 绑定生命组件，并立即用当前值刷新视图。
## 参数 health：提供 ValueChanged、CurrentValue 与 MaxValue 的生命组件。
## 返回值：无。
func Bind(health: Node) -> void:
	if health == null:
		push_error("HealthBarUI.Bind 收到空生命组件。")
		return
	if _health == health:
		return
	_unbind()
	_health = health
	var callback := Callable(self, "_on_health_changed")
	if _health.has_signal(&"ValueChanged") and not _health.is_connected(&"ValueChanged", callback):
		_health.connect(&"ValueChanged", callback)
	_refresh(int(_health.get("CurrentValue")), int(_health.get("MaxValue")))


## 退出场景时解除外部生命组件信号。
## 返回值：无。
func _exit_tree() -> void:
	_unbind()


## 解除当前生命组件的变化信号。
func _unbind() -> void:
	if _health == null:
		return
	var callback := Callable(self, "_on_health_changed")
	if _health.has_signal(&"ValueChanged") and _health.is_connected(&"ValueChanged", callback):
		_health.disconnect(&"ValueChanged", callback)
	_health = null


## 响应生命组件变化并同步视图。
## 参数 current_value：变化后的当前生命值。
## 参数 max_value：变化后的生命上限。
func _on_health_changed(current_value: int, max_value: int) -> void:
	_refresh(current_value, max_value)


## 把权威生命值写入进度条和文本。
## 参数 current_value：需要展示的当前生命值。
## 参数 max_value：需要展示的生命上限。
func _refresh(current_value: int, max_value: int) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current_value
	_health_label.text = "%d / %d" % [current_value, max_value]
