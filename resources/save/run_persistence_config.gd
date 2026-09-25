extends Resource
class_name RunPersistenceConfig

## 局内状态保存策略；默认只在本进程保留。运行时选择会覆盖此默认值并存入本地偏好。
## 0 表示本次运行，1 表示跨重启保存。
@export_enum("本次运行:0", "跨重启:1") var DefaultMode: int = 0
