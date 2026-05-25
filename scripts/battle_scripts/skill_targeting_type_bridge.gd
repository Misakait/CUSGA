## 技能目标类型桥接器：运行时解析 C# 枚举并缓存映射，避免 GDScript 侧重复维护。
## 返回值说明：通过 `get_map`/`get_value` 获取枚举名称到整型值的映射。
extends RefCounted
class_name SkillTargetingTypeBridge

# 读取 C# 枚举源文件，避免在 GDScript 中重复维护枚举顺序。
# 这里采用文本解析，是为了在不修改 C# 的前提下同步枚举值。
const ENUM_SOURCE_PATH := "res://core/combat/skills/SkillTargetingType.cs"

# 兜底映射：当 C# 源文件读取失败或解析为空时使用，确保战斗不崩。
const FALLBACK_VALUES := {
	"Self": 0,
	"SingleEnemy": 1,
	"AllEnemies": 2,
	"AnySingleUnit": 3,
	"AllUnits": 4,
	"RandomEnemy": 5,
	"SpreadFromEnemy": 6
}

static var _cached_map: Dictionary = {}

## 获取枚举映射字典。
## 返回值：key 为枚举名（String），value 为枚举整型值（int）。
static func get_map() -> Dictionary:
	if _cached_map.is_empty():
		_cached_map = _load_from_source()
	return _cached_map

## 获取指定枚举名对应的整型值。
## 参数：
## - name：枚举名称。
## - fallback：当名称不存在时的兜底值。
## 返回值：目标枚举的整型值，或兜底值。
static func get_value(name: String, fallback: int = -1) -> int:
	var map := get_map()
	return map.get(name, fallback)

static func _load_from_source() -> Dictionary:
	var file := FileAccess.open(ENUM_SOURCE_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法读取 SkillTargetingType.cs，使用兜底枚举映射。")
		return FALLBACK_VALUES.duplicate()

	var text := file.get_as_text()
	file.close()

	var in_enum := false
	var current_value := 0
	var map: Dictionary = {}

	# 仅解析 SkillTargetingType 枚举定义块，按声明顺序生成数值。
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()

		if not in_enum:
			if "enum SkillTargetingType" in line:
				in_enum = true
			continue

		if line.is_empty() or line.begins_with("//"):
			continue

		var comment_index := line.find("//")
		if comment_index >= 0:
			line = line.substr(0, comment_index).strip_edges()

		if line.is_empty():
			continue

		if "}" in line:
			break

		# 跳过枚举块起始花括号或特性行，避免隐式枚举值被错误偏移。
		if line.begins_with("{") or line.begins_with("["):
			continue

		if line.ends_with(","):
			line = line.substr(0, line.length() - 1).strip_edges()

		if line.is_empty():
			continue

		var parts := line.split("=", false, 2)
		var name := parts[0].strip_edges()
		if name.is_empty():
			continue

		# 如果 C# 枚举显式赋值，则以该值为准，并从此继续递增。
		if parts.size() > 1:
			var value_str := parts[1].strip_edges()
			if value_str.is_valid_int():
				current_value = int(value_str)

		map[name] = current_value
		current_value += 1

	if map.is_empty():
		push_warning("SkillTargetingType 枚举解析结果为空，使用兜底映射。")
		return FALLBACK_VALUES.duplicate()

	return map

## 清理运行时缓存，方便热更新或调试。
static func clear_cache() -> void:
	# 允许运行时清理缓存，方便调试或热更新枚举。
	_cached_map.clear()
