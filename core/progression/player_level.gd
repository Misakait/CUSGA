extends Node

## 玩家等级与经验值 Autoload 的 GDScript 生产实现。
##
## 本脚本只拥有「等级 / 当前经验 / 待发放属性点」三项数值与线性经验曲线规则，
## 不引用玩家实体、场景节点或任何 UI。升级产生的属性点以「挂起 + 领取」协议对外暴露：
## 消费方（entities/player.gd）收到 AttributePointsGranted 后调用
## ClaimPendingAttributePoints() 领取，再交给自己的 AttributeComponent.EarnPoints 发放。
##
## 之所以把发点设计成「谁需要谁来领」而不是由本脚本主动推送，是因为等级规则层不应该
## 知道玩家在哪里——主动推送就必须在全局规则里做实体查找，把实体耦合引进最需要保持纯粹的
## 那一层。领取模型还顺带解决了「玩家比升级晚出现」的时序问题：未被领取的点数一直挂起，
## 玩家进入场景补领即可，既不会丢失也不会重复发放。

## 玩家设置文件中等级数据所属的分组，与 PlayerWallet、PlayerProgression 同组。
const SettingsSection: String = "player"

## 等级存档键；发布后不可随意修改，否则旧存档会读不到等级。
const LevelKey: String = "level"

## 当前等级内经验存档键；发布后不可随意修改。
const ExperienceKey: String = "experience"

## 开发期不跨运行保存，必须与 PlayerWallet 以及 PlayerProgression 的策略保持同值。
## 改为 true 即启用跨运行保存，存档校验与写入逻辑无需改动。
const PersistAcrossRuns: bool = false

## 最低等级，同时作为新档初始等级。
const MinLevel: int = 1

## 满级等级；达到该等级后不再累积经验。
const MaxLevel: int = 50

## 从 MinLevel 升到下一级所需的基础经验。
const BaseExperienceRequirement: int = 100

## 每高一级增加的所需经验，与基础值共同构成 100/150/200… 的线性曲线。
const ExperienceRequirementStep: int = 50

## 每提升一级发放的属性点数量；改变它会影响满级累计可获得的属性点总量。
const AttributePointsPerLevel: int = 3

## 等级变化信号，参数为变化后的等级；连续升多级时逐级发出。
signal LevelChanged(level: int)

## 经验变化信号，参数为当前等级内已累积经验与升到下一级所需经验。
signal ExperienceChanged(current_experience: int, required_experience: int)

## 属性点发放信号，参数为当前全部可领取的挂起属性点总数（不是本次增量）。
## 携带总数而非增量是有意为之：消费方无论漏接几次信号，只要在任意一次信号后领取，
## 就能拿到全部挂起值，领取与发放在数量上天然对齐，不需要增量累加与去重逻辑。
signal AttributePointsGranted(pending_points: int)

## 当前等级，取值 MinLevel..MaxLevel。
var Level: int = MinLevel

## 当前等级内已累积的经验，始终小于本级升级需求。
var CurrentExperience: int = 0

## 已发放但尚未被玩家领取的属性点；被领取后清零。
var PendingAttributePoints: int = 0

## SettingsManager Autoload 缓存；缺失时仅影响跨运行保存，不阻断本次运行。
var _settings_manager: Node = null


## 解析设置服务并读取既有等级进度。
## @return void。
func _ready() -> void:
	_settings_manager = get_node_or_null("/root/SettingsManager")
	if _settings_manager == null:
		push_error("PlayerLevel: 未找到 SettingsManager，等级与经验将只在本次运行内有效。")

	if not PersistAcrossRuns:
		_clear_stored_progress()

	# 等级必须先于经验读取：经验校验需要依赖已经确定的等级来推算本级需求。
	Level = _read_stored_level()
	CurrentExperience = _read_stored_experience()


## 获得经验值，并按曲线连续结算升级。
## @param amount 要获得的经验值；非正数会被忽略。
## @return 实际入账的经验值；非正数或已满级时返回 0。
func AddExperience(amount: int) -> int:
	if amount <= 0:
		return 0

	# 满级后不再累积经验：直接短路，避免发出无人消费的经验变更信号。
	if IsMaxLevel():
		return 0

	CurrentExperience += amount
	_settle_level_ups()
	_persist()
	ExperienceChanged.emit(CurrentExperience, GetExperienceToNextLevel())
	return amount


## 消耗当前经验提升一级。
## @return 经验足够并升级成功时返回 true；经验不足或已满级时返回 false。
func TryLevelUp() -> bool:
	if IsMaxLevel():
		return false

	var required: int = GetExperienceToNextLevel()
	# 需求非正说明等级配置异常或已满级，此时拒绝升级，避免进入无消耗升级的坏状态。
	if required <= 0 or CurrentExperience < required:
		return false

	CurrentExperience -= required
	_apply_level_gain()
	_persist()
	LevelChanged.emit(Level)
	ExperienceChanged.emit(CurrentExperience, GetExperienceToNextLevel())
	AttributePointsGranted.emit(PendingAttributePoints)
	return true


## 直接提升指定级数，不消耗经验；供剧情推进、道具奖励或调试使用。
## @param count 期望提升的级数；非正数会被忽略。
## @return 实际提升的级数；已满级时返回 0。
func AddLevels(count: int) -> int:
	if count <= 0:
		return 0

	var applied: int = 0
	while applied < count and not IsMaxLevel():
		_apply_level_gain()
		applied += 1

	# 一级都没提升时保持静默，避免发出内容不变的信号。
	if applied <= 0:
		return 0

	# 直接提升同样可能一步抵达满级，残值处理必须与经验结算保持一致。
	if IsMaxLevel():
		CurrentExperience = 0

	_persist()
	LevelChanged.emit(Level)
	ExperienceChanged.emit(CurrentExperience, GetExperienceToNextLevel())
	AttributePointsGranted.emit(PendingAttributePoints)
	return applied


