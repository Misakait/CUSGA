extends Resource

## 描述一次通道驻守战斗中的怪物组合。
##
## 资源只保存怪物配置；稳定边缓存和随机 encounter 选择仍由
## PassageGuardMonsterResolver 负责。

## 本次 encounter 中依次生成的怪物资源。
@export var Monsters: Array[Resource] = []
