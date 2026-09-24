extends Node

## 跨运行存档层的唯一权威节点（Autoload 第一项）。
##
## 职责边界（为什么这样切）：
## - 本节点只做四件事：文件生命周期（读 / 原子写 / 备份 / 版本）、参与者注册表与协议校验、
##   `global` / `run` 作用域分流、变更信号订阅与合并延迟落盘。
## - 它**不认识**任何玩法数据：`data.global.<save_key>` 的内部结构完全由参与者自己决定。
##   这样新增一个存档对象只需要新增一个参与者，不需要改存档层。
##
## 为什么必须注册成 `[autoload]` 的第一项：参与者要在自己的 `_ready()` 里注册，而注册会
## **同步**把存档分发下去（见 `register_participant`）。若 `SaveManager` 排在参与者之后，
## `register_participant` 就会走「尚未加载完成」的兜底路径退化成延迟分发，`Main.tscn` 的
## `RunStartInitializer` 会在存档生效**之前**就把带入栏消费掉，玩家上次选好的带入物品会
## 静默消失且日志里没有任何错误。该顺序由契约测试锁定。
##
## 为什么读档分发不用 `call_deferred()`：同上——延迟一拍正好错过带入栏的消费时机。
##
## 为什么不用 `Timer` 做防抖：`Timer` 受 `get_tree().paused` 影响，而存档必须对暂停免疫
## （玩家可能暂停着整理仓库然后直接关窗）。本节点自己设 `PROCESS_MODE_ALWAYS` 并用
## `_process` 计时。
##
## 为什么偏好不搬到这里：`SettingsManager` 继续只做**可丢弃的偏好**（操作模式、反馈强度）。
## 偏好读坏了应当无痛回退默认值，存档读坏了必须保留现场并告警——两者的正确行为不同，
## 混在一个 `ConfigFile` 里会让备份与恢复策略互相牵制。

## 默认存档目录；`user://` 在导出后指向用户的持久化目录。
##
## 这只是 `DEFAULT_SAVE_FILE_PATH` 的父目录。真正要写入的目录由 `get_save_directory()`
## 从 `SaveFilePath` 推导——见该方法的说明。
const SAVE_DIRECTORY: String = "user://save"

## 默认存档文件路径。测试通过覆写 `SaveFilePath` 指到临时路径，避免污染真实存档。
const DEFAULT_SAVE_FILE_PATH: String = "user://save/game_save.json"

## 上一次成功写入的备份后缀。
const BACKUP_SUFFIX: String = ".bak"

## 原子写入的中间文件后缀；正常情况下不存在。
const TEMP_SUFFIX: String = ".tmp"

## 主档损坏时保留现场的后缀。
##
## 为什么不把损坏内容写进 `.bak`：`.bak` 的意义是「上一份**好**档」，是主档损坏时唯一的
## 自动恢复来源；把损坏内容盖上去正好毁掉这条恢复路径。因此损坏内容另存 `.corrupt`。
const CORRUPT_SUFFIX: String = ".corrupt"

## 存档格式版本。结构发生不兼容变化时 +1，并在此处补迁移逻辑。
const FORMAT_VERSION: int = 1

## 局外（跨运行）作用域：写进主存档的 `data.global`。
const SCOPE_GLOBAL: String = "global"

## 局内（单局）作用域：写进主存档的 `data.run`，不跨运行保留。
const SCOPE_RUN: String = "run"

## 变更后延迟落盘的秒数。
##
## 为什么需要防抖：拖拽 / 批量移动物品会在连续多帧里持续发出库存变化信号，逐次落盘会变成
## 每帧一次磁盘写入。
const SAVE_DEBOUNCE_SECONDS: float = 0.5

## 参与者必须实现的完整协议方法名。注册期逐个校验，把协议错误暴露在启动期，
## 而不是等到玩家关窗存档时才发现少了个方法。
const PARTICIPANT_METHODS: Array[String] = [
	"save_key",
	"save_scope",
	"save_change_signals",
	"capture_save_data",
	"apply_save_data",
]

