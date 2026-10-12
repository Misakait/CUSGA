extends RefCounted

## 按键绑定注册表。
##
## 集中声明「哪些输入动作允许玩家改键」「它们的中文显示名与分组」，以及按键事件与
## 存档字典之间的编解码规则。本脚本只有静态函数、不持有任何状态，因此既可以被
## KeyBindingManager（运行时把偏好应用到 InputMap）复用，也可以在编辑器测试里直接
## 调用，不需要 autoload 环境。
##
## 显示名与动作名刻意分离：动作名是写进 user://settings.cfg 的稳定标识，发布后不可
## 修改；显示名只影响界面文案，可以随时调整，不会让玩家已保存的键位失效。

## 本地设置中存放键位偏好的分组名。
## 与 project.godot 的 [input] 段同名，但两者是不同介质：这里是玩家本地偏好，
## project.godot 才是项目默认键位，玩家的改动永远不会写回项目配置。
const SETTINGS_SECTION: String = "input"

## 无法识别键位时显示给玩家的文案（没有键位，或键位格式非法）。
const UNBOUND_TEXT: String = "未绑定"

## 读取设置时用来表示「这个动作还没有保存过键位」的哨兵值。
##
## 不能直接把 null 当作 get_setting 的默认值：SettingsManager 会把它透传给
## ConfigFile.get_value，而该接口在默认值为 null 时会打印一条 C++ 错误
## （"no default was given"），把一次正常的首次运行变成启动报错。空字典是合法类型，
## 又不会被 decode_event 误判成有效记录，因此适合当哨兵。
const MISSING_RECORD: Dictionary = {}

## 可重绑动作清单。
##
## 顺序即面板中的显示顺序；group 相同且相邻的条目会被 UIOptionPanel 归入同一个分组
## 标题。每个元素包含四个键：
##   action  — InputMap 中的动作名，必须与 project.godot 的 [input] 段完全一致。
##   display — 界面上的中文名。
##   group   — 面板中的分组标题。
##   note    — 需要额外说明时显示的次要文案，没有说明时为空字符串（说明必须与真实行为一致）。
##
## 新增输入动作时必须同时改这里和 project.godot，否则
## test_key_binding_settings_contract 的「动作集合双向相等」断言会失败——这正是防止
## 以后新增动作漏进面板的机制。
const REBINDABLE_ACTIONS: Array[Dictionary] = [
	{"action": &"move_up", "display": "向上移动", "group": "移动", "note": ""},
	{"action": &"move_down", "display": "向下移动", "group": "移动", "note": ""},
	{"action": &"move_left", "display": "向左移动", "group": "移动", "note": ""},
	{"action": &"move_right", "display": "向右移动", "group": "移动", "note": ""},
	{"action": &"toggle_inventory", "display": "打开背包", "group": "界面", "note": ""},
	{"action": &"toggle_crafting", "display": "打开合成", "group": "界面", "note": ""},
	{"action": &"open_map", "display": "打开地图", "group": "界面", "note": ""},
	{"action": &"check", "display": "确认", "group": "界面", "note": ""},
	{"action": &"interact_building", "display": "交互建筑", "group": "交互", "note": ""},
	{"action": &"pause_game", "display": "暂停游戏", "group": "交互", "note": ""},
]


## 读取可重绑动作清单。
##
## 返回深拷贝而不是常量本身：常量数组在 GDScript 中并非深度只读，直接交出引用会让
## 调用方有机会改坏这份全局清单。
## @return Array[Dictionary] 每个元素形如 {action, display, group, note}。
static func get_rebindable_actions() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in REBINDABLE_ACTIONS:
		entries.append(entry.duplicate(true))
	return entries


## 读取全部可重绑动作名，顺序与面板显示顺序一致。
## @return Array[StringName] 动作名列表。
static func get_action_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for entry: Dictionary in REBINDABLE_ACTIONS:
		names.append(StringName(entry.get("action", &"")))
	return names


