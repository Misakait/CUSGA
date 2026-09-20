@tool
extends RefCounted

## 迁移期助手：让测试套件在「C# 兼容垫片存在」时照跑，在「C# 已退役」时安全跳过。
##
## 为什么需要它：本项目有 15 个套件会用 `preload` / `load` 加载 C# 脚本，或直接读取
## `.cs` 源文本来证明「C# 与 GDScript 两侧行为一致」。C# 是迁移期的兼容垫片，物理删除后
## 这些断言必须整体跳过，而不是把套件跑挂；但 `preload("…/*.cs")` 在文件缺失时是
## **解析期错误**，会连累整个套件文件加载失败，所以必须改成惰性加载。
##
## 使用约定：
##   * 只通过本助手的 `present()` / `script()` / `read()` / `present_all()` 访问 C# 表面；
##     套件里不要再直接 `preload` / `load` / `FileAccess.get_file_as_string` 任何 `.cs` 路径。
##   * 依赖 C# 的用例开头统一写：
##         if not CS_OPTIONAL.present(PATH):
##             skip(CS_OPTIONAL.SKIP_REASON)
##             return
##     这样「C# 存在」时断言照跑，「C# 已退役」时记为 skipped 而不是 failed。

## C# 表面缺失时统一的跳过原因，便于在报告里一眼认出「因为 C# 已退役而跳过」。
const SKIP_REASON: String = "C# 兼容垫片已退役（迁移完成后的预期状态），跳过 C# 对照断言。"


## 判断某个 C# 文件当前是否存在。
##
## 参数 path：`res://` 路径。
## 返回值：存在返回 true，否则 false。
static func present(path: String) -> bool:
	return FileAccess.file_exists(path)


## 判断一组 C# 路径是否全部存在。
##
## 参数 paths：`res://` 路径数组。
## 返回值：全部存在返回 true；空数组返回 true。
static func present_all(paths: Array) -> bool:
	for path: String in paths:
		if not FileAccess.file_exists(path):
			return false
	return true


## 判断一组 C# 路径里是否至少有一个存在。
##
## 参数 paths：`res://` 路径数组。
## 返回值：至少一个存在返回 true；空数组返回 false。
static func any_present(paths: Array) -> bool:
	for path: String in paths:
		if FileAccess.file_exists(path):
			return true
	return false


## 惰性加载 C# 脚本；文件缺失时返回 null，绝不抛错（由调用方决定是否跳过）。
##
## 参数 path：`res://` 路径。
## 返回值：加载到的 Script；文件缺失或加载结果不是脚本时返回 null。
static func script(path: String) -> Script:
	if not FileAccess.file_exists(path):
		return null
	var loaded: Variant = load(path)
	if loaded is Script:
		return loaded
	return null


## 读取 C# 源码文本；文件缺失时返回空字符串。
##
## 为什么先判存在：`FileAccess.get_file_as_string` 打开缺失文件会向编辑器日志推
## 「Cannot open file」等错误；C# 退役后这些噪声会污染每次测试运行的日志，因此这里
## 先做存在性检查，让「垫片已退役」成为静默的正常状态。
##
## 参数 path：`res://` 路径。
## 返回值：文件正文；缺失时为空字符串。
static func read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 惰性加载 C# 脚本；文件缺失时回退到等价的生产 GDScript 路径。
##
## 参数 legacy_path：C# 兼容垫片的 `res://` 路径。
## 参数 fallback_path：C# 退役后等效替代的 GDScript `res://` 路径。
## 返回值：优先返回 C# 脚本；C# 缺失时返回 fallback 脚本；两者都不可用时返回 null。
static func script_or(legacy_path: String, fallback_path: String) -> Script:
	var legacy := script(legacy_path)
	if legacy != null:
		return legacy
	var fallback: Variant = load(fallback_path)
	if fallback is Script:
		return fallback
	return null
