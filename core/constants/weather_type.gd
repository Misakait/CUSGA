extends RefCounted
## 天气类型常量，保留原 C# 枚举的稳定整数值供迁移期间的脚本读取。
class_name WeatherType

## 天气类型的稳定整数值；保留原 C# 枚举的 Rain=0 语义。
enum { RAIN = 0 }

## 兼容旧命名的别名，供迁移期间的脚本读取。
const Rain: int = RAIN