## 存档文件路径。测试可覆写为临时路径（如 `user://test_save/save.json`）。
@export var SaveFilePath: String = DEFAULT_SAVE_FILE_PATH

## key → 参与者节点。
var _participants: Dictionary = {}

## 存档是否已经从磁盘读过（读过才允许注册时即时分发）。
var _loaded: bool = false

## 内存中的存档内容，形如 {"global": Dictionary, "run": Dictionary}。
var _loaded_data: Dictionary = {}

## 是否存在一份可用的存档（主档或 `.bak` 恢复出来的都算）。
var _has_valid_save: bool = false

## 最近一次读档失败的原因；为空表示没有失败。
var _last_load_error: String = ""

## 是否有待落盘的变更。
var _dirty: bool = false

## 距离首次变更累积的秒数，用于防抖。
var _dirty_elapsed: float = 0.0

## 是否正在分发存档。分发期间到来的变更请求被**丢弃**而不是延迟——它们的语义是
## 「读档造成的回声」，落盘只会把同一份内容再写一次。
var _is_applying: bool = false

## 已经告警过的未知参与者键，避免每次落盘都重复刷同一条警告。
var _warned_unknown_keys: Dictionary = {}

## 进程内成功写入的次数。
##
## 存在的理由：防抖与「分发期间不回声落盘」这两条行为只能靠「实际写了几次」来验证，
## 而在同一次运行内比较文件内容无法区分「写了一次相同内容」与「压根没写」。运行期也能
## 用它确认自动存档确实发生过。
var _successful_writes: int = 0


## 设置进程模式、读取存档。
##
## 只把文件读进内存，**不在此处分发**——分发交给 `register_participant()`，使每个参与者
## 在自己的 `_ready()` 里同步拿到数据。详见类注释里的时序说明。
##
## @return 无返回值。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()


## 结算待落盘的变更，并在退出时兜底写档。
##
## `NOTIFICATION_EXIT_TREE` 覆盖编辑器「停止运行」与异常退出这两条不触发
## `WM_CLOSE_REQUEST` 的路径；写档是幂等的，重复触发只是多写一次相同内容。
##
## @param what 通知类型。
## @return 无返回值。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_now()


## 推进防抖计时并在稳定后落盘一次。
##
## 为什么用自己的 `_process` 而不是 `Timer`：见类注释。
##
## @param delta 距上一帧的秒数。
## @return 无返回值。
func _process(delta: float) -> void:
	if not _dirty:
		_dirty_elapsed = 0.0
		return

	_dirty_elapsed += delta
	if _dirty_elapsed >= SAVE_DEBOUNCE_SECONDS:
		save_now()


# ── 公开查询面 ───────────────────────────────────────────────────────────

## 返回存档主文件路径。
##
## @return `user://` 形式的绝对路径。
func get_save_file_path() -> String:
	return SaveFilePath


## 返回备份文件路径。
##
## @return 主文件路径加 `.bak`。
func get_backup_file_path() -> String:
	return SaveFilePath + BACKUP_SUFFIX


## 返回临时文件路径。
##
## @return 主文件路径加 `.tmp`。
func get_temp_file_path() -> String:
	return SaveFilePath + TEMP_SUFFIX


## 返回损坏现场文件的路径。
##
## @return 主文件路径加 `.corrupt`。
func get_corrupt_file_path() -> String:
	return SaveFilePath + CORRUPT_SUFFIX


## 返回本次实际要写入的目录。
##
## 为什么从 `SaveFilePath` 推导而不是直接用 `SAVE_DIRECTORY` 常量：`SaveFilePath` 可以被覆写
## （测试用临时目录，将来的多存档槽会指向不同目录），此时常量指向的目录并不是真正要写的
## 目录——在那里建目录、往别处写文件，结果是写入静默失败而目录却建了一堆空壳。
##
## @return `SaveFilePath` 的父目录。
func get_save_directory() -> String:
	return SaveFilePath.get_base_dir()


