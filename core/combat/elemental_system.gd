extends RefCounted

## 五行属性克制与天气修正的 GDScript 生产实现，等价旧 core/combat/ElementalSystem.cs。
##
## 相克矩阵与旧 C# 元组字典逐项一致（金克木、木克土、土克水、水克火、火克金各 1.5 倍，
## 反向各 0.5 倍），天气修正通过稳定的 Autoload 节点路径读取，兼容 GDScript 天气管理器
## 与旧 C# 天气管理器。不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 相克倍率。
const COUNTER_MODIFIER: float = 1.5
## 被克制倍率。
const RESIST_MODIFIER: float = 0.5

## ElementType.None。
const ELEMENT_NONE: int = 0
## ElementType.Wood。
const ELEMENT_WOOD: int = 1
## ElementType.Metal。
const ELEMENT_METAL: int = 2
## ElementType.Water。
const ELEMENT_WATER: int = 3
## ElementType.Earth。
const ELEMENT_EARTH: int = 4
## ElementType.Fire。
const ELEMENT_FIRE: int = 5

## 矩阵键的进位，等价旧 C# 的 (攻击属性, 防御属性) 元组键。
const MATRIX_KEY_RADIX: int = 10

## 五行相克矩阵，键为攻击属性 * 10 + 防御属性。
const DAMAGE_MATRIX: Dictionary = {
	21: COUNTER_MODIFIER,  # 金克木
	14: COUNTER_MODIFIER,  # 木克土
	43: COUNTER_MODIFIER,  # 土克水
	35: COUNTER_MODIFIER,  # 水克火
	52: COUNTER_MODIFIER,  # 火克金
	12: RESIST_MODIFIER,  # 木被金克
	34: RESIST_MODIFIER,  # 水被土克
	53: RESIST_MODIFIER,  # 火被水克
	41: RESIST_MODIFIER,  # 土被木克
	25: RESIST_MODIFIER,  # 金被火克
}

## 天气 Autoload 节点名。
const WEATHER_MANAGER_PATH: String = "WeatherManager"


## 计算攻击属性对防御属性的最终伤害倍率，包含天气修正。
##
## @param attack_element 攻击方五行属性 Enum 整数。
## @param defense_element 防御方五行属性 Enum 整数。
## @return 五行倍率与天气倍率的乘积；无匹配时返回 1.0。
static func CalculateMultiplier(attack_element: int, defense_element: int) -> float:
	var multiplier: float = 1.0

	# 五行基础倍率查询。
	var base_multiplier: Variant = DAMAGE_MATRIX.get(_matrix_key(attack_element, defense_element))
	if base_multiplier != null:
		multiplier = float(base_multiplier)

	# 通过稳定的 Autoload 节点路径读取天气，兼容 GDScript 管理器和旧 C# 管理器。
	var weather_manager: Node = _get_weather_manager()
	if weather_manager != null:
		var weather: Variant = weather_manager.get("CurrentWeather")
		if weather != null:
			var weather_multiplier: Variant = _read_weather_multiplier(weather, attack_element)
			if weather_multiplier != null:
				multiplier *= float(weather_multiplier)

	return multiplier


## 把攻击与防御属性编码为矩阵键。
##
## @param attack_element 攻击方五行属性 Enum 整数。
## @param defense_element 防御方五行属性 Enum 整数。
## @return 矩阵字典键。
static func _matrix_key(attack_element: int, defense_element: int) -> int:
	return attack_element * MATRIX_KEY_RADIX + defense_element


## 从当前场景树获取天气 Autoload。
##
## @return 天气管理器节点；编辑器或测试环境未启动场景树时返回 null。
static func _get_weather_manager() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null

	var tree: SceneTree = main_loop
	if tree.root == null:
		return null

	return tree.root.get_node_or_null(WEATHER_MANAGER_PATH)


## 读取天气 Resource 中指定元素的倍率，兼容 GDScript/C# Dictionary Variant。
##
## @param weather 天气配置资源。
## @param element_key 五行属性的稳定整数值。
## @return 找到数值倍率时返回倍率；否则返回 null。
static func _read_weather_multiplier(weather: Variant, element_key: int) -> Variant:
	var modifiers: Variant = weather.get("ElementModifiers")
	if typeof(modifiers) != TYPE_DICTIONARY:
		return null

	var modifier_map: Dictionary = modifiers
	if not modifier_map.has(element_key):
		return null

	var raw_multiplier: Variant = modifier_map[element_key]
	if typeof(raw_multiplier) != TYPE_INT and typeof(raw_multiplier) != TYPE_FLOAT:
		return null

	return float(raw_multiplier)
