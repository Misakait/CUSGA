extends RefCounted

## 计算入夜生成驻守通道表时使用的最终概率。
##
## 该服务只解释配置 Resource 和玩家标签，不负责修改地图状态；这样可以在迁移期间
## 让旧 C# 配置与 GDScript 配置共享同一套概率规则。

## 根据全局配置和玩家标签计算最终驻守概率。
##
## 参数 settings：包含 BaseGuardChance 和 ProbabilityModifiers 的驻守配置资源。
## 参数 tags：可选的标签对象，需要提供 HasTag(StringName) 方法。
## 返回值：限制在 0 到 1 之间的最终驻守概率。
func Calculate(settings: Resource, tags: Object = null) -> float:
	if settings == null:
		return 0.0

	var additive_sum := 0.0
	var multiplier_product := 1.0
	for modifier in _read_resource_array(settings, &"ProbabilityModifiers"):
		if modifier == null or not _applies(modifier, tags):
			continue

		additive_sum += _read_float(modifier, &"AdditiveChance", 0.0)
		multiplier_product *= _read_float(modifier, &"Multiplier", 1.0)

	var base_chance := _read_float(settings, &"BaseGuardChance", 0.0)
	return clampf((base_chance + additive_sum) * multiplier_product, 0.0, 1.0)


## 判断概率修正是否满足玩家标签条件。
##
## 参数 modifier：旧 C# 或新 GDScript 概率修正资源。
## 参数 tags：玩家标签对象；为空时只有无标签修正可生效。
## 返回值：标签为空或玩家拥有所需标签时返回 true。
func _applies(modifier: Resource, tags: Object) -> bool:
	var required_tag := _read_string_name(modifier, &"RequiredTag")
	if required_tag.is_empty():
		return true
	if tags == null or not tags.has_method(&"HasTag"):
		return false

	return bool(tags.call(&"HasTag", required_tag))


## 从 Resource 边界读取浮点配置，兼容整型和浮点型 Variant。
##
## 参数 resource：待读取的配置资源。
## 参数 property_name：导出属性名称。
## 参数 fallback：属性缺失或类型不匹配时使用的中性默认值。
## 返回值：资源中的浮点配置或 fallback。
func _read_float(resource: Resource, property_name: StringName, fallback: float) -> float:
	var value: Variant = resource.get(property_name)
	if value is int or value is float:
		return float(value)
	return fallback


## 从 Resource 边界读取标签，兼容 StringName、String 和空值。
##
## 参数 resource：待读取的概率修正资源。
## 参数 property_name：标签属性名称。
## 返回值：资源中的标签；无法读取时返回空标签。
func _read_string_name(resource: Resource, property_name: StringName) -> StringName:
	var value: Variant = resource.get(property_name)
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return &""


## 从配置 Resource 读取通用 Resource 数组。
##
## 参数 resource：待读取的配置资源。
## 参数 property_name：数组属性名称。
## 返回值：过滤掉非 Resource 元素后的配置数组。
func _read_resource_array(resource: Resource, property_name: StringName) -> Array[Resource]:
	var resources: Array[Resource] = []
	var value: Variant = resource.get(property_name)
	if not value is Array:
		return resources

	for item in value:
		if item is Resource:
			resources.append(item)
	return resources
