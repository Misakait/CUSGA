extends Node2D

## 统计区域协调器；通过各子区域公开接口显示时间、结局和描述。
## 参数由公开设置接口提供；本区域不参与奖励计算或存档。

var _duration_seconds: float = 0.0
var _ending_id: String = ""
var _ending_title: String = ""
var _description: String = ""
var _statistics: Dictionary = {}

func _ready() -> void:
	_refresh()

## 更新活跃游玩时间。
## 参数 seconds：秒数，负值按 0；返回值：无。
func set_play_time(seconds: float) -> void:
	_duration_seconds = maxf(seconds, 0.0)
	_refresh()

## 更新结局标识与名称。
## 参数 id：稳定结局标识；title：显示名称；返回值：无。
func set_ending(id: String, title: String) -> void:
	_ending_id = id
	_ending_title = title
	_refresh()

## 替换完整描述。
## 参数 text：新描述；返回值：无。
func set_description(text: String) -> void:
	_description = text
	_refresh()

## 换行追加描述，空原文没有前导换行，空追加不增加空行。
## 参数 text：额外描述；返回值：无。
func add_description(text: String) -> void:
	if text.is_empty():
		return
	_description += ("\n" if not _description.is_empty() else "") + text
	_refresh()

## 接收扩展统计；不把机器键名直接显示给玩家。
## 参数 data：后续玩法的统计字典；返回值：无。
func set_statistics(data: Dictionary) -> void:
	_statistics = data.duplicate(true)

## 读取扩展统计的隔离副本。
## 返回值：统计字典，修改副本不影响本区域。
func get_statistics() -> Dictionary:
	return _statistics.duplicate(true)

func _refresh() -> void:
	if not is_node_ready():
		return
	var seconds: int = floori(_duration_seconds)
	get_node("TimeSection").call("set_text", "耗时：%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60])
	var ending: String = _ending_title if not _ending_title.is_empty() else _ending_id
	get_node("EndingSection").call("set_text", "达成结局：" + (ending if not ending.is_empty() else "未结束"))
	get_node("Description").call("set_description", _description)
