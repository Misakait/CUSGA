extends RefCounted

## 房间地形布局生成器的 GDScript 生产实现，等价迁移自 RoomTerrainLayoutGenerator.cs。
##
## 只负责按地形配置产出摆放结果：按权重轮盘赌选地形、乱序取格子、按格子中心换算
## 摆放坐标、按倍率区间抽样地形浮动倍率。摆放结果用字典表达（TerrainData、
## LocalGridPos、BoardPosition、Variance），让 GDScript 仓库可以直接消费。
##
## 旧 C# 生成器与 TerrainSpawnPlacement 继续作为兼容垫片保留；普通 C# 类
## MonsterStatMultiplier 无法跨越 GDScript 边界，因此这里只产出倍率字典。
##
## 唯一有意的差异是随机数源：旧实现使用 System.Random，这里使用
## RandomNumberGenerator，同一种子不会得到相同序列，但抽样规则、权重边界、
## min/max 反序处理和格子坐标换算与旧实现完全一致。

## 倍率字典的稳定字段顺序，与旧 MonsterStatMultiplier.Identity 的六个字段一致。
const VARIANCE_FIELDS: Array[String] = [
	"MaxHealth",
	"PhysAtk",
	"PhysDef",
	"MagPower",
	"MagResist",
	"Speed",
]

## 布局抽样使用的随机数源。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## 构造布局生成器。
##
## @param seed_value 随机种子；0 表示使用时间随机种子，非 0 时固定种子便于测试对照。
## @return 无。
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## 根据 C# 或 GDScript 地形配置生成摆放结果。
##
## @param profile 含 TerrainPool、MinCount/MaxCount、GridColumns/GridRows、
##        PlacementMin/PlacementMax 与 EncounterVarianceRange 稳定字段的配置资源。
## @return 摆放字典数组；配置为空或地形池没有有效地形时返回空数组。
func Generate(profile: Resource) -> Array:
	if profile == null:
		return []

	var terrain_pool: Array = _read_resource_array(profile, "TerrainPool")
	if terrain_pool.is_empty():
		return []

	var grid_columns: int = maxi(_read_int(profile, "GridColumns", 1), 1)
	var grid_rows: int = maxi(_read_int(profile, "GridRows", 1), 1)
	var available_slots: int = grid_columns * grid_rows
	var min_count: int = clampi(_read_int(profile, "MinCount", 0), 0, available_slots)
	var max_count: int = clampi(
		maxi(_read_int(profile, "MaxCount", min_count), min_count),
		min_count,
		available_slots
	)
	var count: int = _rng.randi_range(min_count, max_count)

	var placement_min: Vector2 = _read_vector2(profile, "PlacementMin", Vector2.ZERO)
	var placement_max: Vector2 = _read_vector2(profile, "PlacementMax", Vector2.ZERO)
	var variance_range: Resource = _read_resource(profile, "EncounterVarianceRange")

	var cells: Array = _build_cells(grid_columns, grid_rows)
	_shuffle(cells)

	var placements: Array = []
	for index in count:
		var entry: Variant = _choose_terrain_entry(terrain_pool)
		var terrain_data: Resource = _read_terrain_data(entry)
		if terrain_data == null:
			continue
		var cell: Vector2i = cells[index]
		placements.append(
			{
				"TerrainData": terrain_data,
				"LocalGridPos": cell,
				"BoardPosition": _cell_center_to_board_position(
					cell, grid_columns, grid_rows, placement_min, placement_max
				),
				"Variance": _roll_multiplier(variance_range),
			}
		)

	return placements


## 按权重从地形池中随机选择一个条目。
##
## @param terrain_pool 已过滤的地形池条目数组。
## @return 选中的地形池条目；没有有效地形时返回 null。
func _choose_terrain_entry(terrain_pool: Array) -> Variant:
	var total_weight: float = 0.0
	for entry: Variant in terrain_pool:
		if _read_terrain_data(entry) == null:
			continue
		total_weight += maxf(_read_float(entry, "Weight", 1.0), 0.0)

	# 总权重不大于 0 时退化为“第一个有效地形”，与旧实现的无随机分支一致。
	if total_weight <= 0.0:
		for entry: Variant in terrain_pool:
			if _read_terrain_data(entry) != null:
				return entry
		return null

	var roll: float = _rng.randf() * total_weight
	var accumulated: float = 0.0
	for entry: Variant in terrain_pool:
		if _read_terrain_data(entry) == null:
			continue
		accumulated += maxf(_read_float(entry, "Weight", 1.0), 0.0)
		if roll <= accumulated:
			return entry

	return null


## 按倍率区间抽样一个完整的地形浮动倍率。
##
## @param range 倍率区间资源；为空时返回中性倍率。
## @return 含六个倍率字段的字典。
func _roll_multiplier(range: Resource) -> Dictionary:
	if range == null:
		return _identity_variance()

	return {
		"MaxHealth": _roll_float(
			_read_multiplier(range, "MinMaxHealth"), _read_multiplier(range, "MaxMaxHealth")
		),
		"PhysAtk": _roll_float(
			_read_multiplier(range, "MinPhysAtk"), _read_multiplier(range, "MaxPhysAtk")
		),
		"PhysDef": _roll_float(
			_read_multiplier(range, "MinPhysDef"), _read_multiplier(range, "MaxPhysDef")
		),
		"MagPower": _roll_float(
			_read_multiplier(range, "MinMagPower"), _read_multiplier(range, "MaxMagPower")
		),
		"MagResist": _roll_float(
			_read_multiplier(range, "MinMagResist"), _read_multiplier(range, "MaxMagResist")
		),
		"Speed": _roll_float(
			_read_multiplier(range, "MinSpeed"), _read_multiplier(range, "MaxSpeed")
		),
	}


