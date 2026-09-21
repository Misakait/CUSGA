extends RefCounted

## 开发者按键序列匹配器。
##
## 该类型只做一件事：把逐次送入的字母累积成固定的开发者序列，并告诉调用方
## 是否刚好凑齐。它刻意不持有任何节点引用、不读取输入事件、不产生副作用，
## 因此可以在 tests/godot 下用纯逻辑断言覆盖，无需启动真实游戏进程。
##
## 之所以把它从面板脚本里拆出来，是因为面板脚本带有 @onready 场景依赖，
## 无法在测试中直接实例化；把状态机抽成无依赖的 RefCounted 后，序列规则
## 才具备独立可测性。
class_name DevSequenceMatcher

## 触发开发者设置的固定按键序列。
const SEQUENCE: String = "LISBAM"

## 当前已经连续匹配到的字符数量，取值范围 0 .. SEQUENCE.length()。
var _progress: int = 0


## 送入一个已归一化为大写的单字母按键。
##
## 匹配规则刻意允许「错键后从该键本身重新开始」：如果按错的那个键恰好是序列
## 首字母，进度会停在 1 而不是清零。这样玩家多按一次 L（例如 LLISBAM）依然
## 能触发，符合隐藏序列的容错预期。
##
## 参数 letter：已归一化为大写的单字母；非单字母输入会被忽略且不改变进度。
## 返回值：本次送入是否刚好凑齐完整序列；凑齐时进度自动归零，可立即再次触发。
func push_letter(letter: String) -> bool:
	if letter.length() != 1:
		return false

	if letter == SEQUENCE[_progress]:
		_progress += 1
	else:
		_progress = 1 if letter == SEQUENCE[0] else 0

	if _progress >= SEQUENCE.length():
		_progress = 0
		return true

	return false


## 读取当前已经匹配到的字符数量。
## 返回值：0 表示尚未开始匹配；等于 SEQUENCE.length() 的情况不会出现，因为凑齐即归零。
func get_progress() -> int:
	return _progress


## 清空匹配进度，让下一次送入重新从序列首字母开始。
## 返回值：无。
func reset() -> void:
	_progress = 0
