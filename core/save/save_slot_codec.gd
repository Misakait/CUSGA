extends RefCounted

## 存档槽位编解码工具（跨运行存档系统的序列化边界）。
##
## 为什么单独抽一个文件：仓库槽位与带入栏条目都是「物品 + 数量（+ 洗炼属性）」，两处各写
## 一份编解码必然分叉（改一处忘另一处，存档格式就会悄悄不一致）。下沉成无状态静态函数后，
## 两个参与者只负责把自己的容器形状转成条目数组。
##
## 为什么物品身份只落 CardId：
## - CardId 是项目里唯一的稳定物品身份，`ItemsControl` 本身就是按它建索引的。
## - 落资源路径会随目录整理失效；用 `ResourceSaver` 落整个 Resource 更糟——那等于把一份
##   内容数据冻结进存档，之后调整物品数值时旧档不会跟随。只落 CardId 才让「改数值」对
##   所有存档同时生效。
##
## 为什么 `lookup` 是注入的 Callable 而不是直接取 autoload：本脚本必须能在 `test_run`
## 环境（没有 autoload、没有 `ItemsControl`）里被完整测试，直接引用 `/root/ItemsControl`
## 会让它不可测。
##
## 洗炼属性（`rolled`）为什么用字符串键：其键是 `AttributeType` 的整型枚举，而 JSON 对象
## 的键只能是字符串，因此写为 `{"0": 15}`。读回时解析为 int 并与该物品 `AttributeBonuses`
## 的键集合求交集——既避免了「枚举 → 字符串 → 枚举」的类型歧义，也顺手挡住了属性表被
## 改动后残留在旧档里的脏数据。

## 物品数据的跨语言字段协议，用于读取 CardId。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 槽位解码结局：存档里是 `null`，语义为「合法的空槽位」，不计入告警。
const STATUS_EMPTY: String = "empty"

## 槽位解码结局：水合成功。
const STATUS_OK: String = "ok"

## 槽位解码结局：结构损坏或物品未知，跳过该槽位并计入告警。
const STATUS_SKIPPED: String = "skipped"

## 条目字典的键名，集中在此避免参与者与编解码各写一份字符串字面量。
const KEY_CARD_ID: String = "card_id"
const KEY_AMOUNT: String = "amount"
const KEY_ROLLED: String = "rolled"

## 跳过原因的稳定前缀，供调用方与测试按前缀区分「未知物品」与「结构损坏」。
const REASON_UNKNOWN_ITEM_PREFIX: String = "unknown_card_id:"


## 把一个物品堆叠编码成存档条目。
##
## 参数 item：物品 Resource；为空时返回 null（空槽位的规范写法）。
## 参数 amount：堆叠数量；非正数时返回 null。
## 参数 rolled：洗炼属性字典，键为 AttributeType 整型枚举；为空时不写入该字段。
## 返回值：形如 {"card_id": String, "amount": int, "rolled": {"0": int}} 的字典；
##   物品无法被稳定标识（没有 CardId）时同样返回 null——存进去也读不回来。
static func encode_entry(item: Resource, amount: int, rolled: Dictionary) -> Variant:
	if item == null or amount <= 0:
		return null

	var card_id: StringName = StringName(ITEM_DATA_COMPAT.call("get_card_id", item, &""))
	if card_id.is_empty():
		return null

	var entry: Dictionary = {KEY_CARD_ID: String(card_id), KEY_AMOUNT: amount}
	var encoded_rolled: Dictionary = {}
	for key: Variant in rolled:
		if not _is_number(key):
			continue
		var value: Variant = rolled[key]
		if not _is_number(value):
			continue
		encoded_rolled[str(int(key))] = int(value)
	if not encoded_rolled.is_empty():
		entry[KEY_ROLLED] = encoded_rolled

	return entry


