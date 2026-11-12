extends RefCounted

## 战斗行为预告组件：锁定每个非玩家角色的下一次技能，并把卡牌分类交给角色标签。
## 预告与行动队列共用同一份技能引用，刷新界面不会重新随机。

## 技能卡目录；通过卡牌的 Skill 引用反查分类，不从伤害效果猜测类别。
const SKILL_CARD_DIRECTORY: String = "res://resources/skill_cards/"
## 复用卡面已有的类别文案，保持预告和技能卡文字一致。
const SKILL_CARD_VIEW: GDScript = preload("res://scripts/card_scripts/skill_card.gd")
## 标签位于怪物根节点下，不参与卡面缩放或目标选择动画。
const INTENT_LABEL_PATH: NodePath = ^"IntentLabel"

## 角色到待执行技能的映射；null 也是已锁定结果，表示原有的普通攻击兜底。
var _planned_skills: Dictionary = {}
## 技能资源路径到技能卡资源的索引；保留资源引用以读取其权威 CardCategory。
var _skill_cards: Dictionary = {}
## 目录只在首次展示时扫描，避免每次出牌重新加载全部卡牌。
var _catalog_ready: bool = false


## 刷新在场角色的预告，只有需要显示时才创建尚未存在的计划。
## 参数 actors：在场的非玩家角色；show_intents：当前是否处于玩家回合。
## 返回值：无。
func Refresh(actors: Array, show_intents: bool) -> void:
	for actor: Node in actors:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		# 没有展示节点的兼容角色仍可正常行动，展示层不成为战斗执行的前置条件。
		var label: Label = actor.get_node_or_null(INTENT_LABEL_PATH) as Label
		if label == null:
			continue
		label.visible = show_intents
		if show_intents:
			label.text = GetCategoryText(_get_or_plan(actor))


## 取走角色已经预告的技能；未经过玩家回合的快速角色会在此首次选定。
## 参数 actor：本次行动的非玩家角色。
## 返回值：锁定的技能资源；没有技能时返回 null，沿用普通攻击结算。
func Consume(actor: Node) -> Resource:
	# 必须先取值再清除，下一次行动才允许重新选择；ATB 插队不改变其他角色的计划。
	var skill: Resource = _get_or_plan(actor)
	_planned_skills.erase(actor)
	return skill


## 清理退场角色，死亡表现仍在播放时也立即隐藏预告。
## 参数 actor：已退场或已失效的角色。
## 返回值：无。
func Forget(actor: Node) -> void:
	_planned_skills.erase(actor)
	if is_instance_valid(actor):
		# 死亡动画会暂时保留节点，必须显式隐藏，不能等待节点销毁。
		var label: Label = actor.get_node_or_null(INTENT_LABEL_PATH) as Label
		if label != null:
			label.hide()


## 战斗结束时清理所有计划和仍在场上的标签。
## 参数 actors：当前在场的非玩家角色。
## 返回值：无。
func Clear(actors: Array) -> void:
	Refresh(actors, false)
	_planned_skills.clear()


## 根据将要使用的技能读取对应技能卡分类。
## 参数 skill：锁定的战斗技能；null 表示普通攻击。
## 返回值：攻击、防御、状态或未分类；未知技能和非法类别统一显示未分类。
func GetCategoryText(skill: Resource) -> String:
	if skill == null:
		return SKILL_CARD_VIEW.CATEGORY_DISPLAY_NAMES[SKILL_CARD_VIEW.CATEGORY_ATTACK]
	_ensure_catalog()
	# 资源路径是技能与卡牌的关联键，不把同名的不同技能混为一谈。
	var card: Resource = _skill_cards.get(skill.resource_path) as Resource
	var category: int = SKILL_CARD_VIEW.CATEGORY_UNCLASSIFIED
	if card != null and card.get("CardCategory") is int:
		category = int(card.get("CardCategory"))
	return SKILL_CARD_VIEW.CATEGORY_DISPLAY_NAMES.get(
		category, SKILL_CARD_VIEW.CATEGORY_DISPLAY_NAMES[SKILL_CARD_VIEW.CATEGORY_UNCLASSIFIED]
	)


## 首次请求时随机一次，后续刷新或玩家连续回合都复用该结果。
func _get_or_plan(actor: Node) -> Resource:
	if not _planned_skills.has(actor):
		# 保存空结果，防止无技能角色在每次界面刷新时反复请求选牌。
		var skill: Resource = null
		if actor.has_method("GetRandomCombatSkill"):
			skill = actor.call("GetRandomCombatSkill") as Resource
		_planned_skills[actor] = skill
	return _planned_skills[actor] as Resource


## 使用资源目录接口兼容导出后的资源重映射，重复关联按文件名固定取第一张。
func _ensure_catalog() -> void:
	if _catalog_ready:
		return
	_catalog_ready = true
	# 排序避免目录枚举顺序影响多张卡共用同一技能时的类别选择。
	var files: PackedStringArray = ResourceLoader.list_directory(SKILL_CARD_DIRECTORY)
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		# 卡牌资源已经拥有分类字段，缓存引用即可，不复制一份分类配置。
		var card: Resource = load(SKILL_CARD_DIRECTORY + file_name) as Resource
		if card == null:
			continue
		var skill: Resource = card.get("Skill") as Resource
		if skill != null and not skill.resource_path.is_empty() and not _skill_cards.has(skill.resource_path):
			_skill_cards[skill.resource_path] = card
