extends Resource

## 火山密库地形交互的 GDScript 数据与操作序列。
##
## 资源只描述“消耗时间后打开仓库”这一既有流程；实际时间推进和界面请求仍由
## TerrainInteractionExecutor 通过现有 C# 运行时端口执行。

## 进入密库需要消耗的行动时间；默认值保持旧 C# Resource 的 20。
@export var TimeCost: int = 20


## 构建进入密库时应按顺序执行的操作描述。
## 参数 _player：触发交互的玩家；密库流程不读取玩家内部状态。
## 参数 _terrain：当前地形实例；密库流程不修改地形运行时状态。
## 参数 _effective_time_cost_override：长按开始时的耗时快照；旧密库实现不读取该值，因此仅作为兼容输入接收。
## 返回值：先推进时间、再请求打开仓库的有序操作数组。
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
			"type": "enter_vault",
		},
	]