## 判断是否存在一份可用存档。
##
## @return 主档或 `.bak` 成功读出过内容时为 true；从未有过存档时为 false。
func has_save() -> bool:
	return _has_valid_save


## 返回最近一次读档失败的原因。
##
## @return 失败原因；没有失败时为空字符串。
func get_last_load_error() -> String:
	return _last_load_error


## 返回已注册的参与者键列表（按注册顺序）。
##
## @return 键名数组，供测试与运行期排查使用。
func get_registered_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in _participants:
		keys.append(String(key))
	return keys


## 判断某个键是否已注册。
##
## @param key 参与者键名。
## @return 已注册时为 true。
func is_registered(key: String) -> bool:
	return _participants.has(key)


## 返回内存中的存档内容副本。
##
## @return {"global": Dictionary, "run": Dictionary} 的深拷贝。
func get_loaded_data() -> Dictionary:
	return _loaded_data.duplicate(true)


## 返回进程内成功写入存档的次数。
##
## @return 成功写入次数；只增不减，用于验证防抖与回声抑制。
func get_successful_write_count() -> int:
	return _successful_writes


# ── 注册与分发 ───────────────────────────────────────────────────────────

## 注册一个存档参与者，并在存档已加载时**立即**把它的数据分发下去。
##
## 同步分发是刻意的：参与者通常在自己的 `_ready()` 里调用本方法，同步分发保证
## 「`_ready()` 返回时自身状态已经是存档内容」，从而让 `Main.tscn` 之后才 ready 的
## `RunStartInitializer` 读到正确的带入栏。若在 `_ready()` 阶段就退化成延迟分发，
## 带入栏会被开局流程当成空的消费掉。
##
## 注册对「存档尚未加载」也做了兜底（仅记录，等 `load_from_disk()` 后补发），
## 因此即使 `[autoload]` 顺序被误改也不会丢档，只是退回延迟分发语义。
##
## @param participant 实现 `PARTICIPANT_METHODS` 全部方法的 Node。
## @return 协议校验通过并成功注册时为 true。
func register_participant(participant: Node) -> bool:
	if participant == null or not is_instance_valid(participant):
		push_error("SaveManager: 拒绝注册空的参与者。")
		return false

	var missing: Array[String] = []
	for method_name: String in PARTICIPANT_METHODS:
		if not participant.has_method(method_name):
			missing.append(method_name)
	if not missing.is_empty():
		push_error(
			"SaveManager: 参与者 %s 缺少存档协议方法 %s，已拒绝注册。"
			% [_describe_participant(participant), ", ".join(missing)]
		)
		return false

	var key: String = String(participant.call("save_key"))
	if key.is_empty():
		push_error(
			"SaveManager: 参与者 %s 的 save_key() 为空，已拒绝注册。"
			% _describe_participant(participant)
		)
		return false

	var scope: String = String(participant.call("save_scope"))
	if scope != SCOPE_GLOBAL and scope != SCOPE_RUN:
		push_error(
			"SaveManager: 参与者 %s 的 save_scope() 为 %s，只接受 %s 或 %s。"
			% [_describe_participant(participant), scope, SCOPE_GLOBAL, SCOPE_RUN]
		)
		return false

	if _participants.has(key):
		# 重复注册是允许的：将来每局重建的 run 参与者需要在新实例上重新注册。
		# 但必须留下痕迹，否则「两个 autoload 抢同一个 key」这种配置错误会静默互相覆盖。
		push_warning("SaveManager: 键 %s 已被注册，本次注册将替换原参与者。" % key)
		_unsubscribe_participant(_participants[key])

	_participants[key] = participant
	_subscribe_participant(participant)

	# 注册即应用：存档已加载时同步补发，避免错过调用方的初始化时机。
	if _loaded:
		_apply_to_participant(participant, key)

	return true


