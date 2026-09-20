extends Node

## 天气全局管理器的 GDScript 实现。
##
## 该 Autoload 只负责持有当前天气并广播变更；天气配置本身由 weather_data.gd
## 保存，运行时消费者通过稳定的 Resource 字段读取，保留旧 C# 管理器的边界语义。

## 当前生效的天气配置；未设置时保持 null。
@export var CurrentWeather: Resource

## 天气变更通知，参数为新的天气 Resource。
signal WeatherChanged(newWeather: Resource)


## 设置当前天气并广播变更。
##
## 参数 new_weather：新的天气配置资源。
func ChangeWeather(new_weather: Resource) -> void:
	CurrentWeather = new_weather
	emit_signal(&"WeatherChanged", CurrentWeather)
	print("[环境系统] 天气变更为：", str(CurrentWeather.get("WeatherName")))
