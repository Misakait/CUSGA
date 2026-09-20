extends Resource

## Boss 地形交互的 GDScript 数据与操作序列。
##
## 本资源只保存耗时与 Boss 配置，并按旧实现顺序返回操作描述；遭遇请求、战斗切换和
## 棋盘卡移除仍由 TerrainInteractionExecutor 及既有 C# 端口执行。

## 触发 Boss 遭遇需要消耗的行动时间；默认值保持旧 C# Resource 的 20。
@export var TimeCost: int = 20

## Boss 遭遇使用的 MonsterData；迁移期继续保留原 C# Resource 对象身份。
@export var Monster: Resource


## 构建 Boss 地形交互的有序操作描述。
## 参数 _player：触发交互的玩家；Boss Resource 不读取玩家内部状态。
## 参数 _terrain：当前地形实例；由执行器原样传给遭遇请求。
## 参数 _effective_time_cost_override：长按开始时的耗时快照；旧 Boss 实现不读取该值，因此仅作为兼容输入接收。
## 返回值：依次推进时间、请求 Boss 遭遇并移除源卡的操作数组。
func build_ops(
	_player: Variant,
	_terrain: Variant,
	_effective_time_cost_override: Variant = null
) -> Array[Dictionary]:
	return [
		{
			"type": "pass_time",
			"amount": TimeCost,
		},
		{
			"type": "spawn_monster",
			"monster": Monster,
		},
		{
			"type": "remove_source_card",
		},
	]
