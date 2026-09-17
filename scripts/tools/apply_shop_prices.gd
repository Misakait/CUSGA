extends SceneTree

## 一次性工具：为局外商店批量写入物品买价与卖价。
##
## 用法：
##   godot --headless --path . --script res://scripts/tools/apply_shop_prices.gd
##
## 保留在仓库里作为价格的唯一可复现来源：价格规则调整后重跑本脚本即可，不需要手工编辑 88 个 .tres。
## 价格规则与商品名单的决策依据见 .trellis/tasks/09-17-outdoor-shop/design.md 第 2 节。
##
## 为什么用文本插入而不是 ResourceSaver.save：
## 在非编辑器上下文（--script）里保存资源时，Godot 不会写回 uid，实测会把 [gd_resource] 的 uid
## 以及全部 [ext_resource] 的 uid 一并删掉，等于篡改了资源的身份。文本插入只增加两行属性，
## 其余内容（含 uid 与既有属性顺序）逐字节保持不变，因此 diff 可逐行审阅。
## 这也是本脚本必须先读文本、再按行重建的原因，不能用 load + save 的常规写法。

## 商品根目录。
const ITEMS_ROOT := "res://items"

## 期望被写入价格的商品数量。
## 写死这个数字是为了让规则表被误改（例如把环境物算进商品）时脚本直接失败，而不是静默少刷。
const EXPECTED_WRITTEN := 88

## 整目录排除：environment 下是树木、石壁、矿体这类地图地形物，不是商品。
const EXCLUDED_DIRS: Array[String] = ["environment"]

## 单独排除：CardId 为 "1"/"2"/"3" 的测试物品。
const EXCLUDED_FILES: Array[String] = ["item1", "item2", "item3"]

## 元素材料统一价。
const ELEMENT_PRICE := 150

## 装备与工具的品阶基准价，按文件名前缀判定。
const TIER_BASE := {
	"Leather": 80,
	"Iron": 240,
	"Golden": 700,
	"Gloden": 700, # 资源里存在拼写不一致的 GlodenHelmet，按同一品阶处理
}

## 装备部位系数。
const EQUIP_SLOT_COEFFICIENT := {
	"Helmet": 1.00,
	"Breastplate": 1.50,
	"Legguard": 1.20,
	"Shoes": 0.80,
	"Handguard": 0.70,
	"Belt": 0.90,
	"Necklace": 1.10,
	"Ring": 0.80,
}

## 工具类型系数。
const TOOL_TYPE_COEFFICIENT := {
	"Sword": 1.30,
	"Hammer": 1.35,
	"Pickaxe": 1.15,
	"Ax": 1.15,
	"Truncheon": 0.90,
	"Shovel": 0.90,
	"FishingRod": 0.90,
}

## 无品阶前缀的基础工具与石制工具共用的基准价。
const BASE_TOOL_PRICE := 80

## 价格插入锚点：写在 [resource] 段的 script 属性之后。
const SCRIPT_PROPERTY_PREFIX := "script = "

## items 目录下的消耗品与材料按稀有度分档，逐项显式列出。
## 显式列出而不是靠文件名猜，是因为这些物品的稀有度无法从名字可靠推导。
const ITEM_PRICES := {
	# 凡品：基础采集物
	"leaf": 20,
	"branch": 20,
	"littlerock": 20,
	"sand": 20,
	"snow": 20,
	"ice": 20,
	"powder": 20,
	"berry": 20,
	"apple": 20,
	"wheat": 20,
	"sugarcane": 20,
	"aloe": 20,
	"bug": 20,
	"birdegg": 20,
	# 良品：可直接食用或经一次加工的食材
	"fish": 60,
	"applechips": 60,
	"applecore": 60,
	"bakedapplecore": 60,
	"cookedmeat": 60,
	"roastfish": 60,
	"processedfish": 60,
	"deliciousfish": 60,
	"broth": 60,
	"fishsoup": 60,
	"eggsoup": 60,
	"delicioussoup": 60,
	"leather": 60,
	# 器物：容器、火把与金属锭
	"woodenbowl": 150,
	"stonebowl": 150,
	"flametorch": 150,
	"ironingot": 150,
	"goldingot": 150,
	# 道具：野外生存用具
	"sleepingbag": 90,
	"tent": 90,
	# 极品：药剂
	"lifepotion": 300,
	"magicpotion": 300,
}