## 把条目数组编码成存档用的槽位数组。
##
## 参数 entries：条目字典数组，每项形如 {"item": Resource, "amount": int, "rolled": Dictionary}；
##   `rolled` 可省略。非字典项按空槽位处理。
## 返回值：等长的槽位数组，空槽位为 null，顺序即槽位序号。
static func encode_slots(entries: Array) -> Array:
	var encoded: Array = []
	for entry: Variant in entries:
		if not (entry is Dictionary):
			encoded.append(null)
			continue
		var source: Dictionary = entry
		var item: Resource = source.get("item") as Resource
		var amount: int = int(source.get("amount", 0))
		var rolled_raw: Variant = source.get(KEY_ROLLED)
		var rolled: Dictionary = rolled_raw if rolled_raw is Dictionary else {}
		encoded.append(encode_entry(item, amount, rolled))

	return encoded


## 把 ItemStack 协议对象转成条目字典。
##
## 参数 stack：任意实现 `IsEmpty` / `Item` / `Amount` / `RolledAttributes` 协议的堆叠对象。
## 返回值：条目字典；空堆叠或协议不完整时返回 {"item": null, "amount": 0, "rolled": {}}。
static func stack_to_entry(stack: Variant) -> Dictionary:
	var empty_entry: Dictionary = {"item": null, "amount": 0, KEY_ROLLED: {}}
	if stack == null or not (stack is Object):
		return empty_entry
	if bool(stack.get("IsEmpty")):
		return empty_entry

	var item: Resource = stack.get("Item") as Resource
	if item == null:
		return empty_entry

	var rolled_raw: Variant = stack.get("RolledAttributes")
	var rolled: Dictionary = rolled_raw if rolled_raw is Dictionary else {}
	return {"item": item, "amount": int(stack.get("Amount")), KEY_ROLLED: rolled}


## 解码单个槽位。
##
## 参数 raw：存档里的槽位原始值；`null` 表示合法的空槽位。
## 参数 lookup：`card_id -> Resource` 的查表函数；不可用时该槽位按跳过处理。
## 返回值：三态字典之一：
##   {"status": "empty"}
##   {"status": "ok", "item": Resource, "amount": int, "rolled": Dictionary, "rolled_dropped": int}
##   {"status": "skipped", "reason": String}
## 之所以用三态而不是 bool：`null` 槽位是**合法**的空槽位，与「结构损坏被跳过」必须能
## 区分开，否则调用方会把正常空档位也报成告警。
static func decode_entry(raw: Variant, lookup: Callable) -> Dictionary:
	if raw == null:
		return {"status": STATUS_EMPTY}

	if not (raw is Dictionary):
		return _skipped("槽位不是对象")

	var entry: Dictionary = raw
	var card_id_raw: Variant = entry.get(KEY_CARD_ID)
	if not (card_id_raw is String) or String(card_id_raw).is_empty():
		return _skipped("槽位缺少 card_id")

	var card_id_text: String = String(card_id_raw)
	if not lookup.is_valid():
		return _skipped("物品查表函数不可用")

	var looked_up: Variant = lookup.call(StringName(card_id_text))
	if not (looked_up is Resource):
		return _skipped(REASON_UNKNOWN_ITEM_PREFIX + card_id_text)
	var item: Resource = looked_up

	var amount_raw: Variant = entry.get(KEY_AMOUNT)
	if not _is_number(amount_raw):
		return _skipped("数量不是数值")
	var amount: int = int(amount_raw)
	if amount <= 0:
		return _skipped("数量非正")

	var rolled: Dictionary = {}
	var dropped: int = 0
	var rolled_raw: Variant = entry.get(KEY_ROLLED)
	if rolled_raw is Dictionary:
		dropped = _decode_rolled(rolled_raw, item, rolled)

	return {
		"status": STATUS_OK,
		"item": item,
		"amount": amount,
		KEY_ROLLED: rolled,
		"rolled_dropped": dropped,
	}