## 判断某个动作是否允许玩家改键。
## @param action 待检查的动作名。
## @return bool 在可重绑清单中返回 true。
static func is_rebindable(action: StringName) -> bool:
	return get_action_names().has(action)


## 读取动作的界面中文名。
## @param action 动作名。
## @return String 中文名；动作不在清单中时回退为动作名本身，便于排查遗漏。
static func get_display_name(action: StringName) -> String:
	var entry: Dictionary = _find_entry(action)
	return String(entry.get("display", String(action)))


## 读取动作在面板中的分组标题。
## @param action 动作名。
## @return String 分组标题；动作不在清单中时回退为空字符串。
static func get_group_name(action: StringName) -> String:
	var entry: Dictionary = _find_entry(action)
	return String(entry.get("group", ""))


## 读取动作的次要说明文案。
## @param action 动作名。
## @return String 说明文案；没有说明时为空字符串。
static func get_note(action: StringName) -> String:
	var entry: Dictionary = _find_entry(action)
	return String(entry.get("note", ""))


## 把一次真实按键事件规范化为可写入 SettingsManager 的字典。
##
## 只接受「非键盘重复（echo）且带有真实键码」的键盘事件：纯修饰键（单独按下 Shift、
## Ctrl、Alt、Meta）没有主键码，绑定它不会产生任何可用的触发条件，因此一并拒绝。
## @param event 待编码的输入事件。
## @return Dictionary 可存储的字典；不可绑定时返回空字典。
static func encode_event(event: InputEvent) -> Dictionary:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or key_event.echo:
		return {}
	# 优先物理键码：WASD 这类操作跟随键位的物理位置，玩家换键盘布局时不会漂移。
	var physical_keycode: int = key_event.physical_keycode
	var keycode: int = 0
	if physical_keycode == 0:
		keycode = key_event.keycode
	if physical_keycode == 0 and keycode == 0:
		return {}
	return {
		"physical_keycode": physical_keycode,
		"keycode": keycode,
		"ctrl": key_event.ctrl_pressed,
		"alt": key_event.alt_pressed,
		"shift": key_event.shift_pressed,
		"meta": key_event.meta_pressed,
	}


## 把存档字典还原为 InputMap 可用的按键模板。
##
## 逐字段做类型校验：任何一个字段类型不对都返回 null，由调用方回退项目默认键位。
## 这样手改坏 user://settings.cfg 只会退化成「键位回到默认」，不会让游戏启动报错。
## @param data 来自 SettingsManager 的原始值。
## @return InputEventKey 合法的按键模板；非法输入返回 null。
static func decode_event(data: Variant) -> InputEventKey:
	if not (data is Dictionary):
		return null

	var stored: Dictionary = data as Dictionary
	var physical_value: Variant = stored.get("physical_keycode", 0)
	var keycode_value: Variant = stored.get("keycode", 0)
	if not _is_keycode_value(physical_value) or not _is_keycode_value(keycode_value):
		return null

	var physical_keycode: int = int(physical_value)
	var keycode: int = int(keycode_value)
	if physical_keycode == 0 and keycode == 0:
		return null

	for modifier_key: String in ["ctrl", "alt", "shift", "meta"]:
		if not (stored.get(modifier_key, false) is bool):
			return null

	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = keycode
	event.ctrl_pressed = bool(stored.get("ctrl", false))
	event.alt_pressed = bool(stored.get("alt", false))
	event.shift_pressed = bool(stored.get("shift", false))
	event.meta_pressed = bool(stored.get("meta", false))
	# InputMap 里存放的是匹配模板而不是一次真实按键，按下与重复标记必须清零，
	# 否则模板只会在「恰好也处于按下状态」时才匹配得上。
	event.pressed = false
	event.echo = false
	return event