func _initialize() -> void:
	var paths := _collect_tres_paths(ITEMS_ROOT)
	# 排序让每次运行的写入顺序与输出一致，便于比对两次刷价的结果差异。
	paths.sort()

	var written := 0
	var skipped := 0
	var failed := 0

	for path in paths:
		if _is_excluded(path):
			skipped += 1
			continue

		var buy_price := _resolve_buy_price(path)
		if buy_price <= 0:
			# 能走到这里说明商品名单里多了一个没有价格规则的物品，必须报错而不是静默漏刷。
			push_error("apply_shop_prices: 未识别的商品，缺少价格规则：%s" % path)
			failed += 1
			continue

		# 卖价统一按买价折半向下取整，与 ShopService.ResolveSellPrice 的回退规则保持一致。
		if not _write_prices(path, buy_price, int(buy_price / 2)):
			failed += 1
			continue

		written += 1

	print("apply_shop_prices: 写入 %d，跳过 %d，失败 %d（期望写入 %d）" % [written, skipped, failed, EXPECTED_WRITTEN])

	# 自校验：重新从磁盘强制加载，确认 Godot 真的读到了刚写入的两个属性。
	# 只靠写入成功不足以证明属性名与类型正确，必须由引擎实际反序列化一次。
	var verify_failures := _verify_written_prices(paths)
	if verify_failures > 0:
		failed += verify_failures

	if failed > 0 or written != EXPECTED_WRITTEN:
		push_error("apply_shop_prices: 结果与期望不符，请检查商品名单与价格规则。")
		quit(1)
		return

	print("apply_shop_prices: 全部 %d 个商品自校验通过。" % written)
	quit(0)