## 解码整个槽位数组。
##
## 参数 raw_slots：存档里的 `slots` 字段；不是数组时整体判定为不可用。
## 参数 slot_count：期望的槽位数（调用方当前容量）。
## 参数 lookup：`card_id -> Resource` 的查表函数。
## 返回值：{"ok": bool, "entries": Array, "skipped": int, "rolled_dropped": int,
##   "reasons": Array[String]}。
##   `ok` 只表达「槽位结构本身可用」；个别槽位被跳过不影响它（存档里某件物品被删掉不应
##   让整份进度作废）。`entries` 的长度取 `max(slot_count, 存档槽位数)`——存档条数多于此
##   时**不截断**，交回给调用方扩容，否则会静默丢掉玩家存在高序号槽位里的物品。
static func decode_slots(raw_slots: Variant, slot_count: int, lookup: Callable) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"entries": [],
		"skipped": 0,
		"rolled_dropped": 0,
		"reasons": [],
	}
	if not (raw_slots is Array):
		var reasons: Array = result["reasons"]
		reasons.append("存档的 slots 不是数组")
		return result

	var slots: Array = raw_slots
	var count: int = maxi(slot_count, slots.size())
	var entries: Array = result["entries"]
	var all_reasons: Array = result["reasons"]
	var skipped: int = 0
	var rolled_dropped: int = 0

	for index: int in count:
		if index >= slots.size():
			entries.append({"status": STATUS_EMPTY})
			continue

		var decoded: Dictionary = decode_entry(slots[index], lookup)
		entries.append(decoded)
		if String(decoded.get("status", "")) == STATUS_SKIPPED:
			skipped += 1
			all_reasons.append("槽位 %d：%s" % [index, String(decoded.get("reason", ""))])
		else:
			rolled_dropped += int(decoded.get("rolled_dropped", 0))

	result["skipped"] = skipped
	result["rolled_dropped"] = rolled_dropped
	result["ok"] = true
	return result


## 构造一个「跳过」结局，避免各处手写 status/reason 字段名。
##
## 参数 reason：可诊断的跳过原因。
## 返回值：{"status": "skipped", "reason": reason}。
static func _skipped(reason: String) -> Dictionary:
	return {"status": STATUS_SKIPPED, "reason": reason}


## 解码洗炼属性：消除类型歧义，并（在可判断时）按物品声明的属性集合求交集。
##
## 参数 raw：存档里的 `rolled` 字典，键为十进制字符串。
## 参数 item：已水合的物品 Resource，用于取得属性声明白名单。
## 参数 out_rolled：输出参数字典，就地写入保留下来的 {"AttributeType": int}。
## 返回值：被丢弃的键数量（非数值、非整数键、不在白名单内的都计入）。
static func _decode_rolled(raw: Dictionary, item: Resource, out_rolled: Dictionary) -> int:
	var whitelist: Array = _rolled_whitelist(item)
	var dropped: int = 0

	for key: Variant in raw:
		var value: Variant = raw[key]
		if not _is_number(value):
			dropped += 1
			continue

		var key_text: String = String(key)
		if not key_text.is_valid_int():
			dropped += 1
			continue

		var attribute_type: int = int(key_text)
		# 白名单为空表示「无法判断该物品能有哪些属性」，此时**不做交集**：
		# 「无法判断」不等于「非法」，丢弃判断不了的数据远比留下一个可能已无意义的键危险。
		# 回归依据：2026-09-24 运行期验证时发现，无条件求交集会把普通物品（没有
		# AttributeBonuses）上的洗炼属性全部销毁。
		if not whitelist.is_empty() and not whitelist.has(attribute_type):
			dropped += 1
			continue

		out_rolled[attribute_type] = int(value)

	return dropped


## 读取物品声明可洗炼的属性键集合。
##
## 参数 item：物品 Resource，可为 null。
## 返回值：`AttributeBonuses` 的键数组；该字段缺失、不是字典或为空时返回空数组，
##   调用方一律按「没有白名单、不做交集」处理（见 `_decode_rolled`）。
static func _rolled_whitelist(item: Resource) -> Array:
	if item == null or not (item is Object):
		return []

	var bonuses: Variant = (item as Object).get("AttributeBonuses")
	if not (bonuses is Dictionary):
		return []

	return (bonuses as Dictionary).keys()


## 判断 Variant 是否为可参与整数运算的数值。
##
## JSON 解析出的数字统一是 float，因此每个数值字段都必须经过这一层判定再 int()，
## 否则字符串或 null 会被静默转成 0。
##
## 参数 value：待判定的 Variant。
## 返回值：整数或浮点数时为 true。
static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