## 订阅参与者声明的变更信号，用于自动存档。
##
## @param participant 已通过协议校验的参与者。
## @return 无返回值。
func _subscribe_participant(participant: Node) -> void:
	var signals_raw: Variant = participant.call("save_change_signals")
	if not (signals_raw is Array):
		return

	var callback: Callable = Callable(self, "_on_participant_changed")
	for signal_raw: Variant in signals_raw:
		var signal_name: StringName = StringName(signal_raw)
		if signal_name.is_empty():
			continue
		if not participant.has_signal(signal_name):
			push_warning(
				"SaveManager: 参与者 %s 声明了不存在的信号 %s，该触发点不会自动存档。"
				% [_describe_participant(participant), signal_name]
			)
			continue
		if participant.is_connected(signal_name, callback):
			continue
		participant.connect(signal_name, callback)


## 断开某个参与者此前声明的变更信号。
##
## @param participant 已被替换的参与者。
## @return 无返回值。
func _unsubscribe_participant(participant: Node) -> void:
	if participant == null or not is_instance_valid(participant):
		return

	var signals_raw: Variant = participant.call("save_change_signals")
	if not (signals_raw is Array):
		return

	var callback: Callable = Callable(self, "_on_participant_changed")
	for signal_raw: Variant in signals_raw:
		var signal_name: StringName = StringName(signal_raw)
		if signal_name.is_empty() or not participant.has_signal(signal_name):
			continue
		if participant.is_connected(signal_name, callback):
			participant.disconnect(signal_name, callback)


## 参与者声明的变更信号统一入口，只负责请求一次落盘。
##
## 形参带默认值是为了同时接住 0 / 1 / 2 个参数的信号（`InventoryChanged`、
## `GoldChanged`、`UpgradeChanged`），避免为每个信号各写一个回调。
##
## @param _first 信号第一个参数，未使用。
## @param _second 信号第二个参数，未使用。
## @return 无返回值。
func _on_participant_changed(_first: Variant = null, _second: Variant = null) -> void:
	request_save()


# ── 采集、分发与落盘 ─────────────────────────────────────────────────────

## 采集全部参与者的当前状态。
##
## @return {"global": {key: Dictionary}, "run": {key: Dictionary}}；参与者返回值不是字典时
##   跳过该参与者并报错（协议被破坏，不应静默写进存档）。
func capture() -> Dictionary:
	var data: Dictionary = {SCOPE_GLOBAL: {}, SCOPE_RUN: {}}

	for key: Variant in _participants:
		var participant: Node = _participants[key]
		if not is_instance_valid(participant):
			continue

		var scope: String = String(participant.call("save_scope"))
		if not data.has(scope):
			continue

		var captured: Variant = participant.call("capture_save_data")
		if not (captured is Dictionary):
			push_error(
				"SaveManager: 参与者 %s 的 capture_save_data() 未返回字典，本次采集跳过它。"
				% String(key)
			)
			continue

		var scope_data: Dictionary = data[scope]
		scope_data[String(key)] = captured

	return data


## 用给定存档内容覆盖内存存档并分发给全部参与者。
##
## @param data 形如 {"global": Dictionary, "run": Dictionary} 的存档内容；缺失的作用域按空处理。
## @return 全部参与者都成功应用时为 true。
func apply(data: Dictionary) -> bool:
	_loaded_data = _normalize_scopes(data)
	_loaded = true
	return _distribute_to_participants()