## 递归收集目录下所有 .tres 的 res:// 路径。
## @param dir_path 起始目录的 res:// 路径。
## @return PackedStringArray 找到的 .tres 路径列表；目录打不开时返回空列表。
func _collect_tres_paths(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("apply_shop_prices: 无法打开目录 %s" % dir_path)
		return result

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := dir_path.path_join(entry)
			if dir.current_is_dir():
				result.append_array(_collect_tres_paths(full_path))
			elif entry.ends_with(".tres"):
				result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

	return result


## 判断某个资源是否明确不属于商品。
## @param path 资源的 res:// 路径。
## @return bool 属于被排除的地形物或测试物品时返回 true。
func _is_excluded(path: String) -> bool:
	var dir_name := path.get_base_dir().get_file()
	var file_name := path.get_file().get_basename()
	return EXCLUDED_DIRS.has(dir_name) or EXCLUDED_FILES.has(file_name)


## 按所在目录与文件名解析买价。
## @param path 资源的 res:// 路径。
## @return int 买价；无法识别时返回 -1，由调用方报错。
func _resolve_buy_price(path: String) -> int:
	var dir_name := path.get_base_dir().get_file()
	var file_name := path.get_file().get_basename()

	match dir_name:
		"element":
			return ELEMENT_PRICE
		"equip":
			return _resolve_equip_price(file_name)
		"tool":
			return _resolve_tool_price(file_name)
		"items":
			return int(ITEM_PRICES.get(file_name, -1))
		_:
			return -1


## 装备价格 = 品阶基准 × 部位系数。
## @param file_name 资源文件名（不含扩展名）。
## @return int 买价；品阶或部位无法识别时返回 -1。
func _resolve_equip_price(file_name: String) -> int:
	var base_price := _resolve_tier_base(file_name)
	if base_price <= 0:
		return -1

	# 部位按关键字匹配而不是等值匹配：护手、护腿、鞋子都有 _left / _right 后缀。
	for slot_key in EQUIP_SLOT_COEFFICIENT:
		if file_name.contains(slot_key):
			return int(round(base_price * float(EQUIP_SLOT_COEFFICIENT[slot_key])))

	return -1


## 工具价格 = 品阶基准 × 类型系数，再取整到十位让价格好读。
## @param file_name 资源文件名（不含扩展名）。
## @return int 买价；类型无法识别时返回 -1。
func _resolve_tool_price(file_name: String) -> int:
	var base_price := _resolve_tier_base(file_name)
	if base_price <= 0:
		base_price = BASE_TOOL_PRICE

	# 先判 Pickaxe 再判 Ax：Pickaxe 的小写 "axe" 不会误命中 "Ax"，但顺序写清楚可以避免日后改成小写匹配时出错。
	for type_key in TOOL_TYPE_COEFFICIENT:
		if file_name.contains(type_key):
			return int(round(base_price * float(TOOL_TYPE_COEFFICIENT[type_key]) / 10.0)) * 10

	return -1


## 按文件名前缀解析品阶基准价。
## @param file_name 资源文件名（不含扩展名）。
## @return int 品阶基准价；没有匹配的前缀时返回 -1（由调用方回退到基础价）。
func _resolve_tier_base(file_name: String) -> int:
	for prefix in TIER_BASE:
		if file_name.begins_with(prefix):
			return int(TIER_BASE[prefix])

	return -1


## 把买价与卖价两行插入到 .tres 的 [resource] 段中。
## @param path 资源的 res:// 路径。
## @param buy_price 买价。
## @param sell_price 卖价。
## @return bool 写入成功时返回 true。
func _write_prices(path: String, buy_price: int, sell_price: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("apply_shop_prices: 无法读取 %s" % path)
		return false

	var original := file.get_as_text()
	file.close()

	# .tres 全部是 LF，因此按 \n 切分再按 \n 拼回可以逐字节保留原有换行风格。
	var lines := original.split("\n")

	# 先剔除上一次运行写入的价格行，让本脚本可以反复执行而不产生重复属性。
	var stripped := PackedStringArray()
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("BuyPrice = ") or trimmed.begins_with("SellPrice = "):
			continue
		stripped.append(line)

	var script_line := _find_resource_script_line(stripped)
	if script_line < 0:
		push_error("apply_shop_prices: 在 [resource] 段里找不到 script 属性：%s" % path)
		return false

	var rebuilt := PackedStringArray()
	rebuilt.append_array(stripped.slice(0, script_line + 1))
	rebuilt.append("BuyPrice = %d" % buy_price)
	rebuilt.append("SellPrice = %d" % sell_price)
	rebuilt.append_array(stripped.slice(script_line + 1))

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("apply_shop_prices: 无法写入 %s" % path)
		return false

	out.store_string("\n".join(rebuilt))
	out.close()
	return true


## 定位 [resource] 段里 script 属性所在的行号。
## @param lines 已按行切分的 .tres 文本。
## @return int 行号；找不到时返回 -1。
## @remarks
## 必须限定在 [resource] 段内查找：写在段外的属性不会被 Godot 当作资源属性读取。
func _find_resource_script_line(lines: PackedStringArray) -> int:
	var section_index := -1
	for i in lines.size():
		if lines[i].strip_edges() == "[resource]":
			section_index = i
			break

	if section_index < 0:
		return -1

	for i in range(section_index + 1, lines.size()):
		var trimmed := lines[i].strip_edges()
		# 撞到下一个段头说明 [resource] 段里没有 script 行。
		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			return -1
		if trimmed.begins_with(SCRIPT_PROPERTY_PREFIX):
			return i

	return -1


## 重新从磁盘加载所有商品资源，确认价格属性真的被 Godot 读到。
## @param paths 全部 .tres 路径。
## @return int 校验失败的数量。
func _verify_written_prices(paths: PackedStringArray) -> int:
	var failures := 0
	for path in paths:
		if _is_excluded(path):
			continue

		var expected := _resolve_buy_price(path)
		if expected <= 0:
			continue

		# CACHE_MODE_IGNORE 绕开资源缓存，强制从磁盘重新反序列化，否则校验的只是内存对象。
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null or not (resource is ItemData):
			push_error("apply_shop_prices: 自校验无法加载 %s" % path)
			failures += 1
			continue

		var item := resource as ItemData
		if item.BuyPrice != expected or item.SellPrice != int(expected / 2):
			push_error(
				"apply_shop_prices: 自校验价格不符 %s（读回 BuyPrice=%d SellPrice=%d，期望 %d/%d）"
				% [path, item.BuyPrice, item.SellPrice, expected, int(expected / 2)]
			)
			failures += 1

	return failures
