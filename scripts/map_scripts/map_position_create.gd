extends Node2D

## 地图位置生成器（群系优先 BFS 算法）
##
## 核心逻辑：
## - 以 normal 群系为中心，6 个群系各自聚拢生成。
## - 每个场景的连接数受其类别约束（主 3~4 / 过渡 1~4 / 传送 3~4 / 集市 3~4）。
## - normal 与其余 5 个群系之间有且仅有一个通道相连。
##
## 输出（与旧版兼容）：
##   map: Array[Array]              — 2D 字符串数组，每格为场景名或 "void"
##   scene_to_scene: Dictionary     — {Vector2i: [上,右,下,左]} 四方向连接

@onready var map_types_ref: Node2D = $"../MapTypes"

# 四方向偏移：[上, 右, 下, 左]
const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]

# 反向映射：方向索引 → 对侧方向索引
const OPPOSITE_DIR: Array[int] = [2, 3, 0, 1]

# 每个群系内部场景节点数上限（用作 BFS 队列容量估算）
const MAX_SCENES_PER_BIOME := 22

# ---- 公共输出 ----
var map: Array = []                       ## 2D 网格，map[x][y] = 场景名（String）
var scene_to_scene: Dictionary = {}       ## {Vector2i: [int,int,int,int]} 四方向连接
var start_position: Vector2i              ## 生成后的起始位置（normal 群系集市场景）
var max_dis_from_home: int = 0
var max_dis_from_home_point: Vector2i = Vector2i(1, 1)
var map_arr: Array[Vector2i] = []         ## 创建顺序（保留兼容）
var map_search_arr: Array[Vector2i] = []  ## 搜索顺序（保留兼容）
var map_point_has_search: Dictionary = {} ## 已搜索标记（保留兼容）

# ---- 内部状态 ----
var _grid_rows: int = 0
var _grid_cols: int = 0
var _biomes_placed: int = 0
# 记录每个群系已放置的位置列表
var _biome_positions: Dictionary = {}  ## {String: Array[Vector2i]} 群系名 → 已放置位置列表
# 位置 → 所属群系名（用于跨群系连接约束）
var _pos_biome: Dictionary = {}  ## {Vector2i: String}


func _ready() -> void:
	randomize()
	_build_world()


## === 世界生成入口 ===
func _build_world() -> void:
	if map_types_ref == null:
		push_error("MapPositionCreate 未找到 MapTypes 节点，无法生成地图。")
		return

	var biome_defs: Array[BiomeDefinition] = map_types_ref.biome_definitions
	if biome_defs.is_empty():
		push_error("MapTypes 中没有配置任何生态群系。")
		return

	# 1. 计算总场景数并估算网格大小
	var total_scenes := 0
	for bd in biome_defs:
		if bd != null:
			total_scenes += bd.get_total_scene_count()

	# 网格尺寸：场景数的 2 倍取平方根，上下留余量（最少 15×12）
	_grid_rows = max(15, ceili(sqrt(total_scenes * 2.5)))
	_grid_cols = max(12, ceili(sqrt(total_scenes * 2.0)))

	# 2. 初始化二维数组
	map.clear()
	for x in range(_grid_rows):
		var col: Array = []
		for y in range(_grid_cols):
			col.append("void")
		map.append(col)

	scene_to_scene.clear()
	_biome_positions.clear()
	_pos_biome.clear()

	# 3. 找到起始群系（normal）
	var normal_biome: BiomeDefinition = map_types_ref.starting_biome
	if normal_biome == null:
		push_error("未设置起始群系（is_starting_biome），无法生成地图。")
		return

	# 4. 阶段一：生成 normal 群系
	var center := Vector2i(_grid_rows / 2, _grid_cols / 2)
	start_position = center
	_biome_generate(normal_biome, center)

	# 5. 阶段二：按顺序生成其余 5 个群系
	var others: Array[BiomeDefinition] = []
	for bd in biome_defs:
		if bd != null and bd != normal_biome:
			others.append(bd)

	# 为每个群系找一个锚点：必须紧邻 normal 群系，确保有且仅有一个跨群系通道
	for other_biome in others:
		var anchor := _find_edge_anchor_near_biome("normal")
		if anchor == Vector2i(-1, -1):
			# 退路：在任意已生成区域边缘找锚点
			anchor = _find_edge_anchor()
		if anchor == Vector2i(-1, -1):
			push_warning("无法为群系 ", other_biome.biome_name, " 找到合适的锚点，跳过。")
			continue
		_biome_generate(other_biome, anchor)

	# 6. 强制约束：normal 与每个其他群系之间有且仅有一个通道
	_enforce_normal_inter_biome_connections()

	# 7. 输出地图信息
	for col in map:
		print(col)
	print("[MapPositionCreate] 地图生成完成，共 ", total_scenes, " 个场景。")


