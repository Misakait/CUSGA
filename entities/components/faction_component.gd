extends Node

## 实体阵营组件。
##
## 组件只保存阵营枚举值；阵营判断和目标选择继续由现有战斗调用方负责。

## 当前阵营：Hostile=0、PlayerSummon=1、Neutral=2；运行时可由 Monster 初始化更新。
@export_enum("Hostile:0", "PlayerSummon:1", "Neutral:2") var Faction: int = 0
