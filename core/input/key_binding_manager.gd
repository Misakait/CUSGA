extends Node

## 按键绑定管理器（Autoload 名 KeyBindingManager）。
##
## 职责有三件：① 启动时把玩家保存在 SettingsManager 里的键位应用到全局 InputMap，
## 让偏好先于任何场景的 `_ready()` 生效；② 运行时接收改键请求，校验后只替换该动作的
## 键盘事件并立即落盘；③ 提供「全部恢复默认」与重复键查询。
##
## 它不引用任何 UI 节点，只通过信号广播事实，因此暂停菜单与登录菜单里的同一份设置
## 面板可以共用这一个实例。

## 单个动作的键位发生变化时广播。
## 参数 action：动作名。参数 event：生效后的按键事件。
signal binding_changed(action: StringName, event: InputEvent)

## 全部动作恢复默认键位后广播一次。
signal bindings_reset

## 设置服务节点路径。
##
## 用 NodePath 而不是直接引用 autoload 标识符：编辑器测试环境没有 autoload，
## 直接引用会让脚本在解析阶段就报错。
const SETTINGS_MANAGER_PATH: NodePath = ^"/root/SettingsManager"

## 按键绑定注册表脚本，提供动作清单与键位编解码。
const KEY_BINDING_REGISTRY: GDScript = preload("res://core/input/key_binding_registry.gd")

## 项目默认键位快照：动作名 → Array[InputEvent]。
##
## 在 `_ready()` 里从 InputMap 抓取一次，此后不再变化，作为「恢复默认」的唯一依据。
var _default_events: Dictionary = {}

## 是否已经抓取过项目默认键位。
## 用独立标志而不是判断 `_default_events` 是否为空：动作全部缺失时它也会是空的，
## 那种情况下重复抓取同样没有意义。
var _defaults_captured: bool = false

## 提供 get_setting / set_setting / erase_setting 的设置服务；缺失时为 null。
var _settings_source: Object = null


## 解析设置服务，抓取默认键位快照，并应用玩家已保存的键位。
## @return void 无返回值。
func _ready() -> void:
	_settings_source = get_node_or_null(SETTINGS_MANAGER_PATH)
	if _settings_source == null:
		push_warning(
			"KeyBindingManager: 未找到 %s，本次运行的键位偏好不会被保存。" % SETTINGS_MANAGER_PATH
		)
	capture_project_defaults()
	apply_saved_bindings()


## 抓取项目默认键位快照。
##
## 只在启动阶段有效：那时 InputMap 刚由 project.godot 的 `[input]` 段装配完成，是默认
## 键位唯一可靠的来源，因此脚本里不需要再复制一份键码表。重复调用会被忽略，否则运行期
## 改键之后再次抓取会把玩家的设定误当成默认值。
## @return void 无返回值。
func capture_project_defaults() -> void:
	if _defaults_captured:
		return
	_defaults_captured = true
	for action: StringName in _rebindable_actions():
		if not InputMap.has_action(action):
			push_warning(
				"KeyBindingManager: InputMap 中没有动作 %s，已跳过默认键位快照。" % String(action)
			)
			continue
		_default_events[action] = _duplicate_events(InputMap.action_get_events(action))


## 把 SettingsManager 中保存的键位逐个应用到 InputMap。
##
## 没有保存记录或记录损坏的动作保持项目默认值，因此首次运行与配置文件损坏都只会
## 退化成「用默认键位」，不会中断启动。
## @return void 无返回值。
func apply_saved_bindings() -> void:
	for action: StringName in _rebindable_actions():
		var saved: InputEventKey = KEY_BINDING_REGISTRY.call("read_saved_event", _settings_source, action)
		if saved == null:
			continue
		_apply_event(action, saved)


## 注入设置服务。
##
## 生产环境由 `_ready()` 自动解析；这个入口存在的意义是让编辑器测试在没有 autoload 的
## 环境里也能驱动落盘逻辑，传入 null 表示本次运行不做持久化。
## @param source 提供 get_setting / set_setting / erase_setting 的对象。
## @return void 无返回值。
func set_settings_source(source: Object) -> void:
	_settings_source = source