## 读取当前等级。
## @return 当前等级。
func GetLevel() -> int:
	return Level


## 读取当前等级内已累积的经验。
## @return 当前等级内的经验值。
func GetExperience() -> int:
	return CurrentExperience


## 读取升到下一级所需的经验。
## @return 升级所需经验；已满级时返回 0。
func GetExperienceToNextLevel() -> int:
	return GetExperienceRequirement(Level)


## 查询任意等级升到下一级所需的经验，供 UI、测试与数值预演复用同一份曲线规则。
## @param level 待查询的等级。
## @return 升级所需经验；高于等于满级或低于最低等级时返回 0。
func GetExperienceRequirement(level: int) -> int:
	if level < MinLevel or level >= MaxLevel:
		return 0
	return BaseExperienceRequirement + ExperienceRequirementStep * (level - MinLevel)


## 判断是否已经满级。
## @return 已满级时返回 true。
func IsMaxLevel() -> bool:
	return Level >= MaxLevel


## 领取全部挂起属性点并清零。
## @return 本次领取的属性点数量；没有可领取的点数时返回 0。
func ClaimPendingAttributePoints() -> int:
	var claimed: int = PendingAttributePoints
	if claimed <= 0:
		return 0

	PendingAttributePoints = 0
	return claimed


## 以当前经验连续结算升级，直到经验不足以再升一级或抵达满级。
## 每提升一级立即发出 LevelChanged，使逐级响应的监听者（例如升级特效）能感知每一次提升。
func _settle_level_ups() -> void:
	var leveled: bool = false
	while not IsMaxLevel():
		var required: int = GetExperienceToNextLevel()
		if required <= 0 or CurrentExperience < required:
			break
		CurrentExperience -= required
		_apply_level_gain()
		LevelChanged.emit(Level)
		leveled = true

	# 满级后不存在下一级需求，残留经验永远无法被消耗，因此直接清空保持数值自洽。
	if IsMaxLevel():
		CurrentExperience = 0

	if leveled:
		AttributePointsGranted.emit(PendingAttributePoints)


## 提升一级并累积待发放属性点；本身不发信号，由调用方统一决定信号时机。
func _apply_level_gain() -> void:
	Level += 1
	PendingAttributePoints += AttributePointsPerLevel


## 把等级与经验写回 SettingsManager。
## 写入失败只记录警告，内存数值在本次运行内仍然有效。
func _persist() -> void:
	if not PersistAcrossRuns or _settings_manager == null:
		return
	if not _settings_manager.has_method("set_setting"):
		push_warning("PlayerLevel: SettingsManager 缺少 set_setting，等级进度未持久化。")
		return

	for entry: Array in [[LevelKey, Level], [ExperienceKey, CurrentExperience]]:
		var saved: Variant = _settings_manager.call("set_setting", SettingsSection, entry[0], entry[1])
		if not (saved is bool) or not bool(saved):
			push_warning("PlayerLevel: %s 未能写入本地设置文件，本次运行内仍然有效。" % entry[0])


## 读取并校验等级存档。
## @return 收窄到 MinLevel..MaxLevel 的等级；存档缺失、类型错误时返回 MinLevel。
func _read_stored_level() -> int:
	if not PersistAcrossRuns or _settings_manager == null:
		return MinLevel
	if not _settings_manager.has_method("get_setting"):
		return MinLevel

	var stored: Variant = _settings_manager.call("get_setting", SettingsSection, LevelKey, MinLevel)
	if not (stored is int or stored is float):
		push_warning("PlayerLevel: 存档中的等级不是数值，已回退到 %d 级。" % MinLevel)
		return MinLevel

	var raw: int = int(stored)
	var clamped: int = clampi(raw, MinLevel, MaxLevel)
	if clamped != raw:
		push_warning("PlayerLevel: 存档中的等级为 %d，已收窄到 %d。" % [raw, clamped])
	return clamped


## 读取并校验当前等级内的经验存档。
## @return 收窄到 0..(本级需求-1) 的经验；满级、存档缺失或类型错误时返回 0。
func _read_stored_experience() -> int:
	if not PersistAcrossRuns or _settings_manager == null:
		return 0
	if not _settings_manager.has_method("get_setting"):
		return 0

	var required: int = GetExperienceToNextLevel()
	# 满级没有下一级需求，任何历史经验都已失去意义，直接归零而不是原样保留。
	if required <= 0:
		return 0

	var stored: Variant = _settings_manager.call("get_setting", SettingsSection, ExperienceKey, 0)
	if not (stored is int or stored is float):
		push_warning("PlayerLevel: 存档中的经验不是数值，已回退到 0。")
		return 0

	var raw: int = int(stored)
	var clamped: int = clampi(raw, 0, required - 1)
	if clamped != raw:
		push_warning("PlayerLevel: 存档中的经验为 %d，已收窄到 %d。" % [raw, clamped])
	return clamped


## 清理开发期遗留的等级与经验存档。
func _clear_stored_progress() -> void:
	if _settings_manager == null or not _settings_manager.has_method("erase_setting"):
		return

	for key: String in [LevelKey, ExperienceKey]:
		_settings_manager.call("erase_setting", SettingsSection, key)