## === 单个群系的 BFS 生成 ===
func _biome_generate(biome: BiomeDefinition, start_pos: Vector2i) -> void:
	var bname := biome.biome_name
	print("[MapPositionCreate] 开始生成群系: ", bname, " 起点: ", start_pos)

	var placed: Array[Vector2i] = []
	var queue: Array[Vector2i] = []

	# ---- 场景池初始化 ----
	var main_pool: Array[map_attribute] = []
	main_pool.append_array(biome.main_scenes)

	var transition_pool: Array[map_attribute] = []
	transition_pool.append_array(biome.transition_scenes)

	var teleport_attr: map_attribute = biome.teleport_scene
	var market_attr: map_attribute = biome.market_scene
	var teleport_placed := false
	var market_placed := false

	# ---- 第一步：放置集市场景 ----
	if market_attr != null:
		_place_scene(start_pos, market_attr.scene_name, bname)
		market_placed = true
		queue.append(start_pos)
		placed.append(start_pos)

	# ---- 第二步：BFS 展开主场景和过渡场景 ----
	# 放置优先级：主场景（需多连接） > 过渡场景（连接需求较灵活）
	while not queue.is_empty() and (not main_pool.is_empty() or not transition_pool.is_empty()):
		var current := queue.pop_front() as Vector2i

		# 确定当前场景还需要创建多少连接
		var cur_attr := _find_attr_for_name(_cell_name(current))
		if cur_attr == null:
			continue

		var existing_conns := _count_connections(current)
		var target_conns := randi_range(cur_attr.min_connections, cur_attr.max_connections)
		var to_create: int = max(0, target_conns - existing_conns)

		if to_create <= 0:
			continue

		# 获取空闲相邻方向（洗牌以增加随机性）
		var free_dirs := _get_free_directions(current)
		_free_directions_shuffle(free_dirs)

		for dir_idx in free_dirs:
			if to_create <= 0:
				break

			var new_pos := current + DIR_OFFSETS[dir_idx]
			var next_attr: map_attribute = null

			# 按优先级选场景：主场景优先 → 过渡场景
			if not main_pool.is_empty():
				next_attr = main_pool.pop_front()
			elif not transition_pool.is_empty():
				next_attr = transition_pool.pop_front()
			else:
				break

			if next_attr == null:
				continue

			# 放置场景
			_place_scene(new_pos, next_attr.scene_name, bname)
			_add_connection(current, new_pos, dir_idx)
			placed.append(new_pos)
			to_create -= 1

			# 如果新场景还需要更多连接，放回 BFS 队列继续展开
			if next_attr.max_connections > 1:
				queue.append(new_pos)

	# 收集 BFS 后剩余的未使用场景作为 fallback 池（供后续连接填补使用）
	var fallback_pool: Array[map_attribute] = []
	fallback_pool.append_array(main_pool)
	fallback_pool.append_array(transition_pool)

	# ---- 第三步：放置传送场景（群系边缘） ----
	if teleport_attr != null and not teleport_placed:
		var teleport_pos := _find_teleport_position(placed, biome)
		if teleport_pos == Vector2i(-1, -1):
			# 退路：在已放置区域的边缘外直接找一个空闲格
			teleport_pos = _find_edge_cell_near(placed)
		if teleport_pos != Vector2i(-1, -1):
			_place_scene(teleport_pos, teleport_attr.scene_name, bname)
			teleport_placed = true
			# 将传送场景连接到最近的已放置场景
			var connected := _connect_to_nearest(teleport_pos, placed, teleport_attr)
			if connected > 0:
				placed.append(teleport_pos)
				# 传送场景需要 3-4 连接，如果还不够，尝试扩充
				var existing := _count_connections(teleport_pos)
				var need_more := teleport_attr.min_connections - existing
				if need_more > 0:
					_try_fill_connections(teleport_pos, need_more, teleport_attr.max_connections - existing, bname, fallback_pool)

	# ---- 第四步：补充连接数不足的场景 ----
	# 遍历已放置的场景，确保每个都达到 min_connections
	for pos in placed:
		var attr := _find_attr_for_name(_cell_name(pos))
		if attr == null:
			continue
		var cur_conn := _count_connections(pos)
		var deficit := attr.min_connections - cur_conn
		if deficit > 0:
			_try_fill_connections(pos, deficit, attr.max_connections - cur_conn, bname, fallback_pool)

	# 记录群系位置
	_biome_positions[bname] = placed
	_biomes_placed += 1
	print("[MapPositionCreate] 群系 ", bname, " 生成完毕，放置 ", placed.size(), " 个场景。")