## 读取某个动作当前真正生效的键盘键位。
## @param action 动作名。
## @return InputEventKey 当前键位；动作不存在或没有键盘事件时返回 null。
func get_binding_event(action: StringName) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			return key_event
	return null


## 读取某个动作的项目默认键盘键位。
## @param action 动作名。
## @return InputEventKey 默认键位；没有快照或快照里没有键盘事件时返回 null。
func get_default_event(action: StringName) -> InputEventKey:
	var events: Array = _default_events.get(action, []) as Array
	for event: InputEvent in events:
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			return key_event
	return null


## 判断某个动作当前生效的键位是否就是项目默认键位。
##
## 面板用它决定这一行要不要显示「恢复默认」按钮：只有被改过的动作才需要这个入口。
## @param action 动作名。
## @return bool 与默认快照一致返回 true；缺少默认快照或动作不存在时也返回 true，
##         因为那种情况下没有可恢复的目标，显示按钮只会误导玩家。
func is_default_binding(action: StringName) -> bool:
	var default_event: InputEventKey = get_default_event(action)
	if default_event == null:
		return true
	var current: InputEventKey = get_binding_event(action)
	if current == null:
		return false
	return _event_signature(current) == _event_signature(default_event)


## 找出当前互相使用了同一个键的全部动作。
##
## 允许同键是刻意设计：两个动作共用一个键都能正常触发，界面负责把它们标红让玩家知情，
## 因此这里只报告事实、不阻止绑定。比较范围仅限可重绑动作之间——把 Godot 内置的
## `ui_*` 动作算进来会误伤「把移动绑到方向键」这类完全正常的诉求。
## @return Array[StringName] 至少与另一个动作重复的动作名；没有重复时为空数组。
func get_conflicting_actions() -> Array[StringName]:
	var actions_by_signature: Dictionary = {}
	for action: StringName in _rebindable_actions():
		var event: InputEventKey = get_binding_event(action)
		if event == null:
			continue
		var signature: String = _event_signature(event)
		var bucket: Array = actions_by_signature.get(signature, []) as Array
		bucket.append(action)
		actions_by_signature[signature] = bucket

	var conflicts: Array[StringName] = []
	for signature: Variant in actions_by_signature.keys():
		var bucket: Array = actions_by_signature[signature] as Array
		if bucket.size() < 2:
			continue
		for action: Variant in bucket:
			conflicts.append(StringName(action))
	return conflicts


## 修改一个动作的键位。
##
## 只替换该动作的键盘事件，保留它上面可能存在的其它事件类型（手柄、鼠标），这样将来
## 给某个动作补手柄绑定时，玩家改键盘不会把它们一起清掉。
## @param action 动作名，必须在可重绑清单中。
## @param event 玩家按下的按键事件。
## @return Dictionary 形如 {ok: bool, reason: String, saved: bool, conflicts: Array}。
##         ok 为 false 时 reason 是可直接展示给玩家的中文原因；saved 为 false 表示
##         本次运行有效但没能写入本地文件，调用方不得宣称已跨重启保存。
func rebind(action: StringName, event: InputEventKey) -> Dictionary:
	var conflicts: Array[StringName] = []
	if not bool(KEY_BINDING_REGISTRY.call("is_rebindable", action)):
		return _failure("该动作不支持改键：%s" % String(action), conflicts)
	if event == null:
		return _failure("没有识别到按键，请重新按下。", conflicts)
	var encoded: Dictionary = KEY_BINDING_REGISTRY.call("encode_event", event)
	if encoded.is_empty():
		return _failure("这个按键不能单独作为绑定，请换一个。", conflicts)
	if not InputMap.has_action(action):
		return _failure("InputMap 中不存在动作 %s。" % String(action), conflicts)

	_apply_event(action, event)
	var saved: bool = bool(
		KEY_BINDING_REGISTRY.call("write_saved_event", _settings_source, action, event)
	)
	binding_changed.emit(action, event)
	return {"ok": true, "reason": "", "saved": saved, "conflicts": get_conflicting_actions()}


