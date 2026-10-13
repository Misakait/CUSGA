@tool
extends EditorPlugin

## 注册英文标签 Inspector；定时检查用于捕获原生数组原地编辑。
## 游戏运行逻辑不依赖本编辑器插件。

const Monitor = preload("res://addons/tag_catalog/catalog_monitor.gd")
const Inspector = preload("res://addons/tag_catalog/tag_inspector.gd")

var _monitor: RefCounted
var _inspector: EditorInspectorPlugin
var _poll_timer: Timer


func _enter_tree() -> void:
	_monitor = Monitor.new()
	_inspector = Inspector.new(_monitor)
	add_inspector_plugin(_inspector)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_monitor.refresh)
	add_child(_poll_timer)
	_poll_timer.start()


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
	_inspector = null
	if is_instance_valid(_poll_timer):
		_poll_timer.stop()
		if _monitor != null and _poll_timer.timeout.is_connected(_monitor.refresh):
			_poll_timer.timeout.disconnect(_monitor.refresh)
		_poll_timer.queue_free()
	_poll_timer = null
	if _monitor != null:
		_monitor.dispose()
	_monitor = null
