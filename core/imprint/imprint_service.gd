extends RefCounted

## 刻印规则：先按星级权重、再在同星级中等概率抽取，材料优先使用属性卡胚。
## 物品和库存均通过 Resource 与库存组件协议传入，避免持有界面状态。

## 每次刻印消耗的卡胚数量。
const COST_PER_DRAW: int = 1
## 技能卡资源目录。
const CARD_DIRECTORY: String = "res://resources/skill_cards"
## 各星级的基础权重；未配置卡牌的星级不参与当次抽取。
const STAR_WEIGHTS: Dictionary = {3: 780, 4: 200, 5: 20}

## 执行一批刻印；任何预检查失败时均不消耗材料。
## 参数 inventory：玩家库存；element：五行枚举值；specific：属性卡胚；universal：通用卡胚；count：抽取次数。
## 返回值：包含 cards 和 message 的字典。
func draw(inventory: Node, element: int, specific: Resource, universal: Resource, count: int) -> Dictionary:
	if inventory == null or specific == null or universal == null or count <= 0:
		return {"cards": [], "message": "刻印配置无效"}
	var pool: Array[Resource] = _pool_for_element(element)
	if pool.is_empty():
		return {"cards": [], "message": "该属性暂无可刻印的技能卡"}
	var cost: int = count * COST_PER_DRAW
	var specific_count: int = mini(int(inventory.call("ItemCnt", specific)), cost)
	var universal_count: int = cost - specific_count
	if int(inventory.call("ItemCnt", universal)) < universal_count:
		return {"cards": [], "message": "卡胚不足"}
	var selected: Array[Resource] = []
	for index in count:
		selected.append(_pick_card(pool))
	var payment: Dictionary = {}
	if specific_count > 0:
		payment[specific] = specific_count
	if universal_count > 0:
		payment[universal] = universal_count
	if not bool(inventory.call("TryRemoveItems", payment)):
		return {"cards": [], "message": "卡胚不足"}
	# 抽中的卡先交给界面暂存，只有玩家确认选择后才写入库存。
	return {"cards": selected, "message": "刻印成功"}

## 先按星级权重抽取，再在该星级内等概率选择卡牌。
## 参数 pool：同属性且已配置权重的候选卡；返回值：被选中的技能卡。
func _pick_card(pool: Array[Resource]) -> Resource:
	var groups: Dictionary = {}
	for card in pool:
		var star: int = int(card.get("StarLevel"))
		if not STAR_WEIGHTS.has(star):
			continue
		if not groups.has(star):
			groups[star] = []
		groups[star].append(card)
	var total: int = 0
	for star in groups:
		total += int(STAR_WEIGHTS[star])
	if total <= 0:
		return null
	var roll: int = randi_range(1, total)
	for star in STAR_WEIGHTS:
		if groups.has(star):
			roll -= int(STAR_WEIGHTS[star])
			if roll <= 0:
				return groups[star].pick_random()
	return null

## 枚举指定五行且配置了抽取权重的技能卡。
## 参数 element：五行枚举值；返回值：可抽取的卡牌资源数组。
func _pool_for_element(element: int) -> Array[Resource]:
	var result: Array[Resource] = []
	var directory: DirAccess = DirAccess.open(CARD_DIRECTORY)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres") or file_name.begins_with("test_card_"):
			continue
		var card: Resource = load(CARD_DIRECTORY.path_join(file_name))
		if card == null or card.get("Skill") == null:
			continue
		# 目录也可能包含尚未迁移或无星级字段的资源，不能将空值当作整数。
		var card_element: Variant = card.get("Element")
		var card_star: Variant = card.get("StarLevel")
		if card_element is int and card_star is int and card_element == element and STAR_WEIGHTS.has(card_star):
			result.append(card)
	return result