## 生成玩家可读的键位文案。
## @param event 待格式化的输入事件。
## @return String 形如 "W"、"Ctrl+S"、"Escape" 的文案；无法识别时返回 UNBOUND_TEXT。
static func format_event_text(event: InputEvent) -> String:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return UNBOUND_TEXT

	var code: int = key_event.physical_keycode
	if code == 0:
		code = key_event.keycode
	if code == 0:
		return UNBOUND_TEXT

	var parts: Array[String] = []
	if key_event.ctrl_pressed:
		parts.append("Ctrl")
	if key_event.alt_pressed:
		parts.append("Alt")
	if key_event.shift_pressed:
		parts.append("Shift")
	if key_event.meta_pressed:
		parts.append("Meta")
	parts.append(OS.get_keycode_string(code))
	return "+".join(PackedStringArray(parts))


## 从本地设置读取某个动作已保存的键位。
##
## settings_source 允许为 null：编辑器测试环境没有 autoload，运行期也可能因为场景
## 装配问题拿不到 SettingsManager，这两种情况都只应退化为「使用项目默认键位」。
## @param settings_source 提供 get_setting 的设置服务，通常是 SettingsManager。
## @param action 动作名。
## @return InputEventKey 已保存的键位；没有保存或记录非法时返回 null。
static func read_saved_event(settings_source: Object, action: StringName) -> InputEventKey:
	if settings_source == null or not settings_source.has_method(&"get_setting"):
		return null

	var stored: Variant = settings_source.call(
		"get_setting", SETTINGS_SECTION, String(action), MISSING_RECORD
	)
	# 取回哨兵本身（或玩家手写的一个空块）说明这个动作还没有保存过键位，属于首次运行的
	# 正常情况，静默回退即可。这里用 typeof 判断而不是 `==`：GDScript 在 `==` 两侧类型
	# 不同时会直接抛「Invalid operands in operator '=='」，而存档被手改成字符串恰恰是
	# 这条路径必须扛住的情况之一。
	if typeof(stored) == TYPE_DICTIONARY and (stored as Dictionary).is_empty():
		return null

	var event: InputEventKey = decode_event(stored)
	if event == null:
		push_warning("按键绑定记录无法解析，已回退默认键位：%s" % String(action))
	return event


## 把某个动作的键位写入本地设置。
## @param settings_source 提供 set_setting 的设置服务。
## @param action 动作名。
## @param event 需要保存的按键事件。
## @return bool 成功写入返回 true；设置服务缺失、事件不可编码或落盘失败返回 false。
static func write_saved_event(
	settings_source: Object, action: StringName, event: InputEventKey
) -> bool:
	if settings_source == null or not settings_source.has_method(&"set_setting"):
		return false

	var encoded: Dictionary = encode_event(event)
	if encoded.is_empty():
		return false
	return bool(settings_source.call("set_setting", SETTINGS_SECTION, String(action), encoded))


## 删除某个动作已保存的键位，使其回到项目默认值。
## @param settings_source 提供 erase_setting 的设置服务。
## @param action 动作名。
## @return bool 删除成功（键本来就不存在也算成功）返回 true。
static func erase_saved_event(settings_source: Object, action: StringName) -> bool:
	if settings_source == null or not settings_source.has_method(&"erase_setting"):
		return false
	return bool(settings_source.call("erase_setting", SETTINGS_SECTION, String(action)))


## 在清单中查找一个动作的完整条目。
## @param action 动作名。
## @return Dictionary 命中的条目；未命中返回空字典。
static func _find_entry(action: StringName) -> Dictionary:
	for entry: Dictionary in REBINDABLE_ACTIONS:
		if StringName(entry.get("action", &"")) == action:
			return entry
	return {}


## 校验存档里的键码字段是否合法。
##
## 接受非负整数，以及手改配置时可能出现的整数值浮点数（例如 87.0）；bool 不是 int，
## 因此 true 这类明显错误的值会被拒绝。
## @param value 待校验的原始值。
## @return bool 合法返回 true。
static func _is_keycode_value(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		var number: float = float(value)
		return is_finite(number) and number >= 0.0 and number == floor(number)
	return false
