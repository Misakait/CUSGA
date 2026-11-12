@tool
extends McpTestSuite

## 验证预告和实际行动共享选择，覆盖 ATB 连续回合、空技能与死亡补位边界。

## 生产预告组件；无场景树依赖，允许在编辑器测试中直接验证行为。
const CONTROLLER: GDScript = preload("res://scripts/battle_scripts/battle_intent_controller.gd")

## 返回编辑器测试入口名称。
## 返回值：稳定套件名。
func suite_name() -> String:
	return "battle_intent_controller"


## 按固定序列选牌，选牌次数用于检测界面刷新是否偷偷重新随机。
class FakeActor extends Node:
	## 每次选牌返回的资源序列；允许空结果以模拟普通攻击。
	var skills: Array[Resource] = []
	## 选牌调用次数，初始为零。
	var selection_count: int = 0

	## 返回序列中的下一张技能。
	## 返回值：技能资源；序列为空时返回 null。
	func GetRandomCombatSkill() -> Resource:
		selection_count += 1
		return null if skills.is_empty() else skills[(selection_count - 1) % skills.size()]


## 创建带预告标签的角色，交给套件自动释放。
func _actor(skills: Array[Resource]) -> FakeActor:
	# 角色不进入场景树，确保选牌缓存本身没有帧处理依赖。
	var actor: FakeActor = track(FakeActor.new()) as FakeActor
	actor.skills = skills
	# 标签结构与生产怪物一致，避免用字符串断言代替真实界面状态。
	var label: Label = Label.new()
	label.name = "IntentLabel"
	actor.add_child(label)
	return actor


## 重复展示、隐藏和玩家连续回合都不得重选，消费后才生成下一次选择。
## 返回值：无。
func test_preview_matches_consumed_skill_across_refreshes() -> void:
	# 两个不同技能可检测消费顺序是否被刷新打乱。
	var first: Resource = Resource.new()
	var second: Resource = Resource.new()
	var actor: FakeActor = _actor([first, second])
	var controller: RefCounted = CONTROLLER.new()
	controller.Refresh([actor], true)
	controller.Refresh([actor], true)
	controller.Refresh([actor], false)
	assert_false(actor.get_node("IntentLabel").visible, "敌人回合隐藏预告。")
	controller.Refresh([actor], true)
	assert_eq(actor.selection_count, 1, "玩家连续回合也必须保留原计划。")
	assert_eq(controller.Consume(actor), first, "实际行动必须消费预告技能。")
	controller.Refresh([actor], true)
	assert_eq(actor.selection_count, 2, "只有消费以后才能重新选择。")
	assert_eq(controller.Consume(actor), second, "下一次行动使用新计划。")


## 无技能结果同样需要锁定；死亡后立即隐藏，补位不影响存活者的计划。
## 返回值：无。
func test_fallback_death_replacement_and_combat_end() -> void:
	var empty_actor: FakeActor = _actor([])
	var survivor: FakeActor = _actor([Resource.new()])
	var replacement: FakeActor = _actor([Resource.new()])
	var controller: RefCounted = CONTROLLER.new()
	controller.Refresh([empty_actor, survivor], true)
	controller.Refresh([empty_actor, survivor], true)
	assert_eq(empty_actor.selection_count, 1, "空技能也只能选择一次。")
	assert_eq(empty_actor.get_node("IntentLabel").text, "攻击", "普通攻击应显示攻击。")
	assert_eq(controller.Consume(empty_actor), null, "普通攻击继续走原有空技能兜底。")
	controller.Forget(empty_actor)
	assert_false(empty_actor.get_node("IntentLabel").visible, "死亡动画期间不保留预告。")
	controller.Refresh([survivor, replacement], true)
	assert_eq(survivor.selection_count, 1, "补位不能改变存活角色计划。")
	assert_eq(replacement.selection_count, 1, "补位角色立即拥有预告。")
	controller.Clear([survivor, replacement])
	assert_false(survivor.get_node("IntentLabel").visible, "战斗结束隐藏所有预告。")
	controller.Refresh([survivor], true)
	assert_eq(survivor.selection_count, 2, "清理后不得保留上一场战斗的计划。")


## 怪物连续先手时无需等玩家回合，也能每次独立消费一个技能。
## 返回值：无。
func test_fast_actor_can_act_before_first_player_turn() -> void:
	var first: Resource = Resource.new()
	var second: Resource = Resource.new()
	var actor: FakeActor = _actor([first, second])
	var controller: RefCounted = CONTROLLER.new()
	controller.Refresh([actor], false)
	assert_eq(actor.selection_count, 0, "隐藏阶段不提前多选技能。")
	assert_eq(controller.Consume(actor), first, "第一轮先手正常选牌。")
	assert_eq(controller.Consume(actor), second, "连续先手正常推进计划。")


## 分类必须来自卡牌字段，未知技能回退未分类，不根据效果推断。
## 返回值：无。
func test_category_uses_card_metadata_for_all_categories() -> void:
	var controller: RefCounted = CONTROLLER.new()
	var card: Resource = load("res://resources/skill_cards/test_card_2.tres")
	var skill: Resource = card.get("Skill") as Resource
	var original_category: int = int(card.get("CardCategory"))
	# 只修改内存并在断言前恢复，确保测试不会污染编辑器缓存中的生产资源。
	var texts: Array[String] = []
	for category: int in [0, 1, 2, 3, 99]:
		card.set("CardCategory", category)
		texts.append(controller.GetCategoryText(skill))
	card.set("CardCategory", original_category)
	assert_eq(texts, ["未分类", "攻击", "防御", "状态", "未分类"], "预告应逐字复用卡牌分类。")
	assert_eq(controller.GetCategoryText(Resource.new()), "未分类", "没有关联卡牌时不猜测类别。")