## 从磁盘读取存档。
##
## 读取失败的处理顺序（为什么是这个顺序）：先把损坏的主档另存为 `.corrupt` 保留现场，
## 再尝试从 `.bak` 恢复；`.bak` 也无效时才以默认值启动。绝不把损坏内容写回 `.bak`，
## 那会毁掉唯一的自动恢复来源。
##
## @return 无返回值；结果通过 `has_save()` 与 `get_last_load_error()` 查询。
func load_from_disk() -> void:
	_loaded = true
	_loaded_data = {SCOPE_GLOBAL: {}, SCOPE_RUN: {}}
	_has_valid_save = false
	_last_load_error = ""

	if not FileAccess.file_exists(SaveFilePath):
		return

	var primary_document: Dictionary = {}
	var primary_error: String = _try_read_document(SaveFilePath, primary_document)
	if primary_error.is_empty():
		_adopt_document(primary_document)
		return

	_last_load_error = primary_error
	var corrupt_path: String = _preserve_corrupt_file()
	push_error(
		"SaveManager: 存档无法读取（%s），已保留为 %s，本次以默认值启动。"
		% [primary_error, corrupt_path]
	)

	var backup_document: Dictionary = {}
	var backup_error: String = _try_read_document(get_backup_file_path(), backup_document)
	if backup_error.is_empty():
		_adopt_document(backup_document)
		push_warning(
			"SaveManager: 已从 %s 恢复上一次成功写入的进度。" % get_backup_file_path()
		)


## 请求一次落盘（防抖）。
##
## 分发存档期间到达的请求被丢弃而不是延迟：那是读档造成的回声，落盘只会多写一次
## 相同内容，反而掩盖真正的写入错误。
##
## @return 无返回值。
func request_save() -> void:
	if _is_applying:
		return
	_dirty = true


## 立即采集并原子写入存档。
##
## 失败时 `push_error` 并返回 false，**不假装成功**：内存里的状态仍然有效，但日志必须让
## 「没存上」这件事可见。
##
## @return 写入成功时为 true。
func save_now() -> bool:
	_dirty = false
	_dirty_elapsed = 0.0

	var data: Dictionary = capture()
	_warn_unknown_keys(data)

	var document: Dictionary = {
		"format_version": FORMAT_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"data": data,
	}
	var written: bool = _write_atomically(JSON.stringify(document, "  "))
	if written:
		_successful_writes += 1
		_loaded_data = data
		_has_valid_save = true
	return written


## 删除全部存档产物并把内存状态复位为「无存档」。
##
## 这是本次唯一的「清档」入口（用户明确要求存档全自动、无玩家可见 UI）。删除后不主动
## 落盘，下次启动即回到默认值。
##
## @return 无残留文件时为 true。
func erase_save() -> bool:
	var all_removed: bool = true
	for path: String in [
		SaveFilePath,
		get_backup_file_path(),
		get_temp_file_path(),
		get_corrupt_file_path(),
	]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error: Error = DirAccess.remove_absolute(path)
		if remove_error != OK:
			push_error("SaveManager: 无法删除 %s（错误码 %d）。" % [path, remove_error])
			all_removed = false

	_loaded_data = {SCOPE_GLOBAL: {}, SCOPE_RUN: {}}
	_has_valid_save = false
	_last_load_error = ""
	_dirty = false
	_dirty_elapsed = 0.0
	_warned_unknown_keys.clear()
	return all_removed


## 清空局内作用域并把 run 参与者复位为默认值。
##
## 本次没有 run 参与者，因此它是为后续「每局进度存档」预留的收口点：新一局开始时调用它，
## 就能保证上一局的残留不会漏进新局。
##
## @return 无返回值。
func clear_run_scope() -> void:
	var run_data: Dictionary = _loaded_data.get(SCOPE_RUN, {}) as Dictionary
	if run_data == null:
		run_data = {}
	run_data.clear()
	_loaded_data[SCOPE_RUN] = run_data

	for key: Variant in _participants:
		var participant: Node = _participants[key]
		if not is_instance_valid(participant):
			continue
		if String(participant.call("save_scope")) == SCOPE_RUN:
			_apply_to_participant(participant, String(key))


## 把内存存档分发给全部已注册参与者。
##
## @return 全部参与者都成功应用时为 true。
func _distribute_to_participants() -> bool:
	var all_applied: bool = true
	for key: Variant in _participants:
		if not _apply_to_participant(_participants[key], String(key)):
			all_applied = false
	return all_applied