## === 网格操作 ===

func _place_scene(pos: Vector2i, scene_name: String, biome_name: String = "") -> void:
	map[pos.x][pos.y] = scene_name
	if not biome_name.is_empty():
		_pos_biome[pos] = biome_name


func _cell_name(pos: Vector2i) -> String:
	return map[pos.x][pos.y]


func _is_void(pos: Vector2i) -> bool:
	return pos.x < 0 or pos.x >= _grid_rows or pos.y < 0 or pos.y >= _grid_cols or map[pos.x][pos.y] == "void"


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _grid_rows and pos.y >= 0 and pos.y < _grid_cols


## === 连接操作 ===

func _add_connection(from: Vector2i, to: Vector2i, dir_idx: int) -> void:
	if not scene_to_scene.has(from):
		scene_to_scene[from] = [0, 0, 0, 0]
	if not scene_to_scene.has(to):
		scene_to_scene[to] = [0, 0, 0, 0]
	scene_to_scene[from][dir_idx] = 1
	scene_to_scene[to][OPPOSITE_DIR[dir_idx]] = 1


## 移除 pos_a → pos_b 方向的连接（自动处理双向）
func _remove_connection(pos_a: Vector2i, pos_b: Vector2i, dir_a_to_b: int) -> void:
	if scene_to_scene.has(pos_a):
		scene_to_scene[pos_a][dir_a_to_b] = 0
	if scene_to_scene.has(pos_b):
		scene_to_scene[pos_b][OPPOSITE_DIR[dir_a_to_b]] = 0


func _count_connections(pos: Vector2i) -> int:
	if not scene_to_scene.has(pos):
		return 0
	var cnt := 0
	for v in scene_to_scene[pos]:
		if int(v) == 1:
			cnt += 1
	return cnt


## 返回 pos 四周空闲（且未被占用）方向的索引列表
func _get_free_directions(pos: Vector2i) -> Array[int]:
	var free: Array[int] = []
	for i in range(4):
		var neighbor := pos + DIR_OFFSETS[i]
		if _in_bounds(neighbor) and _is_void(neighbor):
			free.append(i)
	return free