## 构造全 1 的中性倍率字典。
##
## @return 六个字段全为 1.0 的字典。
func _identity_variance() -> Dictionary:
	var variance: Dictionary = {}
	for field: String in VARIANCE_FIELDS:
		variance[field] = 1.0
	return variance


## 在闭区间内抽样浮点数；上下界反序时自动交换。
##
## @param min_value 区间下界。
## @param max_value 区间上界。
## @return 区间内的随机浮点数。
func _roll_float(min_value: float, max_value: float) -> float:
	if max_value < min_value:
		var swapped: float = min_value
		min_value = max_value
		max_value = swapped
	return min_value + _rng.randf() * (max_value - min_value)


## 构造按行优先排列的格子列表。
##
## @param grid_columns 网格列数。
## @param grid_rows 网格行数。
## @return 行优先顺序的 Vector2i 格子数组。
func _build_cells(grid_columns: int, grid_rows: int) -> Array:
	var cells: Array = []
	for y in grid_rows:
		for x in grid_columns:
			cells.append(Vector2i(x, y))
	return cells


## 就地洗牌，保持旧的 Fisher-Yates 方向与交换范围。
##
## @param cells 待洗牌的数组。
## @return 无。
func _shuffle(cells: Array) -> void:
	for index in range(cells.size() - 1, 0, -1):
		var swap_index: int = _rng.randi_range(0, index)
		var current: Variant = cells[index]
		cells[index] = cells[swap_index]
		cells[swap_index] = current


## 按格子中心在摆放矩形内插值得到棋盘坐标。
##
## @param cell 房间内局部格子坐标。
## @param grid_columns 网格列数。
## @param grid_rows 网格行数。
## @param placement_min 摆放矩形左上角。
## @param placement_max 摆放矩形右下角。
## @return 该格子的棋盘显示坐标。
func _cell_center_to_board_position(
	cell: Vector2i,
	grid_columns: int,
	grid_rows: int,
	placement_min: Vector2,
	placement_max: Vector2
) -> Vector2:
	var x_ratio: float = (float(cell.x) + 0.5) / float(grid_columns)
	var y_ratio: float = (float(cell.y) + 0.5) / float(grid_rows)
	return Vector2(
		lerpf(placement_min.x, placement_max.x, x_ratio),
		lerpf(placement_min.y, placement_max.y, y_ratio)
	)


## 从任意字段容器读取字段值，兼容字典与对象属性。
##
## @param source 字段容器。
## @param field_name 字段名称。
## @param fallback 字段缺失时的默认值。
## @return 字段值或默认值。
func _read_field(source: Variant, field_name: String, fallback: Variant) -> Variant:
	if source == null:
		return fallback
	if source is Dictionary:
		var dictionary: Dictionary = source
		return dictionary[field_name] if dictionary.has(field_name) else fallback
	if source is Object:
		var object: Object = source
		return object.get(field_name)
	return fallback


## 读取 Resource 数组字段并过滤非 Resource 元素。
##
## @param resource 待读取的配置资源。
## @param field_name 数组字段名称。
## @return 过滤后的 Resource 数组；字段缺失或类型不符时返回空数组。
func _read_resource_array(resource: Resource, field_name: String) -> Array:
	var resources: Array = []
	if resource == null:
		return resources

	var value: Variant = resource.get(field_name)
	if not (value is Array):
		return resources

	for item: Variant in value:
		if item is Resource:
			resources.append(item)
	return resources


## 读取嵌套 Resource 字段。
##
## @param resource 待读取的配置资源。
## @param field_name 字段名称。
## @return 嵌套 Resource；缺失或类型不符时返回 null。
func _read_resource(resource: Resource, field_name: String) -> Resource:
	if resource == null:
		return null
	return _read_field(resource, field_name, null) as Resource


## 读取整数配置，兼容 int 与 float 两种 Variant。
##
## @param source 配置来源。
## @param field_name 字段名称。
## @param fallback 字段缺失或类型不符时的默认值。
## @return 读取到的整数或默认值。
func _read_int(source: Variant, field_name: String, fallback: int) -> int:
	var value: Variant = _read_field(source, field_name, null)
	if value is int or value is float:
		return int(value)
	return fallback


## 读取浮点配置，兼容 int 与 float 两种 Variant。
##
## @param source 配置来源。
## @param field_name 字段名称。
## @param fallback 字段缺失或类型不符时的默认值。
## @return 读取到的浮点数或默认值。
func _read_float(source: Variant, field_name: String, fallback: float) -> float:
	var value: Variant = _read_field(source, field_name, null)
	if value is int or value is float:
		return float(value)
	return fallback


## 读取 Vector2 配置。
##
## @param source 配置来源。
## @param field_name 字段名称。
## @param fallback 字段缺失或类型不符时的默认值。
## @return 读取到的坐标或默认值。
func _read_vector2(source: Variant, field_name: String, fallback: Vector2) -> Vector2:
	var value: Variant = _read_field(source, field_name, null)
	return value if value is Vector2 else fallback


## 从地形池条目读取 TerrainData，兼容 C# 与 GDScript Resource。
##
## @param entry 地形池条目。
## @return 条目中的地形卡；缺失或类型不符时返回 null。
func _read_terrain_data(entry: Variant) -> Resource:
	return _read_field(entry, "TerrainData", null) as Resource


## 读取倍率区间中的单个倍率字段。
##
## @param range 倍率区间资源。
## @param field_name 字段名称。
## @return 倍率数值；缺失或类型不符时返回中性值 1。
func _read_multiplier(range: Resource, field_name: String) -> float:
	return _read_float(range, field_name, 1.0)