## 构造改键失败的统一返回值（四个失败分支共用，保证字段集合一致）。
##
## 失败分支有四种，返回结构必须完全一致，否则调用方要写四遍字段判断；集中在这里也让
## 「失败一定 saved=false」这个不变式只需要维护一次。
## @param reason 可直接展示给玩家的中文原因。
## @param conflicts 当前仍然存在的冲突动作列表。
## @return Dictionary 形如 {ok: false, reason, saved: false, conflicts}。
func _failure(reason: String, conflicts: Array[StringName]) -> Dictionary:
	return {"ok": false, "reason": reason, "saved": false, "conflicts": conflicts}


## 把全部可重绑动作恢复到项目默认键位，并清除已保存的偏好。
##
## 先删记录再还原 InputMap：即使还原过程中某个动作因缺少快照被跳过，也不会留下
## 「文件里还存着玩家设定、运行时却是默认值」这种下次启动才暴露的不一致。
## @return void 无返回值。
func reset_all_to_defaults() -> void:
	for action: StringName in _rebindable_actions():
		KEY_BINDING_REGISTRY.call("erase_saved_event", _settings_source, action)
		_restore_default_events(action)
	bindings_reset.emit()


## 把单个动作恢复为项目默认键位，并清除它的已保存偏好。
##
## 先删记录再还原 InputMap，理由与 reset_all_to_defaults 相同：否则会留下「文件里还存着
## 玩家设定、运行时却是默认值」这种下次启动才暴露的不一致。
## @param action 动作名，必须在可重绑清单中。
## @return bool 成功恢复返回 true；动作不支持改键或没有默认快照时返回 false。
func reset_action_to_default(action: StringName) -> bool:
	if not bool(KEY_BINDING_REGISTRY.call("is_rebindable", action)):
		return false
	if get_default_event(action) == null:
		return false
	KEY_BINDING_REGISTRY.call("erase_saved_event", _settings_source, action)
	_restore_default_events(action)
	binding_changed.emit(action, get_binding_event(action))
	return true


## 把某个动作还原为默认事件集合。
## @param action 动作名。
## @return void 无返回值。
func _restore_default_events(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	var events: Array = _default_events.get(action, []) as Array
	if events.is_empty():
		# 缺少快照时保守处理：宁可保持现状，也不要把这个动作清成没有任何绑定的空动作。
		push_warning("KeyBindingManager: 缺少 %s 的默认键位快照，已保持现状。" % String(action))
		return
	# 这里可以整组清空：快照本身就是完整的默认事件集合，包含可能存在的非键盘事件。
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


## 把单个按键事件写入 InputMap，替换该动作原有的键盘事件。
## @param action 动作名。
## @param event 需要生效的按键事件。
## @return void 无返回值。
func _apply_event(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		push_warning("KeyBindingManager: InputMap 中没有动作 %s，本次改键被忽略。" % String(action))
		return
	# 只清除键盘事件：动作上可能还挂着将来的手柄或鼠标绑定，改键盘不应该把它们抹掉。
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventKey:
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, event)


## 读取可重绑动作名清单。
## @return Array[StringName] 动作名列表，顺序与面板显示顺序一致。
func _rebindable_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for value: Variant in KEY_BINDING_REGISTRY.call("get_action_names"):
		actions.append(StringName(value))
	return actions


## 深拷贝一组输入事件。
##
## InputMap 返回的事件是它自己持有的实例，直接存进快照会让后续 `action_erase_events`
## 影响到快照本身，因此必须复制一份。
## @param events 待复制的输入事件数组。
## @return Array[InputEvent] 复制后的事件数组。
func _duplicate_events(events: Array[InputEvent]) -> Array[InputEvent]:
	var copies: Array[InputEvent] = []
	for event: InputEvent in events:
		copies.append(event.duplicate())
	return copies


## 生成用于比较「是否同一个键」的签名。
##
## 物理键码优先、键码兜底，再拼上四个修饰键：同一个字母键配合不同修饰键是两个不同的
## 绑定，因此不能只比键码。
## @param event 待比较的键盘事件。
## @return String 该事件对应的唯一签名。
func _event_signature(event: InputEventKey) -> String:
	var code: int = event.physical_keycode
	if code == 0:
		code = event.keycode
	return "%d|%s|%s|%s|%s" % [
		code,
		str(event.ctrl_pressed),
		str(event.alt_pressed),
		str(event.shift_pressed),
		str(event.meta_pressed),
	]