## 把某个参与者在存档里的那一份数据分发下去。
##
## @param participant 目标参与者。
## @param key 参与者键名。
## @return 成功应用（或该参与者本就没有存档）时为 true。
func _apply_to_participant(participant: Node, key: String) -> bool:
	if participant == null or not is_instance_valid(participant):
		return false

	var scope: String = String(participant.call("save_scope"))
	var scope_data: Dictionary = _loaded_data.get(scope, {}) as Dictionary
	if scope_data == null:
		scope_data = {}

	var payload: Dictionary = {}
	if scope_data.has(key) and scope_data[key] is Dictionary:
		payload = scope_data[key]

	# 分发期间压制自动存档请求：读档写入参与者状态会产生「变更信号 → 请求落盘」的回声，
	# 若不放行会把刚读进来的文件立刻原样重写一遍。
	var previous_applying: bool = _is_applying
	_is_applying = true
	var applied: Variant = participant.call("apply_save_data", payload)
	_is_applying = previous_applying

	if not (applied is bool) or not bool(applied):
		push_error(
			"SaveManager: 参与者 %s（key=%s）应用存档失败。"
			% [_describe_participant(participant), key]
		)
		return false

	return true


## 生成参与者的可诊断描述。
##
## 为什么不能只用 `node.name`：参与者可能是尚未进入场景树、或从未命名的实例（测试夹具就是
## 这样），此时名字是空串，报错会退化成「参与者  缺少…」这种无法定位的信息。
## 回退到脚本路径可以保证任何情况下都能指到具体文件。
##
## @param participant 参与者节点。
## @return 形如 `PlayerWallet (res://…/player_wallet.gd)` 的描述。
func _describe_participant(participant: Node) -> String:
	var script_resource: Script = participant.get_script()
	var script_path: String = ""
	if script_resource != null:
		script_path = script_resource.resource_path

	if participant.name.is_empty():
		if script_path.is_empty():
			return "未命名的参与者"
		return "路径为 %s 的参与者" % script_path

	if script_path.is_empty():
		return String(participant.name)
	return "%s (%s)" % [participant.name, script_path]


## 归一化存档作用域，保证 global / run 两个键都存在且都是字典。
##
## @param data 原始存档内容。
## @return 归一化后的 {"global": Dictionary, "run": Dictionary}。
func _normalize_scopes(data: Dictionary) -> Dictionary:
	var normalized: Dictionary = {SCOPE_GLOBAL: {}, SCOPE_RUN: {}}
	for scope: String in [SCOPE_GLOBAL, SCOPE_RUN]:
		var raw: Variant = data.get(scope)
		if raw is Dictionary:
			normalized[scope] = (raw as Dictionary).duplicate(true)
	return normalized


## 对存档里存在但没有任何参与者认领的键发出告警（每个键只告警一次）。
##
## 为什么是告警而不是错误：删掉一个参与者不应该让旧存档整体失效，但要让人看得见
## 「这份存档里有一段没人读的数据」。
##
## @param data 本次采集出的存档内容。
## @return 无返回值。
func _warn_unknown_keys(data: Dictionary) -> void:
	var global_data: Dictionary = data.get(SCOPE_GLOBAL, {}) as Dictionary
	if global_data == null:
		return

	for key: Variant in global_data:
		var key_text: String = String(key)
		if _participants.has(key_text) or _warned_unknown_keys.has(key_text):
			continue
		_warned_unknown_keys[key_text] = true
		push_warning("SaveManager: 存档里存在无参与者认领的键 %s，其内容不会被读取。" % key_text)


# ── 文件层 ───────────────────────────────────────────────────────────────