## Fisher-Yates 洗牌
func _free_directions_shuffle(dirs: Array) -> void:
	for i in range(dirs.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var tmp = dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp


## === 场景属性查询 ===

func _find_attr_for_name(scene_name: String) -> map_attribute:
	if map_types_ref == null:
		return null
	return map_types_ref.from_name_get_attribute(scene_name)


## === 锚点与传送场景定位 ===

## 在任意已生成区域的边缘找一个空闲格，用作新群系的起点（通用退路）
func _find_edge_anchor() -> Vector2i:
	# 收集所有已放置位置
	var all_placed: Array[Vector2i] = []
	for pos_list in _biome_positions.values():
		all_placed.append_array(pos_list)

	if all_placed.is_empty():
		return Vector2i(-1, -1)

	# 按距离中心排序，优先取边缘位置
	all_placed.sort_custom(func(a, b): return a.distance_squared_to(Vector2i(_grid_rows/2, _grid_cols/2)) > b.distance_squared_to(Vector2i(_grid_rows/2, _grid_cols/2)))

	# 从最外层位置向外找空闲格
	for pos in all_placed:
		var free_dirs := _get_free_directions(pos)
		_free_directions_shuffle(free_dirs)
		for d in free_dirs:
			var candidate: Vector2i = pos + DIR_OFFSETS[d]
			# 候选锚点应当有足够的拓展空间（至少 2 个空闲相邻格）
			var free_neighbors := _get_free_directions(candidate)
			if free_neighbors.size() >= 2:
				return candidate

	return Vector2i(-1, -1)


## 在指定群系边缘找一个空闲格，确保新群系与目标群系相邻
func _find_edge_anchor_near_biome(target_biome: String) -> Vector2i:
	var target_positions: Array = _biome_positions.get(target_biome, [])
	if target_positions.is_empty():
		return Vector2i(-1, -1)

	# 按距离中心排序，优先取目标群系的边缘位置
	target_positions.sort_custom(func(a, b): return a.distance_squared_to(Vector2i(_grid_rows/2, _grid_cols/2)) > b.distance_squared_to(Vector2i(_grid_rows/2, _grid_cols/2)))

	# 第一轮：需要 ≥2 空闲相邻格（足够拓展空间）
	for pos in target_positions:
		var pos_v: Vector2i = pos as Vector2i
		var free_dirs := _get_free_directions(pos_v)
		_free_directions_shuffle(free_dirs)
		for d in free_dirs:
			var candidate: Vector2i = pos_v + DIR_OFFSETS[d]
			var free_neighbors := _get_free_directions(candidate)
			if free_neighbors.size() >= 2:
				return candidate

	# 第二轮：放宽条件，只需 ≥1 空闲相邻格
	for pos in target_positions:
		var pos_v: Vector2i = pos as Vector2i
		var free_dirs := _get_free_directions(pos_v)
		_free_directions_shuffle(free_dirs)
		for d in free_dirs:
			var candidate: Vector2i = pos_v + DIR_OFFSETS[d]
			var free_neighbors := _get_free_directions(candidate)
			if free_neighbors.size() >= 1:
				return candidate

	return Vector2i(-1, -1)


## 为传送场景找一个合适的位置 — 群系边缘、有空闲相邻格、距离群系中心较远
func _find_teleport_position(placed: Array[Vector2i], _biome: BiomeDefinition) -> Vector2i:
	if placed.is_empty():
		return Vector2i(-1, -1)

	# 计算群系质心
	var centroid := Vector2i(0, 0)
	for p in placed:
		centroid += p
	centroid = Vector2i(centroid.x / placed.size(), centroid.y / placed.size())

	# 按距离质心从远到近排序
	var sorted := placed.duplicate()
	sorted.sort_custom(func(a, b): return a.distance_squared_to(centroid) > b.distance_squared_to(centroid))

	# 从最远的已放置场景向外找
	for pos in sorted:
		var free_dirs := _get_free_directions(pos)
		_free_directions_shuffle(free_dirs)
		for d in free_dirs:
			var candidate: Vector2i = pos + DIR_OFFSETS[d]
			var free_neighbors := _get_free_directions(candidate)
			# 传送场景需要 3-4 连接，候选位置至少要有 3 个空闲相邻格
			if free_neighbors.size() >= 3:
				return candidate

	return Vector2i(-1, -1)


## 在已放置区域附近找一个空闲格（退路方案）
func _find_edge_cell_near(placed: Array[Vector2i]) -> Vector2i:
	for pos in placed:
		var free_dirs := _get_free_directions(pos)
		if not free_dirs.is_empty():
			_free_directions_shuffle(free_dirs)
			return pos + DIR_OFFSETS[free_dirs[0]]
	return Vector2i(-1, -1)


## === 连接修补 ===

## 将新位置连接到最近的已放置场景（至少 1 个）
func _connect_to_nearest(new_pos: Vector2i, placed: Array[Vector2i], _attr: map_attribute) -> int:
	# 找相邻的已放置场景
	var connected := 0
	var free_dirs := _get_free_directions(new_pos)  # 不会包含新位置自己，但我们检查对面
	for i in range(4):
		var neighbor := new_pos + DIR_OFFSETS[i]
		if not _in_bounds(neighbor) or _is_void(neighbor):
			continue
		# 相邻格已被占用 → 建立连接
		if placed.has(neighbor):
			_add_connection(new_pos, neighbor, i)
			connected += 1
	return connected


## 尝试将一个场景的连接数补到目标值，使用当前群系未用完的场景作为填充
func _try_fill_connections(pos: Vector2i, needed: int, room: int, biome_name: String, fallback_pool: Array[map_attribute]) -> void:
	if needed <= 0 or room <= 0:
		return

	var free_dirs := _get_free_directions(pos)
	_free_directions_shuffle(free_dirs)

	var added := 0
	for d in free_dirs:
		if added >= needed or added >= room:
			break
		if fallback_pool.is_empty():
			break
		var neighbor: Vector2i = pos + DIR_OFFSETS[d]
		var leaf_attr: map_attribute = fallback_pool.pop_front()
		_place_scene(neighbor, leaf_attr.scene_name, biome_name)
		_add_connection(pos, neighbor, d)
		added += 1


## === 跨群系连接约束 ===

## 确保 normal 群系与每个其他群系之间有且仅有一个通道
func _enforce_normal_inter_biome_connections() -> void:
	var normal_positions: Array = _biome_positions.get("normal", [])
	if normal_positions.is_empty():
		push_warning("[MapPositionCreate] normal 群系无已放置场景，跳过跨群系连接约束。")
		return

	for bname in _biome_positions.keys():
		if bname == "normal":
			continue
		var other_positions: Array = _biome_positions[bname]
		if other_positions.is_empty():
			continue

		# 收集 normal ↔ bname 之间所有已存在的跨群系连接
		var cross_conns: Array = []  ## 跨群系连接列表 [{normal_pos, other_pos, dir}]
		for pos in normal_positions:
			if not scene_to_scene.has(pos):
				continue
			for dir_idx in range(4):
				if int(scene_to_scene[pos][dir_idx]) != 1:
					continue
				var pos_v: Vector2i = pos as Vector2i
				var neighbor: Vector2i = pos_v + DIR_OFFSETS[dir_idx]
				if not _in_bounds(neighbor):
					continue
				if _pos_biome.get(neighbor, "") == bname:
					var conn: Dictionary = {}
					conn["normal_pos"] = pos
					conn["other_pos"] = neighbor
					conn["dir"] = dir_idx
					cross_conns.append(conn)

		print("[MapPositionCreate] normal ↔ ", bname, " 跨群系连接数: ", cross_conns.size())

		if cross_conns.size() == 1:
			continue  # 恰好一个，完美

		if cross_conns.size() > 1:
			# 保留第一个，移除其余多余的跨群系连接
			for i in range(1, cross_conns.size()):
				var conn: Dictionary = cross_conns[i]
				_remove_connection(conn["normal_pos"], conn["other_pos"], conn["dir"])
				print("[MapPositionCreate] 移除多余跨群系连接: normal ↔ ", bname,
					" (", conn["normal_pos"], " ↔ ", conn["other_pos"], ")")

		if cross_conns.is_empty():
			# 没有连接 → 创建一个
			_create_cross_biome_connection(normal_positions, other_positions, bname)


## 在 normal 群系和 target 群系之间创建一个新连接
func _create_cross_biome_connection(normal_positions: Array, other_positions: Array, other_bname: String) -> void:
	for normal_pos in normal_positions:
		for dir_idx in range(4):
			var normal_v: Vector2i = normal_pos as Vector2i
			var neighbor: Vector2i = normal_v + DIR_OFFSETS[dir_idx]
			if not _in_bounds(neighbor) or _is_void(neighbor):
				continue
			if _pos_biome.get(neighbor, "") != other_bname:
				continue
			# 检查是否已经连接
			if scene_to_scene.has(normal_v) and int(scene_to_scene[normal_v][dir_idx]) == 1:
				continue
			# 找到合适的相邻对，建立连接
			_add_connection(normal_v, neighbor, dir_idx)
			print("[MapPositionCreate] 创建跨群系连接: normal ↔ ", other_bname,
				" at ", normal_v, " ↔ ", neighbor)
			return

	push_warning("[MapPositionCreate] 无法创建 normal ↔ ", other_bname, " 的跨群系连接：无合适相邻格子。")
