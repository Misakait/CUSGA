extends Resource

## 农场地形交互的 GDScript 并行实现。
##
## 资源只描述耗时和打开农场面板请求；实际时间流逝与 GameplayPort 信号
## 继续由 TerrainInteractionExecutor 和既有 C# TerrainOp 执行。

## 完成交互消耗的游戏时间点数。
@export var TimeCost: int = 20


## 根据地形占用状态构建与旧 FarmingInteraction 相同的操作序列。
##
## 参数 player：统一地形交互入口传入的玩家；本交互不读取玩家状态。
## 参数 terrain：被交互的 TerrainInstance，用于判断农场是否已占用。
## 参数 effective_time_cost_override：统一长按入口的耗时快照；农场保持旧行为并忽略它。
## 返回值：始终包含时间操作，未占用时追加打开农场面板操作。
func build_ops(
	_player: Object,
	terrain: Object,
	_effective_time_cost_override: Variant = null
) -> Array[Dictionary]:
	var ops: Array[Dictionary] = [{"type": "pass_time", "amount": TimeCost}]
	if terrain != null and not bool(terrain.get("IsOccupied")):
		ops.append({"type": "open_farming_panel"})
	return ops
