## 本地设置管理器。
## 该自动加载节点集中维护玩家偏好的读取和写入，让具体功能只声明自己的“分组 + 键 + 默认值”，
## 从而避免多个场景各自处理配置文件、默认值和损坏文件的恢复逻辑。
extends Node

## 玩家本地设置文件的固定保存位置。
## 使用 user:// 可避免将运行时偏好写入项目资源目录；修改该路径会使既有偏好不再被读取。
const SETTINGS_FILE_PATH: String = "user://settings.cfg"

## 内存中的配置对象。
## 它在自动加载初始化时读取一次，并在每次写入后立即保存；读取失败时会被清空以保证默认值回退可靠。
var _settings_config: ConfigFile = ConfigFile.new()

## 初始化本地设置缓存。
## @return void 无返回值。
func _ready() -> void:
	_load_settings()

## 读取一个设置值；当分组、键或配置文件不存在时返回调用方提供的默认值。
## @param section 设置所属的功能分组，用于避免不同功能的键名冲突。
## @param key 分组内的设置键名。
## @param default_value 没有已保存值时应使用的安全默认值。
## @return Variant 已保存值或 default_value。
func get_setting(section: String, key: String, default_value: Variant) -> Variant:
	return _settings_config.get_value(section, key, default_value)

## 更新一个设置值并立即保存到本地文件。
## 即使磁盘保存失败，内存中的新值仍会保留至本次运行结束，避免玩家当前操作被回滚。
## @param section 设置所属的功能分组。
## @param key 分组内的设置键名。
## @param value 需要保存的设置值。
## @return bool 写入磁盘是否成功。
func set_setting(section: String, key: String, value: Variant) -> bool:
	_settings_config.set_value(section, key, value)
	# 本次将内存配置落盘的错误码；OK 表示偏好已成功跨重启保存。
	var save_error: Error = _settings_config.save(SETTINGS_FILE_PATH)
	if save_error != OK:
		push_error("无法保存本地设置：%s（错误码：%s）" % [SETTINGS_FILE_PATH, save_error])
		return false
	return true

## 从本地文件加载所有设置。
## 文件尚未创建是首次运行的正常情况；其他加载失败均丢弃可能不完整的数据，以确保调用方得到明确默认值。
## @return void 无返回值。
func _load_settings() -> void:
	# 读取本地配置文件的错误码；首次运行的 ERR_FILE_NOT_FOUND 会被视为正常默认状态。
	var load_error: Error = _settings_config.load(SETTINGS_FILE_PATH)
	if load_error == OK:
		return

	_settings_config.clear()
	if load_error != ERR_FILE_NOT_FOUND:
		push_warning("本地设置文件无法读取，已使用默认设置：%s（错误码：%s）" % [SETTINGS_FILE_PATH, load_error])
