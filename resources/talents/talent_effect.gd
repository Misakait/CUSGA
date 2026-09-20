extends Resource

## 天赋效果的 GDScript 抽象基类。
##
## 具体效果只修改目标玩家；天赋选择、事件广播和效果迭代由上层负责。

## 将效果应用到指定玩家。
##
## 参数 target_player：接收效果的玩家节点。
## 返回值：无。
func Apply(_target_player: Node) -> void:
	push_error("TalentEffect 基类不能直接应用，请使用具体效果脚本。")