## 解析一个存档文件。
##
## @param path 文件路径。
## @param out_document 输出参数：成功时就地写入 {"global": Dictionary, "run": Dictionary}。
## @return 空字符串表示成功，否则为可诊断的失败原因。
func _try_read_document(path: String, out_document: Dictionary) -> String:
	if not FileAccess.file_exists(path):
		return "文件不存在"

	var text: String = FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return "文件为空"

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return "内容不是合法的 JSON 对象"
	var document: Dictionary = parsed

	var version_raw: Variant = document.get("format_version")
	if not _is_number(version_raw):
		return "缺少可解析的 format_version"
	if int(version_raw) != FORMAT_VERSION:
		return "format_version 为 %d，当前需要 %d" % [int(version_raw), FORMAT_VERSION]

	var data_raw: Variant = document.get("data")
	if not (data_raw is Dictionary):
		return "缺少 data 对象"
	var data: Dictionary = data_raw

	for scope: String in [SCOPE_GLOBAL, SCOPE_RUN]:
		var scope_raw: Variant = data.get(scope, {})
		if not (scope_raw is Dictionary):
			return "data.%s 不是对象" % scope
		out_document[scope] = (scope_raw as Dictionary).duplicate(true)

	return ""


## 把解析好的存档内容设为当前内存存档。
##
## @param document 已通过校验的 {"global": Dictionary, "run": Dictionary}。
## @return 无返回值。
func _adopt_document(document: Dictionary) -> void:
	_loaded_data = _normalize_scopes(document)
	_has_valid_save = true
	_last_load_error = ""


## 把损坏的主档另存为 `.corrupt` 以保留现场。
##
## @return 损坏现场文件路径；复制失败时返回空字符串。
func _preserve_corrupt_file() -> String:
	var corrupt_path: String = get_corrupt_file_path()
	if FileAccess.file_exists(corrupt_path):
		DirAccess.remove_absolute(corrupt_path)
	var copy_error: Error = DirAccess.copy_absolute(SaveFilePath, corrupt_path)
	if copy_error != OK:
		push_warning("SaveManager: 未能保留损坏存档现场（错误码 %d）。" % copy_error)
		return ""
	return corrupt_path


## 原子写入存档文本。
##
## 步骤与理由：先建目录；再把**现有**主档复制为 `.bak`（这样第 4 步的退化路径即使出现
## 「目标文件不存在」的窗口也仍有可恢复来源）；然后写 `.tmp` 并关闭（`FileAccess` 关闭即
## flush）；最后 rename 覆盖主档。
##
## @param text 要写入的 JSON 文本。
## @return 写入成功时为 true。
func _write_atomically(text: String) -> bool:
	var save_directory: String = get_save_directory()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(save_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error(
			"SaveManager: 无法创建存档目录 %s（错误码 %d）。" % [save_directory, directory_error]
		)
		return false

	if FileAccess.file_exists(SaveFilePath):
		var backup_path: String = get_backup_file_path()
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		var backup_error: Error = DirAccess.copy_absolute(SaveFilePath, backup_path)
		if backup_error != OK:
			push_warning("SaveManager: 未能生成备份 %s（错误码 %d）。" % [backup_path, backup_error])

	var temp_path: String = get_temp_file_path()
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveManager: 无法写入临时存档 %s（错误码 %d）。"
			% [temp_path, FileAccess.get_open_error()]
		)
		return false

	file.store_string(text)
	file.close()

	var rename_error: Error = DirAccess.rename_absolute(temp_path, SaveFilePath)
	if rename_error != OK:
		# 退化路径：`rename` 不覆盖已存在的目标时，先删目标再改名。这一步存在「主档短暂
		# 不存在」的窗口，因此上面的 `.bak` 是这条路径唯一的可恢复来源，不能省略。
		if FileAccess.file_exists(SaveFilePath):
			DirAccess.remove_absolute(SaveFilePath)
		rename_error = DirAccess.rename_absolute(temp_path, SaveFilePath)

	if rename_error != OK:
		push_error(
			"SaveManager: 存档写入失败（错误码 %d），本次改动未能落盘。" % rename_error
		)
		return false

	return true


## 判断 Variant 是否为可参与整数运算的数值。
##
## @param value 待判定的 Variant。
## @return 整数或浮点数时为 true。
func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
